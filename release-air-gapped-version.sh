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

# Perform the rebase using --onto to transplant patches directly onto the tag
echo ""
echo -e "${YELLOW}🔀 Rebasing ${COMMIT_COUNT} commits onto ${UPSTREAM_TAG} (using --onto)...${NC}"
if git rebase --onto "refs/tags/${UPSTREAM_TAG}" "${OLD_BASE}" air-gapped/patches; then
    echo ""
    echo -e "${GREEN}✅ Rebase completed successfully!${NC}"

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
