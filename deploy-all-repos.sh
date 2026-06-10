#!/bin/bash

# Dependabot Auto-Merge Workflow - Complete Deployment Script
# This script deploys the workflow and email secrets to ALL your repositories
# 
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated: https://cli.github.com/
#   - jq installed: https://stedolan.github.io/jq/install/
#
# Usage: 
#   bash deploy-all-repos.sh              # Dry run first to see what will happen
#   bash deploy-all-repos.sh --confirm    # Actually deploy to all repos

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKFLOW_SOURCE_REPO="meatflavourdev/Ingress-IITC-Multi-Export"
WORKFLOW_FILE=".github/workflows/dependabot-auto-merge.yml"
COMMIT_MESSAGE="🤖 Add Dependabot auto-merge workflow"

# Email configuration (Gmail)
EMAIL_SERVER="smtp.gmail.com"
EMAIL_PORT="587"
EMAIL_USERNAME="jeremy@meatflavour.dev"
EMAIL_PASSWORD="uarfctdmsyisxsxwn"
EMAIL_FROM="github-actions@meatflavour.dev"

# Deployment mode
CONFIRM_MODE=false
if [[ "$1" == "--confirm" ]]; then
    CONFIRM_MODE=true
fi

echo -e "${BLUE}=================================="
echo "Dependabot Workflow Deployment"
echo "==================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}✓ Checking prerequisites...${NC}"
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) not found.${NC}"
    echo "   Install from: https://cli.github.com/"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq not found.${NC}"
    echo "   Install from: https://stedolan.github.io/jq/install/"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites found${NC}"
echo ""

# Verify GitHub authentication
USER=$(gh api user -q '.login' 2>/dev/null) || {
    echo -e "${RED}❌ Not authenticated with GitHub CLI${NC}"
    echo "   Run: gh auth login"
    exit 1
}

echo -e "${BLUE}🔐 Authenticated as: ${GREEN}$USER${NC}"
echo ""

# Download workflow file from source repo
echo -e "${YELLOW}📥 Downloading workflow file...${NC}"
WORKFLOW_CONTENT=$(gh api repos/$WORKFLOW_SOURCE_REPO/contents/$WORKFLOW_FILE --jq '.content' 2>/dev/null | base64 -d) || {
    echo -e "${RED}❌ Failed to download workflow file${NC}"
    echo "   Expected at: $WORKFLOW_SOURCE_REPO/$WORKFLOW_FILE"
    exit 1
}

echo -e "${GREEN}✓ Workflow file downloaded ($(echo "$WORKFLOW_CONTENT" | wc -c) bytes)${NC}"
echo ""

# Get list of all user repositories
echo -e "${YELLOW}📦 Fetching your repositories...${NC}"
REPOS=$(gh repo list "$USER" --limit 1000 --json name --jq '.[].name' 2>/dev/null) || {
    echo -e "${RED}❌ Failed to fetch repositories${NC}"
    exit 1
}

