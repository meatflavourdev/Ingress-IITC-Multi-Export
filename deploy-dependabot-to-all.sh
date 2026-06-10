#!/bin/bash

# ============================================================================
# Dependabot Auto-Merge Workflow - Production Deployment Script
# ============================================================================
# Deploys the dependabot-auto-merge.yml workflow to ALL user-owned repositories
# Sets up required email secrets for Gmail notifications
# 
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated: https://cli.github.com/
#   - jq installed: https://stedolan.github.io/jq/install/
#   - Gmail account with App Password configured
#
# Usage:
#   # First, test with dry-run (shows what will happen)
#   bash deploy-dependabot-to-all.sh --dry-run
#
#   # Then deploy to all repositories
#   bash deploy-dependabot-to-all.sh --deploy
#
#   # Deploy to single repository
#   bash deploy-dependabot-to-all.sh --deploy --repo REPO_NAME
#
# ============================================================================

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_VERSION="1.0.0"
WORKFLOW_SOURCE_REPO="meatflavourdev/Ingress-IITC-Multi-Export"
WORKFLOW_FILE=".github/workflows/dependabot-auto-merge.yml"
WORKFLOW_COMMIT_MSG="🤖 Add Dependabot auto-merge workflow with email notifications"

# Email Configuration (Gmail)
EMAIL_SERVER="smtp.gmail.com"
EMAIL_PORT="587"
EMAIL_USERNAME="jeremy@meatflavour.dev"
EMAIL_PASSWORD="uarfctdmsyisxsxwn"
EMAIL_FROM="github-actions@meatflavour.dev"

# Script Configuration
DEPLOY_MODE=false
DRY_RUN_MODE=true
SINGLE_REPO=""
LOG_DIR="./deployment-logs"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
PROGRESS_FILE="$LOG_DIR/progress-$(date +%Y%m%d-%H%M%S).txt"

# ============================================================================
# Colors for Terminal Output
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[${timestamp}] [ERROR] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}] [WARN] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
        INFO)
            echo -e "${BLUE}[${timestamp}] [INFO] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[${timestamp}] [✓] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
        DEBUG)
            echo -e "${CYAN}[${timestamp}] [DEBUG] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
    esac
}

print_banner() {
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Dependabot Auto-Merge Workflow - Batch Deployment Script     ║"
    echo "║   Version: $SCRIPT_VERSION                                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --deploy)
                DEPLOY_MODE=true
                DRY_RUN_MODE=false
                shift
                ;;
            --dry-run)
                DEPLOY_MODE=false
                DRY_RUN_MODE=true
                shift
                ;;
            --repo)
                SINGLE_REPO="$2"
                shift 2
                ;;
            --help)
                print_help
                exit 0
                ;;
            *)
                log ERROR "Unknown argument: $1"
                print_help
                exit 1
                ;;
        esac
    done
}

print_help() {
    cat <<EOF
Usage: bash deploy-dependabot-to-all.sh [OPTIONS]

Options:
    --dry-run          Run in dry-run mode (shows what will happen)
    --deploy           Deploy to all repositories
    --repo NAME        Deploy to single repository
    --help             Show this help message

Examples:
    # Test deployment (no changes made)
    bash deploy-dependabot-to-all.sh --dry-run

    # Deploy to all repositories
    bash deploy-dependabot-to-all.sh --deploy

    # Deploy to single repository
    bash deploy-dependabot-to-all.sh --deploy --repo my-repo

EOF
}

setup_logging() {
    mkdir -p "$LOG_DIR"
    
    {
        echo "Deployment Log"
        echo "=============="
        echo "Start Time: $(date)"
        echo "Script Version: $SCRIPT_VERSION"
        echo "Mode: $([ "$DEPLOY_MODE" = true ] && echo "DEPLOY" || echo "DRY-RUN")"
        echo "User: $(gh api user -q '.login' 2>/dev/null || echo "unknown")"
        echo ""
    } >> "$LOG_FILE"
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    if ! command -v gh &> /dev/null; then
        log ERROR "GitHub CLI (gh) not found"
        echo -e "${RED}Install from: https://cli.github.com/${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log ERROR "jq not found"
        echo -e "${RED}Install from: https://stedolan.github.io/jq/install/${NC}"
        exit 1
    fi
    
    log SUCCESS "All prerequisites met"
    echo -e "${GREEN}✓ gh version: $(gh --version | head -1)${NC}"
    echo -e "${GREEN}✓ jq version: $(jq --version)${NC}"
}

