#!/bin/bash

# Dependabot Auto-Merge Workflow Deployment Script
# Deploys the workflow and sets up email secrets across all repositories
# 
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - jq installed for JSON parsing
#
# Usage: ./deploy-dependabot-workflow.sh [--dry-run]

set -e

# Configuration
WORKFLOW_SOURCE_REPO="meatflavourdev/Ingress-IITC-Multi-Export"
WORKFLOW_FILE=".github/workflows/dependabot-auto-merge.yml"
COMMIT_MESSAGE="Add Dependabot auto-merge workflow"
DRY_RUN=false

# Email configuration
EMAIL_SERVER="smtp.gmail.com"
EMAIL_PORT="587"
EMAIL_USERNAME="jeremy@meatflavour.dev"
EMAIL_PASSWORD="uarfctdmsyisxsxwn"  # App password with spaces removed
EMAIL_FROM="github-actions@meatflavour.dev"

# Parse arguments
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🧪 DRY RUN MODE - No changes will be made"
fi

echo "=================================="
echo "Dependabot Workflow Deployment"
echo "=================================="
echo ""

# Check prerequisites
echo "✓ Checking prerequisites..."
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) not found. Please install it: https://cli.github.com"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found. Please install it: https://stedolan.github.io/jq/install/"
    exit 1
fi

echo "✓ All prerequisites met"
echo ""

# Get authenticated user
USER=$(gh api user -q '.login')
echo "🔐 Authenticated as: $USER"
echo ""

# Download workflow file from source repo
echo "📥 Downloading workflow file from $WORKFLOW_SOURCE_REPO..."
WORKFLOW_CONTENT=$(gh repo view "$WORKFLOW_SOURCE_REPO" --json description &>/dev/null && gh api repos/$WORKFLOW_SOURCE_REPO/contents/$WORKFLOW_FILE -q '.content' | base64 -d || echo "")

if [ -z "$WORKFLOW_CONTENT" ]; then
    echo "❌ Failed to download workflow file. Make sure it exists in $WORKFLOW_SOURCE_REPO/$WORKFLOW_FILE"
    exit 1
fi

echo "✓ Workflow file downloaded"
echo ""

# Get list of all user repositories
echo "📦 Fetching repositories..."
REPOS=$(gh repo list "$USER" --limit 1000 --json name,owner --jq '.[] | select(.owner.login == "'$USER'") | .name')

# Convert to array
mapfile -t REPO_ARRAY <<< "$REPOS"
TOTAL_REPOS=${#REPO_ARRAY[@]}

echo "📊 Found $TOTAL_REPOS repositories"
echo ""

# Counter for tracking progress
DEPLOYED=0
FAILED=0
SKIPPED=0

# Deploy to each repository
for i in "${!REPO_ARRAY[@]}"; do
    REPO_NAME="${REPO_ARRAY[$i]}"
    CURRENT=$((i + 1))
    REPO_FULL_NAME="$USER/$REPO_NAME"
    
    printf "\r[$CURRENT/$TOTAL_REPOS] Processing: $REPO_NAME"
    
    # Skip the source repo
    if [ "$REPO_FULL_NAME" == "$WORKFLOW_SOURCE_REPO" ]; then
        printf "\r[$CURRENT/$TOTAL_REPOS] ℹ️  $REPO_NAME (source repo - skipped)                    \n"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    if [ "$DRY_RUN" = false ]; then
        # Set email secrets
        echo "" >/dev/null
        gh secret set EMAIL_SERVER --body "$EMAIL_SERVER" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_PORT --body "$EMAIL_PORT" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_USERNAME --body "$EMAIL_USERNAME" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_PASSWORD --body "$EMAIL_PASSWORD" -R "$REPO_FULL_NAME" 2>/dev/null || true
        gh secret set EMAIL_FROM --body "$EMAIL_FROM" -R "$REPO_FULL_NAME" 2>/dev/null || true
        
        # Create or update workflow file via API
        WORKFLOW_B64=$(echo "$WORKFLOW_CONTENT" | base64)
        
        # Try to create/update the file
        if gh api repos/"$USER"/"$REPO_NAME"/contents/.github/workflows/dependabot-auto-merge.yml \
            --input - \
            -F message="$COMMIT_MESSAGE" \
            -F content="$WORKFLOW_CONTENT" \
            2>/dev/null | grep -q "commit"; then
            printf "\r[$CURRENT/$TOTAL_REPOS] ✅ $REPO_NAME                    \n"
            DEPLOYED=$((DEPLOYED + 1))
        else
            printf "\r[$CURRENT/$TOTAL_REPOS] ❌ $REPO_NAME (deploy failed)          \n"
            FAILED=$((FAILED + 1))
        fi
    else
        printf "\r[$CURRENT/$TOTAL_REPOS] [DRY RUN] Would deploy to: $REPO_NAME        \n"
        DEPLOYED=$((DEPLOYED + 1))
    fi
done

echo ""
echo "=================================="
echo "Deployment Summary"
echo "=================================="
if [ "$DRY_RUN" = true ]; then
    echo "Mode: DRY RUN (no changes made)"
fi
echo "✅ Deployed to: $DEPLOYED repositories"
echo "❌ Failed: $FAILED repositories"
echo "ℹ️  Skipped: $SKIPPED repositories"
echo "📊 Total: $TOTAL_REPOS repositories"
echo ""
echo "📧 Email Configuration:"
echo "   Server: $EMAIL_SERVER:$EMAIL_PORT"
echo "   From: $EMAIL_FROM"
echo "   To: jeremy@meatflavour.dev"
echo "=================================="
echo ""
echo "✨ Deployment complete!"
echo "📬 Email reports will be sent to: jeremy@meatflavour.dev"
echo ""