# Convert to array
mapfile -t REPO_ARRAY <<< "$REPOS"
TOTAL_REPOS=${#REPO_ARRAY[@]}

echo -e "${GREEN}✓ Found $TOTAL_REPOS repositories${NC}"
echo ""

# Summary before confirmation
echo -e "${BLUE}📋 Deployment Summary:${NC}"
echo "   Repositories to update: $TOTAL_REPOS"
echo "   Workflow file: $WORKFLOW_FILE"
echo "   Email recipient: jeremy@meatflavour.dev"
echo "   SMTP Server: $EMAIL_SERVER:$EMAIL_PORT"
echo ""

if [ "$CONFIRM_MODE" = false ]; then
    echo -e "${YELLOW}🧪 Running in DRY RUN mode (no changes will be made)${NC}"
    echo ""
    echo -e "${YELLOW}To actually deploy, run:${NC}"
    echo -e "${GREEN}   bash deploy-all-repos.sh --confirm${NC}"
    echo ""
fi

# Counters
DEPLOYED=0
FAILED=0
SKIPPED=0
declare -a FAILED_REPOS
declare -a SKIPPED_REPOS

# Deploy to each repository
echo -e "${BLUE}Starting deployment...${NC}"
echo ""

for i in "${!REPO_ARRAY[@]}"; do
    REPO_NAME="${REPO_ARRAY[$i]}"
    CURRENT=$((i + 1))
    REPO_FULL_NAME="$USER/$REPO_NAME"
    
    # Calculate percentage
    PERCENTAGE=$((CURRENT * 100 / TOTAL_REPOS))
    
    printf "${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | $REPO_NAME"
    
    # Skip the source repo
    if [ "$REPO_FULL_NAME" == "$WORKFLOW_SOURCE_REPO" ]; then
        printf "\r${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | ${YELLOW}ℹ️  $REPO_NAME (source repo)${NC}\n"
        SKIPPED=$((SKIPPED + 1))
        SKIPPED_REPOS+=("$REPO_NAME")
        continue
    fi
    
    if [ "$CONFIRM_MODE" = true ]; then
        # Set email secrets
        gh secret set EMAIL_SERVER --body "$EMAIL_SERVER" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_PORT --body "$EMAIL_PORT" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_USERNAME --body "$EMAIL_USERNAME" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_PASSWORD --body "$EMAIL_PASSWORD" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_FROM --body "$EMAIL_FROM" -R "$REPO_FULL_NAME" 2>/dev/null || true
        
        # Create or update workflow file
        if gh api repos/$USER/$REPO_NAME/contents/.github/workflows/dependabot-auto-merge.yml \
            -X PUT \
            -f message="$COMMIT_MESSAGE" \
            -f content="$(echo -n "$WORKFLOW_CONTENT" | base64)" \
            2>/dev/null | grep -q '"commit"'; then
            printf "\r${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | ${GREEN}✅ $REPO_NAME${NC}\n"
            DEPLOYED=$((DEPLOYED + 1))
        else
            printf "\r${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | ${RED}❌ $REPO_NAME (failed)${NC}\n"
            FAILED=$((FAILED + 1))
            FAILED_REPOS+=("$REPO_NAME")
        fi
    else
        printf "\r${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | ${YELLOW}[DRY RUN]${NC} $REPO_NAME\n"
        DEPLOYED=$((DEPLOYED + 1))
    fi
done

echo ""
echo -e "${BLUE}=================================="
echo "Deployment Complete"
echo "==================================${NC}"

if [ "$CONFIRM_MODE" = false ]; then
    echo -e "${YELLOW}Mode: DRY RUN (no changes made)${NC}"
fi

echo -e "${GREEN}✅ Deployed to: $DEPLOYED repositories${NC}"
echo -e "${RED}❌ Failed: $FAILED repositories${NC}"
echo -e "${YELLOW}ℹ️  Skipped: $SKIPPED repositories${NC}"
echo -e "${BLUE}📊 Total: $TOTAL_REPOS repositories${NC}"

if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed repositories:${NC}"
    for repo in "${FAILED_REPOS[@]}"; do
        echo -e "   ${RED}• $repo${NC}"
    done
fi

echo ""
echo -e "${BLUE}📧 Email Configuration:${NC}"
echo -e "   Server: ${GREEN}$EMAIL_SERVER:$EMAIL_PORT${NC}"
echo -e "   From: ${GREEN}$EMAIL_FROM${NC}"
echo -e "   To: ${GREEN}jeremy@meatflavour.dev${NC}"

echo ""
echo -e "${GREEN}✨ All done!${NC}"

if [ "$CONFIRM_MODE" = false ]; then
    echo ""
    echo -e "${YELLOW}📋 Next Steps:${NC}"
    echo -e "   1. Review the dry run output above"
    echo -e "   2. Run with --confirm flag to deploy:"
    echo -e "      ${GREEN}bash deploy-all-repos.sh --confirm${NC}"
fi

echo ""
