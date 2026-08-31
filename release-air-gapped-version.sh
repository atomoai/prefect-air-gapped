#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if upstream remote exists, if not add it
if ! git remote get-url upstream >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Upstream remote not found. Adding it...${NC}"
    git remote add upstream https://github.com/PrefectHQ/prefect.git
    echo -e "${GREEN}✓ Added upstream remote${NC}"
    echo ""
fi

# The rebase regenerates uv.lock instead of merging it (see .gitattributes), so
# uv has to be available before we start moving branches around.
if ! command -v uv >/dev/null 2>&1; then
    echo -e "${RED}❌ uv not found on PATH — required to regenerate uv.lock during the rebase${NC}"
    exit 1
fi

# Fetch latest tags from upstream
echo -e "${BLUE}📥 Fetching latest tags from upstream...${NC}"
git fetch upstream --tags
echo -e "${BLUE}⏫ Pushing fetched tags to origin...${NC}"
git push origin --tags
echo ""



# Now check for the argument
UPSTREAM_TAG="${1}"

if [ -z "$UPSTREAM_TAG" ]; then
    echo -e "${RED}Usage: $0 <upstream-tag>${NC}"
    echo ""
    echo "Example: $0 3.1.0"
    echo ""
    if git tag --sort=-version:refname | grep -q "^3\."; then
        echo "Available recent tags:"
        git tag --sort=-version:refname | grep "^3\." | head -10
    else
        echo "No version 3.x tags found."
    fi
    exit 1
fi


echo -e "${BLUE}🔄 Rebasing air-gapped/patches onto tag ${UPSTREAM_TAG}...${NC}"
echo ""

# Check if tag exists
if ! git rev-parse "refs/tags/${UPSTREAM_TAG}" >/dev/null 2>&1; then
    echo -e "${RED}❌ Tag ${UPSTREAM_TAG} not found!${NC}"
    echo ""
    echo "Available tags:"
    git tag --sort=-version:refname | grep "^3\." | head -20
    exit 1
fi

echo -e "${GREEN}✓ Tag ${UPSTREAM_TAG} found${NC}"

# Save current branch
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${BLUE}📍 Current branch: ${CURRENT_BRANCH}${NC}"

# Stash any uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}💾 Stashing uncommitted changes...${NC}"
    git stash push -m "Auto-stash before rebasing onto ${UPSTREAM_TAG}"
    STASHED=true
else
    STASHED=false
fi

# Reset main branch to upstream/main
echo -e "${BLUE}📥 Resetting main branch to upstream/main...${NC}"
git checkout main
git reset upstream/main --hard
echo ""

# Checkout air-gapped/patches
echo ""
echo -e "${YELLOW}🔀 Checking out air-gapped/patches...${NC}"
git checkout air-gapped/patches

# Find the current base of air-gapped/patches
echo -e "${YELLOW}🔍 Finding current base of air-gapped/patches...${NC}"
OLD_BASE=$(git merge-base main air-gapped/patches)
OLD_BASE_SHORT=$(git rev-parse --short ${OLD_BASE})
echo -e "${BLUE}Current base: ${OLD_BASE_SHORT}${NC}"

# Count commits that will be rebased
COMMIT_COUNT=$(git rev-list --count ${OLD_BASE}..air-gapped/patches)
echo -e "${BLUE}Commits to rebase: ${COMMIT_COUNT}${NC}"

# Make the merge=binary rule from .gitattributes actually apply to this rebase.
# A tracked .gitattributes only takes effect once the commit introducing it has
# been applied, and our lock-touching patches come earlier in the series -- so
# during the rebase git would still try (and sometimes succeed at) a textual
# merge of the lockfile, which is how it silently drifted before. info/attributes
# is per-clone and independent of whichever tree is checked out mid-rebase.
ATTRIBUTES_FILE="$(git rev-parse --git-path info/attributes)"
if ! grep -qs '^uv\.lock[[:space:]]\+merge=binary' "${ATTRIBUTES_FILE}"; then
    mkdir -p "$(dirname "${ATTRIBUTES_FILE}")"
    echo 'uv.lock merge=binary' >> "${ATTRIBUTES_FILE}"
    echo -e "${GREEN}✓ Installed 'uv.lock merge=binary' in ${ATTRIBUTES_FILE}${NC}"
fi

rebase_in_progress() {
    [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]
}

# Perform the rebase using --onto to transplant patches directly onto the tag.
#
# uv.lock conflicts here are expected and are never real conflicts: our patches
# pin extra dependencies, upstream moves their shared transitive versions every
# release, and the lockfile is generated output. The only correct resolution is
# to discard the patched lock and re-resolve, so do that automatically and keep
# going. Anything else that conflicts still stops the release for a human.
REBASE_OK=false
echo ""
echo -e "${YELLOW}🔀 Rebasing ${COMMIT_COUNT} commits onto ${UPSTREAM_TAG} (using --onto)...${NC}"
if git rebase --onto "refs/tags/${UPSTREAM_TAG}" "${OLD_BASE}" air-gapped/patches; then
    REBASE_OK=true