verify_github_auth() {
    log INFO "Verifying GitHub authentication..."
    
    if ! USER=$(gh api user -q '.login' 2>/dev/null); then
        log ERROR "Not authenticated with GitHub CLI"
        echo -e "${RED}Run: gh auth login${NC}"
        exit 1
    fi
    
    log SUCCESS "Authenticated as: $USER"
}

download_workflow() {
    log INFO "Downloading workflow file from $WORKFLOW_SOURCE_REPO/$WORKFLOW_FILE"
    
    if ! WORKFLOW_CONTENT=$(gh api repos/$WORKFLOW_SOURCE_REPO/contents/$WORKFLOW_FILE --jq '.content' 2>/dev/null | base64 -d); then
        log ERROR "Failed to download workflow file"
        echo -e "${RED}File not found: $WORKFLOW_SOURCE_REPO/$WORKFLOW_FILE${NC}"
        exit 1
    fi
    
    WORKFLOW_SIZE=$(echo -n "$WORKFLOW_CONTENT" | wc -c)
    log SUCCESS "Workflow file downloaded: $WORKFLOW_SIZE bytes"
}

get_all_repositories() {
    log INFO "Fetching all repositories for user: $USER"
    
    local all_repos=""
    local page=1
    
    while true; do
        log DEBUG "Fetching page $page of repositories..."
        
        page_repos=$(gh repo list "$USER" --limit 100 --json name --jq '.[].name' --no-header 2>/dev/null)
        
        if [ -z "$page_repos" ]; then
            break
        fi
        
        all_repos="$all_repos$page_repos"$'\n'
        page=$((page + 1))
        
        # GitHub API rate limiting - add small delay
        sleep 0.5
    done
    
    # Remove empty lines and duplicates
    echo "$all_repos" | grep -v '^$' | sort -u
}

deploy_to_repository() {
    local repo_name=$1
    local repo_full_name="$USER/$repo_name"
    
    # Skip source repository
    if [ "$repo_full_name" == "$WORKFLOW_SOURCE_REPO" ]; then
        log WARN "Skipping source repository: $repo_name"
        return 2
    fi
    
    if [ "$DEPLOY_MODE" = true ]; then
        log DEBUG "Setting email secrets for $repo_full_name"
        
        # Set email secrets
        for secret in EMAIL_SERVER EMAIL_PORT EMAIL_USERNAME EMAIL_PASSWORD EMAIL_FROM; do
            secret_value=""
            case $secret in
                EMAIL_SERVER) secret_value="$EMAIL_SERVER" ;;
                EMAIL_PORT) secret_value="$EMAIL_PORT" ;;
                EMAIL_USERNAME) secret_value="$EMAIL_USERNAME" ;;
                EMAIL_PASSWORD) secret_value="$EMAIL_PASSWORD" ;;
                EMAIL_FROM) secret_value="$EMAIL_FROM" ;;
            esac
            
            if ! gh secret set "$secret" --body "$secret_value" -R "$repo_full_name" 2>&1 | grep -q ""; then
                log DEBUG "Set secret $secret in $repo_full_name"
            fi
        done
        
        # Deploy workflow file
        log DEBUG "Deploying workflow file to $repo_full_name"
        
        ENCODED_CONTENT=$(echo -n "$WORKFLOW_CONTENT" | base64)
        
        if gh api repos/$USER/$repo_name/contents/.github/workflows/dependabot-auto-merge.yml \
            -X PUT \
            -f message="$WORKFLOW_COMMIT_MSG" \
            -f content="$ENCODED_CONTENT" \
            2>&1 | grep -q '"commit"'; then
            
            log SUCCESS "Deployed to: $repo_full_name"
            return 0
        else
            log ERROR "Failed to deploy to: $repo_full_name"
            return 1
        fi
    else
        log INFO "[DRY-RUN] Would deploy to: $repo_full_name"
        return 0
    fi
}

