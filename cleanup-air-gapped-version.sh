#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for the argument
VERSION="${1}"

if [ -z "$VERSION" ]; then
    echo -e "${RED}Usage: $0 <version>${NC}"
    echo ""
    echo "Example: $0 3.1.0"
    echo ""
    echo "This will delete:"
    echo "  • Tag: air-gapped-<version>"
    echo "  • Branch: air-gapped/releases/<version>"
    echo ""
    if git tag --sort=-version:refname | grep -q "^air-gapped-3\."; then
        echo "Available air-gapped tags:"
        git tag --sort=-version:refname | grep "^air-gapped-3\." | head -10
    else
        echo "No air-gapped tags found."
    fi
    exit 1
fi

# Construct tag and branch names (matching release script pattern)
AIR_GAPPED_TAG="air-gapped-${VERSION}"
RELEASE_BRANCH="air-gapped/releases/${VERSION}"

echo -e "${BLUE}🧹 Cleaning up air-gapped version ${VERSION}...${NC}"
echo ""

# Track what exists
TAG_EXISTS_LOCAL=false
TAG_EXISTS_REMOTE=false
BRANCH_EXISTS_LOCAL=false
BRANCH_EXISTS_REMOTE=false

# Check if tag exists locally
if git rev-parse "refs/tags/${AIR_GAPPED_TAG}" >/dev/null 2>&1; then
    TAG_EXISTS_LOCAL=true
fi

# Check if tag exists remotely
if git ls-remote --tags origin "${AIR_GAPPED_TAG}" >/dev/null 2>&1; then
    TAG_EXISTS_REMOTE=true
fi

# Check if branch exists locally
if git rev-parse --verify "refs/heads/${RELEASE_BRANCH}" >/dev/null 2>&1; then
    BRANCH_EXISTS_LOCAL=true
fi

# Check if branch exists remotely
if git ls-remote --heads origin "${RELEASE_BRANCH}" >/dev/null 2>&1; then
    BRANCH_EXISTS_REMOTE=true
fi

# Show what will be deleted
echo -e "${YELLOW}📋 Items to delete:${NC}"
if [ "$TAG_EXISTS_LOCAL" = true ] || [ "$TAG_EXISTS_REMOTE" = true ]; then
    echo -e "  • Tag: ${AIR_GAPPED_TAG}"
    if [ "$TAG_EXISTS_LOCAL" = true ]; then
        echo -e "    ${BLUE}  └─ Local: ✓ exists${NC}"
    fi
    if [ "$TAG_EXISTS_REMOTE" = true ]; then
        echo -e "    ${BLUE}  └─ Remote: ✓ exists${NC}"
    fi
fi
if [ "$BRANCH_EXISTS_LOCAL" = true ] || [ "$BRANCH_EXISTS_REMOTE" = true ]; then
    echo -e "  • Branch: ${RELEASE_BRANCH}"
    if [ "$BRANCH_EXISTS_LOCAL" = true ]; then
        echo -e "    ${BLUE}  └─ Local: ✓ exists${NC}"
    fi
    if [ "$BRANCH_EXISTS_REMOTE" = true ]; then
        echo -e "    ${BLUE}  └─ Remote: ✓ exists${NC}"
    fi
fi

# Check if anything exists
if [ "$TAG_EXISTS_LOCAL" = false ] && [ "$TAG_EXISTS_REMOTE" = false ] && \
   [ "$BRANCH_EXISTS_LOCAL" = false ] && [ "$BRANCH_EXISTS_REMOTE" = false ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Nothing to delete. Tag and branch do not exist.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}⚠️  WARNING: This will permanently delete the tag and branch!${NC}"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

echo ""

# Save current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ -n "$CURRENT_BRANCH" ]; then
    echo -e "${BLUE}📍 Current branch: ${CURRENT_BRANCH}${NC}"
fi

# Delete local tag
if [ "$TAG_EXISTS_LOCAL" = true ]; then
    echo -e "${YELLOW}🗑️  Deleting local tag: ${AIR_GAPPED_TAG}...${NC}"
    git tag -d "${AIR_GAPPED_TAG}"
    echo -e "${GREEN}✓ Deleted local tag${NC}"
fi

# Delete remote tag
if [ "$TAG_EXISTS_REMOTE" = true ]; then
    echo -e "${YELLOW}🗑️  Deleting remote tag: ${AIR_GAPPED_TAG}...${NC}"
    git push origin --delete "${AIR_GAPPED_TAG}" || {
        echo -e "${RED}❌ Failed to delete remote tag${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Deleted remote tag${NC}"
fi

# Switch away from branch if we're on it
if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" = "$RELEASE_BRANCH" ]; then
    echo -e "${YELLOW}🔀 Switching away from ${RELEASE_BRANCH}...${NC}"
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Could not switch branches automatically. Please switch manually.${NC}"
    }
fi

# Delete local branch
if [ "$BRANCH_EXISTS_LOCAL" = true ]; then
    echo -e "${YELLOW}🗑️  Deleting local branch: ${RELEASE_BRANCH}...${NC}"
    git branch -D "${RELEASE_BRANCH}" || {
        echo -e "${RED}❌ Failed to delete local branch${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Deleted local branch${NC}"
fi

# Delete remote branch
if [ "$BRANCH_EXISTS_REMOTE" = true ]; then
    echo -e "${YELLOW}🗑️  Deleting remote branch: ${RELEASE_BRANCH}...${NC}"
    git push origin --delete "${RELEASE_BRANCH}" || {
        echo -e "${RED}❌ Failed to delete remote branch${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Deleted remote branch${NC}"
fi

# Return to original branch if we switched away
if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
    echo ""
    echo -e "${YELLOW}🔙 Returning to ${CURRENT_BRANCH}...${NC}"
    git checkout "$CURRENT_BRANCH" 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Could not return to ${CURRENT_BRANCH}${NC}"
    }
fi

echo ""
echo -e "${GREEN}✅ Successfully cleaned up version ${VERSION}${NC}"
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
if [ "$TAG_EXISTS_LOCAL" = true ] || [ "$TAG_EXISTS_REMOTE" = true ]; then
    echo "  • Tag ${AIR_GAPPED_TAG}: deleted"
fi
if [ "$BRANCH_EXISTS_LOCAL" = true ] || [ "$BRANCH_EXISTS_REMOTE" = true ]; then
    echo "  • Branch ${RELEASE_BRANCH}: deleted"
fi
echo ""
echo -e "${GREEN}✨ All done!${NC}"