else
    while rebase_in_progress; do
        CONFLICTED=$(git diff --name-only --diff-filter=U)
        if [ "${CONFLICTED}" != "uv.lock" ]; then
            break
        fi
        echo ""
        echo -e "${BLUE}🔁 uv.lock conflict — discarding the patched lock and re-resolving...${NC}"
        git checkout --ours -- uv.lock
        if ! uv lock; then
            echo -e "${RED}❌ uv lock failed — the pinned dependencies do not resolve against ${UPSTREAM_TAG}${NC}"
            echo -e "${YELLOW}   Loosen the constraints in pyproject.toml, then:${NC}"
            echo "     uv lock && git add pyproject.toml uv.lock && git rebase --continue"
            break
        fi
        git add uv.lock
        if GIT_EDITOR=true git rebase --continue; then
            REBASE_OK=true
            break
        fi
    done
fi

if [ "${REBASE_OK}" = true ]; then
    echo ""
    echo -e "${GREEN}✅ Rebase completed successfully!${NC}"

    # The lock was regenerated mid-rebase, and a cleanly-applied lock patch can
    # still leave it describing a resolution that no longer exists. Verify before
    # anything is published.
    echo ""
    echo -e "${BLUE}🔎 Validating uv.lock against pyproject.toml...${NC}"
    if ! uv lock --check; then
        echo -e "${RED}❌ uv.lock is out of sync with pyproject.toml${NC}"
        echo -e "${YELLOW}   Run 'uv lock', commit the result, then re-run this script.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ uv.lock is consistent${NC}"

    # Push the rebased patches branch
    echo ""
    echo -e "${YELLOW}📤 Pushing air-gapped/patches...${NC}"
    git push origin air-gapped/patches --force-with-lease

    # Create release branch
    RELEASE_BRANCH="air-gapped/releases/${UPSTREAM_TAG}"
    AIR_GAPPED_TAG="air-gapped-${UPSTREAM_TAG}"

    echo ""
    echo -e "${YELLOW}🌿 Creating release branch: ${RELEASE_BRANCH}...${NC}"
    git checkout -b "${RELEASE_BRANCH}"

    # Create and push the tag
    echo -e "${YELLOW}🏷️  Creating tag: ${AIR_GAPPED_TAG}...${NC}"
    git tag -a "${AIR_GAPPED_TAG}" -m "Air-gapped release ${UPSTREAM_TAG}"

    # Push both branch and tag
    echo -e "${YELLOW}📤 Pushing release branch and tag...${NC}"
    git push origin "${RELEASE_BRANCH}"
    git push origin "${AIR_GAPPED_TAG}"

    echo ""
    echo -e "${GREEN}✅ Successfully rebased and released ${UPSTREAM_TAG}${NC}"
    echo ""
    echo -e "${BLUE}📋 Summary:${NC}"
    echo "  • main: unchanged (still tracks upstream/main)"
    echo "  • air-gapped/patches: ${COMMIT_COUNT} commits transplanted from ${OLD_BASE_SHORT} → ${UPSTREAM_TAG}"
    echo "  • ${RELEASE_BRANCH}: created from rebased patches"
    echo "  • ${AIR_GAPPED_TAG}: tag created and pushed"
    echo "  • air-gapped/main: unchanged (update via PR)"
    echo ""
    echo -e "${BLUE}🔀 Next steps:${NC}"
    echo "  1. Create PR: air-gapped/patches → air-gapped/main"
    echo "     gh pr create --base air-gapped/main --head air-gapped/patches --title \"Sync to ${UPSTREAM_TAG}\""
    echo "  2. Review and merge the PR"
    echo "  3. Docker images will build from tag: ${AIR_GAPPED_TAG}"

else
    echo ""
    echo -e "${RED}⚠️  Conflicts detected during rebase!${NC}"
    echo ""
    echo -e "${YELLOW}To resolve conflicts:${NC}"
    echo "  0. Never hand-merge uv.lock: git checkout --ours -- uv.lock && uv lock"
    echo "  1. Fix conflicts in the listed files"
    echo "  2. git add <resolved-files>"
    echo "  3. git rebase --continue"
    echo "  4. Repeat until rebase completes"
    echo ""
    echo -e "${YELLOW}Then complete the release:${NC}"
    echo "  git push origin air-gapped/patches --force-with-lease"
    echo "  git checkout -b air-gapped/releases/${UPSTREAM_TAG}"
    echo "  git tag -a air-gapped-${UPSTREAM_TAG} -m \"Air-gapped release ${UPSTREAM_TAG}\""
    echo "  git push origin air-gapped/releases/${UPSTREAM_TAG}"
    echo "  git push origin air-gapped-${UPSTREAM_TAG}"
    echo "  gh pr create --base air-gapped/main --head air-gapped/patches --title \"Sync to ${UPSTREAM_TAG}\""
    echo ""
    echo -e "${YELLOW}Or to abort:${NC}"
    echo "  git rebase --abort"
    exit 1
fi

# Return to original branch
echo ""
echo -e "${YELLOW}🔙 Returning to ${CURRENT_BRANCH}...${NC}"
git checkout "$CURRENT_BRANCH"

# Restore stashed changes if any
if [ "$STASHED" = true ]; then
    echo -e "${YELLOW}💾 Restoring stashed changes...${NC}"
    git stash pop
fi

echo ""
echo -e "${GREEN}✨ All done!${NC}"