main() {
    print_banner
    
    setup_logging
    check_prerequisites
    verify_github_auth
    
    echo ""
    echo -e "${BLUE}📋 Configuration:${NC}"
    echo "   Source Repo: $WORKFLOW_SOURCE_REPO"
    echo "   Workflow File: $WORKFLOW_FILE"
    echo "   Email: $EMAIL_USERNAME"
    echo "   Mode: $([ "$DEPLOY_MODE" = true ] && echo "DEPLOY" || echo "DRY-RUN")"
    echo ""
    
    download_workflow
    
    echo ""
    
    if [ -n "$SINGLE_REPO" ]; then
        log INFO "Deploying to single repository: $SINGLE_REPO"
        mapfile -t REPO_ARRAY <<< "$SINGLE_REPO"
    else
        echo -e "${BLUE}📦 Fetching repositories...${NC}"
        repos=$(get_all_repositories)
        mapfile -t REPO_ARRAY <<< "$repos"
    fi
    
    TOTAL_REPOS=${#REPO_ARRAY[@]}
    
    log INFO "Found $TOTAL_REPOS repositories"
    echo -e "${GREEN}✓ Found $TOTAL_REPOS repositories${NC}"
    echo ""
    
    # Initialize counters
    DEPLOYED=0
    FAILED=0
    SKIPPED=0
    declare -a FAILED_REPOS
    
    # Deploy to each repository
    echo -e "${BLUE}🚀 Deployment Progress:${NC}"
    
    for i in "${!REPO_ARRAY[@]}"; do
        REPO_NAME="${REPO_ARRAY[$i]}"
        CURRENT=$((i + 1))
        PERCENTAGE=$((CURRENT * 100 / TOTAL_REPOS))
        
        printf "\r${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | Processing..."
        
        if deploy_to_repository "$REPO_NAME"; then
            DEPLOYED=$((DEPLOYED + 1))
            printf "\r${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | ${GREEN}✓${NC} $REPO_NAME                    "
        elif [ $? -eq 2 ]; then
            SKIPPED=$((SKIPPED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_REPOS+=("$REPO_NAME")
            printf "\r${BLUE}[$CURRENT/$TOTAL_REPOS]${NC} ${PERCENTAGE}%% | ${RED}✗${NC} $REPO_NAME                    "
        fi
    done
    
    echo ""
    echo ""
    
    # Print summary
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                    Deployment Summary                          ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$DRY_RUN_MODE" = true ]; then
        echo -e "${YELLOW}Mode: DRY-RUN (no changes made)${NC}"
    else
        echo -e "${GREEN}Mode: PRODUCTION (changes applied)${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Successfully deployed to:${NC} $DEPLOYED"
    echo -e "${RED}✗ Failed deployments:${NC} $FAILED"
    echo -e "${YELLOW}⊘ Skipped:${NC} $SKIPPED"
    echo -e "${BLUE}📊 Total:${NC} $TOTAL_REPOS"
    echo ""
    
    if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
        echo -e "${RED}Failed repositories:${NC}"
        for repo in "${FAILED_REPOS[@]}"; do
            echo -e "   ${RED}• $repo${NC}"
        done
        echo ""
    fi
    
    echo -e "${BLUE}📧 Email Configuration:${NC}"
    echo "   SMTP Server: $EMAIL_SERVER:$EMAIL_PORT"
    echo "   From: $EMAIL_FROM"
    echo "   To: $EMAIL_USERNAME"
    echo ""
    
    echo -e "${BLUE}📋 Logs:${NC}"
    echo "   Full log: $LOG_FILE"
    echo ""
    
    if [ "$DRY_RUN_MODE" = true ]; then
        echo -e "${YELLOW}Next: Run with --deploy flag to execute:${NC}"
        echo -e "${GREEN}   bash deploy-dependabot-to-all.sh --deploy${NC}"
    else
        echo -e "${GREEN}✨ Deployment complete!${NC}"
    fi
    
    echo ""
}

# ============================================================================
# Entry Point
# ============================================================================

parse_arguments "$@"
main
