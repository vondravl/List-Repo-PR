#!/bin/bash

# ==============================================================================
# List Changes Script
# ==============================================================================
# This script lists merged PRs from a GitHub repository with two modes:
#   1. List all PRs merged after a specific datetime
#   2. List the last N merged PRs
#
# Usage:
#   ./list_repo_pr.sh --since "2024-10-15T10:30Z"
#   ./list_repo_pr.sh --last 10
#   ./list_repo_pr.sh --help
#
# Requirements:
#   - gh (GitHub CLI) must be installed and authenticated
#   - jq must be installed
#
# Security:
#   - This script performs READ-ONLY operations
#   - No write, push, delete, or modify operations are performed
#   - Safe to run on any repository
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

# Default repository (can be overridden with --repo flag)
DEFAULT_REPO="${GITHUB_REPOSITORY:-}"
REPO_PATH=""

# Mode selection
MODE=""
SINCE_DATE=""
LAST_N=0

# Pagination limit (prevent excessive API calls)
MAX_PAGES=20

# Temporary files for accumulating results safely (avoid long argument lists)
ALL_PRS_FILE=$(mktemp -t all_prs)
PRS_PAGE_FILE=$(mktemp -t prs_page)

# Ensure temp files are removed on exit
cleanup() {
    rm -f "$ALL_PRS_FILE" "$PRS_PAGE_FILE" "${ALL_PRS_FILE}.tmp" 2>/dev/null || true
}
trap cleanup EXIT

# ==============================================================================
# Helper Functions
# ==============================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

List merged PRs from a GitHub repository.

Modes (pick one):
  --since <datetime>     List all PRs merged after the specified datetime
                         Format: ISO 8601 (e.g., "2024-10-15T10:30Z" or "2024-10-15T10:30:00Z")
  
  --last <N>             List the last N merged PRs

Options:
  --repo <owner/name>    GitHub repository (default: auto-detect from git or GITHUB_REPOSITORY env var)
  --help                 Show this help message

Environment Variables:
  GITHUB_REPOSITORY      Default repository in owner/repo format (optional)

Note:
  This script requires GitHub CLI (gh) to be installed and authenticated.
  Run 'gh auth login' if you haven't authenticated yet.

Examples:
  $0 --since "2024-10-15T10:30Z"
  $0 --last 10
  $0 --repo "owner/repo" --last 5

EOF
    exit 0
}

error_exit() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

check_dependencies() {
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq to use this script."
    fi
    
    if ! command -v gh &> /dev/null; then
        error_exit "gh (GitHub CLI) is not installed. Please install it from https://cli.github.com/"
    fi
    
    # Check if gh is authenticated
    if ! gh auth status &> /dev/null; then
        error_exit "gh is not authenticated. Please run 'gh auth login' first."
    fi
}

extract_repo_path() {
    # Extract owner/repo from various URL formats
    echo "$1" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#'
}

detect_repo() {
    # Try to auto-detect repository from git remote
    if [ -z "$REPO_PATH" ]; then
        if [ -n "$DEFAULT_REPO" ]; then
            REPO_PATH="$DEFAULT_REPO"
        elif git remote get-url origin &> /dev/null; then
            REPO_PATH=$(extract_repo_path "$(git remote get-url origin)")
        else
            error_exit "Could not auto-detect repository. Please specify with --repo flag."
        fi
    elif [[ "$REPO_PATH" =~ ^https?:// ]]; then
        # If REPO_PATH is a full URL, extract owner/repo
        REPO_PATH=$(extract_repo_path "$REPO_PATH")
    fi
    
    echo "📦 Repository: $REPO_PATH"
}

validate_date_format() {
    local date_str="$1"
    # Check if date matches ISO 8601 format (basic validation)
    if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z?$ ]]; then
        error_exit "Invalid date format: '$date_str'. Expected ISO 8601 format (e.g., '2024-10-15T10:30Z' or '2024-10-15T10:30:00Z')"
    fi
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

if [ $# -eq 0 ]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --since)
            MODE="since"
            SINCE_DATE="$2"
            shift 2
            ;;
        --last)
            MODE="last"
            LAST_N="$2"
            shift 2
            ;;
        --repo)
            REPO_PATH="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Validate mode selection
if [ -z "$MODE" ]; then
    error_exit "No mode specified. Use --since or --last. See --help for details."
fi

if [ "$MODE" = "last" ] && [ "$LAST_N" -le 0 ]; then
    error_exit "Invalid value for --last. Must be a positive integer."
fi

# Validate and normalize date format
if [ "$MODE" = "since" ]; then
    validate_date_format "$SINCE_DATE"
    # If date ends with Z but doesn't have seconds (format: YYYY-MM-DDTHH:MMZ), add :00
    if [[ "$SINCE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$ ]]; then
        SINCE_DATE="${SINCE_DATE%Z}:00Z"
    fi
fi

# ==============================================================================
# Main Script
# ==============================================================================

check_dependencies
detect_repo

echo "=============================================="
echo "GitHub PR Listing Tool"
echo "=============================================="
echo "Mode: $MODE"
if [ "$MODE" = "since" ]; then
    echo "Since: $SINCE_DATE"
else
    echo "Count: $LAST_N"
fi
echo "=============================================="
echo ""

# ==============================================================================
# Fetch PRs with Pagination
# ==============================================================================

echo "🔍 Fetching merged PRs..."

ALL_PRS=""
PAGE=1
HAS_MORE=true
STOP_PAGINATION=false

while [ "$HAS_MORE" = true ] && [ "$STOP_PAGINATION" = false ] && [ $PAGE -le $MAX_PAGES ]; do
    echo "📄 Fetching page $PAGE..."
    
    # Use gh api to fetch PRs
    if ! PRS_PAGE=$(gh api "/repos/${REPO_PATH}/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=$PAGE" 2>&1); then
        echo "   ❌ Error fetching PRs on page $PAGE"
        if [[ "$PRS_PAGE" =~ "Not Found" ]] || [[ "$PRS_PAGE" =~ "404" ]]; then
            error_exit "Repository not found. Check that the repository path is correct and you have access."
        else
            error_exit "Failed to fetch PRs: $PRS_PAGE"
        fi
    fi
    
    PAGE_COUNT=$(echo "$PRS_PAGE" | jq '. | length' 2>/dev/null || echo "0")
    if [ "$PAGE_COUNT" = "null" ] || [ -z "$PAGE_COUNT" ]; then
        PAGE_COUNT=0
    fi
    
    if [ "$PAGE_COUNT" -eq 0 ]; then
        HAS_MORE=false
        echo "   📄 No more PRs found"
    else
        echo "   📄 Found $PAGE_COUNT PRs on page $PAGE"
        
        # Write page to temp file and merge into accumulator file (using files to avoid argv limits)
        echo "$PRS_PAGE" > "$PRS_PAGE_FILE"
        if ! jq -s 'add' "$ALL_PRS_FILE" "$PRS_PAGE_FILE" > "${ALL_PRS_FILE}.tmp" 2>/dev/null; then
            error_exit "Failed to process PRs (merge step). Try narrowing the range (use --last or a closer --since date)."
        fi
        mv "${ALL_PRS_FILE}.tmp" "$ALL_PRS_FILE"
        
        # Check if we should stop pagination
        if [ "$MODE" = "since" ]; then
            # Stop if we've gone past the baseline date
            OLDEST_ON_PAGE=$(echo "$PRS_PAGE" | jq -r '.[-1]?.updated_at // empty' 2>/dev/null)
            if [ -n "$OLDEST_ON_PAGE" ] && [ "$OLDEST_ON_PAGE" != "null" ] && [ "$OLDEST_ON_PAGE" \< "$SINCE_DATE" ]; then
                echo "   📄 Found PRs older than baseline, stopping pagination"
                STOP_PAGINATION=true
            fi
        else
            # Stop if we have enough merged PRs for --last mode
            MERGED_COUNT=$(jq '[.[]? | select(.merged_at != null)] | length' "$ALL_PRS_FILE" 2>/dev/null || echo "0")
            if [ "$MERGED_COUNT" -ge "$LAST_N" ]; then
                echo "   ✅ Collected enough merged PRs ($MERGED_COUNT >= $LAST_N), stopping pagination"
                STOP_PAGINATION=true
            fi
        fi
        
        PAGE=$((PAGE + 1))
    fi
done

if [ $PAGE -gt $MAX_PAGES ]; then
    echo "⚠️  Warning: Stopped at page $MAX_PAGES to prevent excessive API calls."
fi

# Count total PRs fetched for reporting
TOTAL_PRS_FETCHED=$(jq '. | length' "$ALL_PRS_FILE" 2>/dev/null || echo "0")
if [ "$TOTAL_PRS_FETCHED" = "null" ] || [ -z "$TOTAL_PRS_FETCHED" ]; then
    TOTAL_PRS_FETCHED=0
fi
echo "📊 Total PRs fetched: $TOTAL_PRS_FETCHED"

# ==============================================================================
# Filter and Display Results
# ==============================================================================

echo ""
echo "=============================================="
echo "Results:"
echo "=============================================="
echo ""

# Filter PRs based on mode
if [ "$MODE" = "since" ]; then
    # Filter by date
    FOUND_PRS=$(jq --arg since_date "$SINCE_DATE" '
        [.[]? | 
        select(.merged_at != null) | 
        select(.merged_at > $since_date)] | length
    ' "$ALL_PRS_FILE" 2>/dev/null || echo "0")
    
    PR_LIST=$(jq -r --arg since_date "$SINCE_DATE" --arg repo_path "$REPO_PATH" '
        [.[]? | 
        select(.merged_at != null) | 
        select(.merged_at > $since_date)] |
        sort_by(.merged_at) |
        .[]? |
        "#\(.number)|\(.title)" + 
        (if (.labels | length) > 0 then " [" + ([.labels[]?.name] | join(", ")) + "]" else "" end) + 
        "|https://github.com/\($repo_path)/pull/\(.number)"
    ' "$ALL_PRS_FILE" 2>/dev/null || echo "")
else
    # Take last N merged PRs
    FOUND_PRS=$(jq --arg last_n "$LAST_N" '
        [.[]? | select(.merged_at != null)] | 
        length as $total |
        if $total >= ($last_n | tonumber) then ($last_n | tonumber) else $total end
    ' "$ALL_PRS_FILE" 2>/dev/null || echo "0")
    
    PR_LIST=$(jq -r --arg last_n "$LAST_N" --arg repo_path "$REPO_PATH" '
        [.[]? | select(.merged_at != null)] |
        sort_by(.merged_at) |
        reverse |
        .[:($last_n | tonumber)]? |
        reverse |
        .[]? |
        "#\(.number)|\(.title)" + 
        (if (.labels | length) > 0 then " [" + ([.labels[]?.name] | join(", ")) + "]" else "" end) + 
        "|https://github.com/\($repo_path)/pull/\(.number)"
    ' "$ALL_PRS_FILE" 2>/dev/null || echo "")
fi

# Display the PR list
if [ -n "$PR_LIST" ]; then
    echo "📋 Excel-ready format (copy the lines below, paste into Excel):"
    echo "=============================================="
    echo "ID|Description|Hyperlink"
    echo "$PR_LIST"
    echo "=============================================="
fi

echo ""
if [ "$FOUND_PRS" -eq 0 ] 2>/dev/null; then
    if [ "$MODE" = "since" ]; then
        echo "✅ No PRs found merged since $SINCE_DATE"
    else
        echo "✅ No merged PRs found"
    fi
else
    echo "📊 Total PRs found: $FOUND_PRS"
fi

echo ""
echo "=============================================="
echo "✅ Analysis completed!"
echo "=============================================="

exit 0

