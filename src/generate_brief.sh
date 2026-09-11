#!/bin/bash

# Load environment variables (e.g. API keys) that cron's minimal environment
# doesn't source from ~/.bashrc on its own
if [ -f "${HOME}/.bash_aliases" ]; then
    source "${HOME}/.bash_aliases"
fi

# Check for required dependencies
echo "Checking required dependencies..."

MISSING_DEPS=()

# Check for jq
if ! command -v jq &> /dev/null; then
    MISSING_DEPS+=("jq")
fi

# Check for gcalcli
if ! command -v gcalcli &> /dev/null; then
    MISSING_DEPS+=("gcalcli")
fi

# Check for jrnl
if ! command -v jrnl &> /dev/null; then
    MISSING_DEPS+=("jrnl")
fi

# Check for git
if ! command -v git &> /dev/null; then
    MISSING_DEPS+=("git")
fi

# Check for aider (used by summarize_outputs.py's 7-day summary step)
if ! command -v aider &> /dev/null; then
    MISSING_DEPS+=("aider")
fi

# Check for claude (used to generate the brief itself)
if ! command -v claude &> /dev/null; then
    MISSING_DEPS+=("claude")
fi

# Check for python3
if ! command -v python3 &> /dev/null; then
    MISSING_DEPS+=("python3")
fi

# If any dependencies are missing, print detailed error messages and exit
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "Error: Missing required dependencies!"
    echo ""
    
    for dep in "${MISSING_DEPS[@]}"; do
        case $dep in
            jq)
                echo "  ❌ jq - JSON parser for reading configuration"
                echo "     Install: brew install jq (macOS) or sudo apt-get install jq (Ubuntu/Debian)"
                ;;
            gcalcli)
                echo "  ❌ gcalcli - Google Calendar CLI for fetching calendar events"
                echo "     Install: pip install gcalcli"
                echo "     Setup: Run 'gcalcli oauth' to authenticate with Google Calendar"
                ;;
            jrnl)
                echo "  ❌ jrnl - Journal CLI for accessing journal entries"
                echo "     Install: pip install jrnl"
                echo "     Setup: Run 'jrnl --setup' to initialize your journal"
                ;;
            git)
                echo "  ❌ git - Version control system"
                echo "     Install: brew install git (macOS) or sudo apt-get install git (Ubuntu/Debian)"
                ;;
            aider)
                echo "  ❌ aider - AI assistant used by summarize_outputs.py for the rolling 7-day summary"
                echo "     Install: pip install aider-chat"
                ;;
            claude)
                echo "  ❌ claude - Claude Code CLI, used to generate the daily brief itself"
                echo "     Install: see https://docs.claude.com/en/docs/claude-code"
                echo "     Setup: Run 'claude auth login' (or set ANTHROPIC_API_KEY) to authenticate"
                ;;
            python3)
                echo "  ❌ python3 - Python interpreter (required for summarize_outputs.py)"
                echo "     Install: brew install python3 (macOS) or sudo apt-get install python3 (Ubuntu/Debian)"
                ;;
        esac
        echo ""
    done
    
    echo "Please install the missing dependencies and try again."
    echo "See README.md for detailed installation instructions."
    exit 1
fi

echo "✓ All required dependencies found"
echo ""

# Parse command line arguments
USER_MESSAGE=""
TARGET_DATE=""
while getopts "m:d:" opt; do
    case $opt in
        m)
            USER_MESSAGE="$OPTARG"
            ;;
        d)
            TARGET_DATE="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Usage: $0 [-m \"additional message for claude\"] [-d YYYY-MM-DD]"
            exit 1
            ;;
    esac
done

# Set target date to today if not specified
if [ -z "${TARGET_DATE}" ]; then
    TARGET_DATE=$(date +"%Y-%m-%d")
else
    # Validate date format
    if ! date -d "${TARGET_DATE}" +"%Y-%m-%d" &>/dev/null; then
        echo "Error: Invalid date format '${TARGET_DATE}'. Use YYYY-MM-DD format."
        exit 1
    fi
    # Normalize the date format
    TARGET_DATE=$(date -d "${TARGET_DATE}" +"%Y-%m-%d")
fi

# Print current date and time
echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Get script directory to find config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"

# Check if config file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: Config file not found at ${CONFIG_FILE}"
    exit 1
fi

# Read configuration from JSON file
CALENDARS=($(jq -r '.calendars[]' "${CONFIG_FILE}"))
CALENDAR_LOG_PATH=$(jq -r '.paths.calendar_log' "${CONFIG_FILE}")
LOG_PATH=$(jq -r '.paths.log' "${CONFIG_FILE}")
BRIEF_REPO_PATH=$(jq -r '.paths.brief_repo' "${CONFIG_FILE}")
BRIEF_INPUTS_PATH="${BRIEF_REPO_PATH}/inputs"
BRIEF_OUTPUTS_PATH="${BRIEF_REPO_PATH}/outputs"
CLAUDE_MODEL=$(jq -r '.claude.brief_model // "sonnet"' "${CONFIG_FILE}")

# Build calendar command arguments
CALENDAR_ARGS=""
for calendar in "${CALENDARS[@]}"; do
    CALENDAR_ARGS="${CALENDAR_ARGS} --calendar \"${calendar}\""
done

# calendar command: calme agenda
alias calme="gcalcli ${CALENDAR_ARGS}"

# Create log directories if they don't exist
mkdir -p "${CALENDAR_LOG_PATH}"
mkdir -p "${BRIEF_INPUTS_PATH}"
mkdir -p "${BRIEF_OUTPUTS_PATH}"

# Update brief repository to ensure latest version is present
if [ -d "${BRIEF_REPO_PATH}/.git" ]; then
    echo "Updating brief repository at ${BRIEF_REPO_PATH}..."
    cd "${BRIEF_REPO_PATH}" || { echo "Error: Could not change to brief repo directory ${BRIEF_REPO_PATH}"; exit 1; }
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || echo "No remote to pull from or pull failed, continuing..."
fi

# Initialize git repository in brief repo if it doesn't exist
if [ ! -d "${BRIEF_REPO_PATH}/.git" ]; then
    echo "Initializing git repository in ${BRIEF_REPO_PATH}..."
    cd "${BRIEF_REPO_PATH}" || { echo "Error: Could not change to brief repo directory ${BRIEF_REPO_PATH}"; exit 1; }
    git init
    echo "# Daily Brief Repository" > README.md
    echo "" >> README.md
    echo "This repository contains daily brief inputs and outputs organized by date." >> README.md
    echo "" >> README.md
    echo "## Structure" >> README.md
    echo "- \`inputs/\` - Raw journal and calendar data used to generate briefs" >> README.md
    echo "- \`outputs/\` - Generated daily briefs in markdown format" >> README.md
    git add README.md
    git commit -m "Initial commit: Add README"
fi

## Collect calendar data and save to daily log file
# Get current date for logging and filename
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")
TODAY="${TARGET_DATE}"
TODAY_DAY_NAME=$(date -d "${TARGET_DATE}" +"%A")
TOMORROW=$(date -d "${TARGET_DATE} + 1 day" +"%Y-%m-%d")
YESTERDAY=$(date -d "${TARGET_DATE} - 1 day" +"%Y-%m-%d")
NEXT_WEEK=$(date -d "${TARGET_DATE} + 7 days" +"%Y-%m-%d")
DATE_TWO_WEEKS_AGO=$(date -d "${TARGET_DATE} - 14 days" +"%Y-%m-%d")
YEAR=$(date -d "${TARGET_DATE}" +"%Y")
MONTH=$(date -d "${TARGET_DATE}" +"%m")
DAY=$(date -d "${TARGET_DATE}" +"%d")

# Create hierarchical directory structure for brief outputs
BRIEF_OUTPUT_DIR="${BRIEF_OUTPUTS_PATH}/${YEAR}/${MONTH}"
mkdir -p "${BRIEF_OUTPUT_DIR}"

CALENDAR_LOG_FILE="${CALENDAR_LOG_PATH}/calendar_${TODAY}.log"
GITHUB_LOG_FILE="${CALENDAR_LOG_PATH}/github_${TODAY}.log"
BRIEF_INPUT_FILE="${BRIEF_INPUTS_PATH}/brief_input_${TODAY}.txt"
BRIEF_OUTPUT_FILE="${BRIEF_OUTPUT_DIR}/${DAY}.md"

# Run the calendar command and save output to daily log file
echo "=== Calendar data collected on ${CURRENT_DATE} ===" > "${CALENDAR_LOG_FILE}"
eval "gcalcli ${CALENDAR_ARGS} agenda $DATE_TWO_WEEKS_AGO $NEXT_WEEK --details description" >> "${CALENDAR_LOG_FILE}" 2>&1
echo "" >> "${CALENDAR_LOG_FILE}"  # Add empty line for readability

echo "Calendar data collected and saved to ${CALENDAR_LOG_FILE}"

## Collect GitHub activity (PRs and issues authored by the configured user)
# and save to daily log file. `gh` is optional -- skip gracefully (logging why,
# never leaking raw CLI error/usage text into the brief input) if it's not
# installed/authenticated or no github.username is configured.
#
# Under cron's minimal PATH, `gh` can resolve to an older system install that
# doesn't support `gh search` at all (confirmed: /usr/bin/gh on this machine
# predates it) -- prefer the anaconda gh, which does, and only fall back to
# PATH resolution if that's missing.
GITHUB_USERNAME=$(jq -r '.github.username // empty' "${CONFIG_FILE}")

GH_BIN=""
for candidate in "${HOME}/anaconda3/bin/gh" "$(command -v gh 2>/dev/null)"; do
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
        GH_BIN="${candidate}"
        break
    fi
done

echo "=== GitHub activity collected on ${CURRENT_DATE} ===" > "${GITHUB_LOG_FILE}"
if [ -z "${GITHUB_USERNAME}" ]; then
    echo "No github.username configured in config.json, skipping GitHub activity" >> "${GITHUB_LOG_FILE}"
elif [ -z "${GH_BIN}" ]; then
    echo "gh CLI not found, skipping GitHub activity" >> "${GITHUB_LOG_FILE}"
elif ! "${GH_BIN}" auth status &> /dev/null; then
    echo "gh CLI found (${GH_BIN}) but not authenticated -- run 'gh auth login', skipping GitHub activity" >> "${GITHUB_LOG_FILE}"
else
    PRS_OUTPUT=$("${GH_BIN}" search prs --author="${GITHUB_USERNAME}" --updated=">=${DATE_TWO_WEEKS_AGO}" --limit 50 \
        --json repository,title,state,url,updatedAt \
        --jq '.[] | "- [\(.state)] \(.repository.nameWithOwner): \(.title) (\(.url)) - updated \(.updatedAt | split("T")[0])"' 2>&1)
    PRS_EXIT=$?
    ISSUES_OUTPUT=$("${GH_BIN}" search issues --author="${GITHUB_USERNAME}" --updated=">=${DATE_TWO_WEEKS_AGO}" --limit 50 \
        --json repository,title,state,url,updatedAt \
        --jq '.[] | "- [\(.state)] \(.repository.nameWithOwner): \(.title) (\(.url)) - updated \(.updatedAt | split("T")[0])"' 2>&1)
    ISSUES_EXIT=$?

    if [ ${PRS_EXIT} -ne 0 ] && [ ${ISSUES_EXIT} -ne 0 ]; then
        echo "gh queries failed (${GH_BIN}), skipping GitHub activity" >> "${GITHUB_LOG_FILE}"
    else
        echo "Pull requests (updated since ${DATE_TWO_WEEKS_AGO}):" >> "${GITHUB_LOG_FILE}"
        if [ ${PRS_EXIT} -eq 0 ]; then
            echo "${PRS_OUTPUT}" >> "${GITHUB_LOG_FILE}"
        else
            echo "(pr query failed, skipped)" >> "${GITHUB_LOG_FILE}"
        fi
        echo "" >> "${GITHUB_LOG_FILE}"
        echo "Issues (updated since ${DATE_TWO_WEEKS_AGO}):" >> "${GITHUB_LOG_FILE}"
        if [ ${ISSUES_EXIT} -eq 0 ]; then
            echo "${ISSUES_OUTPUT}" >> "${GITHUB_LOG_FILE}"
        else
            echo "(issue query failed, skipped)" >> "${GITHUB_LOG_FILE}"
        fi
    fi
fi
echo "" >> "${GITHUB_LOG_FILE}"  # Add empty line for readability

echo "GitHub activity collected and saved to ${GITHUB_LOG_FILE}"

## Collect regular log data 
# Update regular log from git repository
echo "Updating regular log from git repository at ${LOG_PATH}..."
cd "${LOG_PATH}" || { echo "Error: Could not change to log directory ${LOG_PATH}"; exit 1; }
git pull origin master

# Append calendar and jrnl data to brief input file
echo "Collecting journal entries from the last two weeks..."
jrnl -from $DATE_TWO_WEEKS_AGO --format md > "${BRIEF_INPUT_FILE}" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: jrnl command failed. Check jrnl configuration."
    echo "Run 'jrnl --setup' to configure jrnl if this is your first time using it."
    echo "Journal entries not available (jrnl command failed)" > "${BRIEF_INPUT_FILE}"
else
    echo "Successfully collected journal entries"
fi

echo "" >> "${BRIEF_INPUT_FILE}"  # Add empty line for readability
echo "Calendar data:" >> "${BRIEF_INPUT_FILE}"

if [ ! -f "${CALENDAR_LOG_FILE}" ]; then
    echo "Warning: Calendar log file not found at ${CALENDAR_LOG_FILE}"
    echo "Calendar data not available" >> "${BRIEF_INPUT_FILE}"
else
    cat "${CALENDAR_LOG_FILE}" >> "${BRIEF_INPUT_FILE}"
    echo "Successfully added calendar data"
fi

echo "" >> "${BRIEF_INPUT_FILE}"  # Add empty line for readability
echo "GitHub activity:" >> "${BRIEF_INPUT_FILE}"

if [ ! -f "${GITHUB_LOG_FILE}" ]; then
    echo "Warning: GitHub activity log file not found at ${GITHUB_LOG_FILE}"
    echo "GitHub activity not available" >> "${BRIEF_INPUT_FILE}"
else
    cat "${GITHUB_LOG_FILE}" >> "${BRIEF_INPUT_FILE}"
    echo "Successfully added GitHub activity data"
fi

echo "Brief input file created at ${BRIEF_INPUT_FILE}"
echo "Combined journal, calendar, and GitHub activity data ready for processing"

# Generate a summary of the past 7 days' briefs using summarize_outputs.py
# Store in a persistent file that is only created once per day
SEVEN_DAYS_AGO=$(date -d "${TARGET_DATE} - 7 days" +"%Y-%m-%d")
SUMMARY_DIR="${BRIEF_REPO_PATH}/summaries"
mkdir -p "${SUMMARY_DIR}"
SUMMARY_FILE="${SUMMARY_DIR}/summary_${TODAY}.md"

# Check if summary already exists for today
if [ -f "${SUMMARY_FILE}" ]; then
    echo "Found existing 7-day summary for today at ${SUMMARY_FILE}"
    echo "Reusing existing summary (delete file to regenerate)"
else
    echo "Generating summary of briefs from ${SEVEN_DAYS_AGO} to ${YESTERDAY}..."
    python3 "${SCRIPT_DIR}/summarize_outputs.py" --start "${SEVEN_DAYS_AGO}" --end "${YESTERDAY}" --output "${SUMMARY_FILE}"
    
    if [ $? -eq 0 ] && [ -f "${SUMMARY_FILE}" ]; then
        echo "Successfully generated 7-day summary"
    else
        echo "Warning: Could not generate 7-day summary. This may be normal if there are no briefs for the past week."
        echo "Continuing without summary..."
    fi
fi

# If summary file exists, append it to the brief input
if [ -f "${SUMMARY_FILE}" ]; then
    echo "" >> "${BRIEF_INPUT_FILE}"
    echo "Summary of briefs from the past 7 days (${SEVEN_DAYS_AGO} to ${YESTERDAY}):" >> "${BRIEF_INPUT_FILE}"
    cat "${SUMMARY_FILE}" >> "${BRIEF_INPUT_FILE}"
    echo "Added 7-day summary to input for AI review"
fi

# Create empty brief output file
touch "${BRIEF_OUTPUT_FILE}"

# Get path to STYLE.md
STYLE_FILE="${SCRIPT_DIR}/../STYLE.md"

# Get path to DEADLINES.md (create if it doesn't exist)
DEADLINES_FILE="${BRIEF_REPO_PATH}/DEADLINES.md"
if [ ! -f "${DEADLINES_FILE}" ]; then
    echo "# Deadlines Tracker" > "${DEADLINES_FILE}"
    echo "" >> "${DEADLINES_FILE}"
    echo "| Category | Date | Deadline | Status | Notes |" >> "${DEADLINES_FILE}"
    echo "|----------|------|----------|--------|-------|" >> "${DEADLINES_FILE}"
    echo "Created initial deadlines table at ${DEADLINES_FILE}"
fi

# Generate daily brief using claude (non-interactive/print mode)
echo "Generating daily brief with claude..."

# Build the claude prompt. Unlike aider (which takes explicit --read/editable
# file args), claude reads/writes files itself via its Read/Write tools, so
# the prompt just points it at the relevant absolute paths.
CLAUDE_MESSAGE="Based on the journal entries, calendar data, GitHub activity, and yesterday's incomplete items in the file at ${BRIEF_INPUT_FILE}, generate a concise daily brief and gameplan for today (${TODAY_DAY_NAME}, ${TODAY}).

The calendar output covers the past 2 weeks through the next 7 days (until ${NEXT_WEEK}).

The GitHub activity data (if present) covers pull requests and issues authored in the past 2 weeks; summarize it briefly rather than listing every item.

Follow the style guide at ${STYLE_FILE} for formatting and content guidelines.

Write the resulting well-formatted GitHub markdown daily brief directly to the file at ${BRIEF_OUTPUT_FILE}, overwriting its current (empty) contents. Do not print the brief in your response -- only write it to that file."

# Append user message if provided
if [ -n "${USER_MESSAGE}" ]; then
    echo "Adding user-provided context to claude prompt..."
    CLAUDE_MESSAGE="${CLAUDE_MESSAGE}

Additional context from user:
${USER_MESSAGE}"
fi

# Run non-interactively (-p/--print), restricted to just Read/Write with all
# permission prompts bypassed -- there's no human to answer prompts under
# cron, and restricting to Read/Write (no Bash) bounds what an unattended
# batch run can do regardless.
echo "Using model: ${CLAUDE_MODEL}..."
CLAUDE_LOG_FILE=$(mktemp)
claude -p \
    --model "${CLAUDE_MODEL}" \
    --permission-mode bypassPermissions \
    --allowedTools "Read Write" \
    --no-session-persistence \
    "${CLAUDE_MESSAGE}" 2>&1 | tee "${CLAUDE_LOG_FILE}"
CLAUDE_EXIT_CODE=${PIPESTATUS[0]}

# claude can exit 0 even when the underlying API call failed, so also scan its
# output for known failure signatures
if [ ${CLAUDE_EXIT_CODE} -eq 0 ] && grep -qiE "authentication_error|invalid_api_key|permission_error|overloaded_error|rate_limit_error|ANTHROPIC_API_KEY" "${CLAUDE_LOG_FILE}"; then
    echo "Error: claude reported an API error despite exiting successfully."
    echo "Check that ANTHROPIC_API_KEY (or your configured auth) is valid."
    CLAUDE_EXIT_CODE=1
fi
rm -f "${CLAUDE_LOG_FILE}"

# claude should have written directly to BRIEF_OUTPUT_FILE via its Write tool;
# treat a still-empty output as a failure too
if [ ${CLAUDE_EXIT_CODE} -eq 0 ] && [ ! -s "${BRIEF_OUTPUT_FILE}" ]; then
    echo "Error: claude exited successfully but ${BRIEF_OUTPUT_FILE} is empty."
    CLAUDE_EXIT_CODE=1
fi

if [ ${CLAUDE_EXIT_CODE} -eq 0 ]; then
    echo "Daily brief generated successfully at ${BRIEF_OUTPUT_FILE}"
    
    # Read deadlines table and substitute {{DEADLINES}} variable in the brief
    if [ -f "${DEADLINES_FILE}" ]; then
        # Use awk to replace {{DEADLINES}} with the contents of DEADLINES_FILE
        # This handles multi-line content and special characters properly
        TEMP_FILE="${BRIEF_OUTPUT_FILE}.tmp"
        awk -v deadlines_file="${DEADLINES_FILE}" '
            /{{DEADLINES}}/ {
                while ((getline line < deadlines_file) > 0) {
                    print line
                }
                close(deadlines_file)
                next
            }
            { print }
        ' "${BRIEF_OUTPUT_FILE}" > "${TEMP_FILE}"
        mv "${TEMP_FILE}" "${BRIEF_OUTPUT_FILE}"
        echo "Deadlines table inserted into brief"
    fi
    
    # Commit and push the generated brief to GitHub
    echo "Committing and pushing brief to GitHub..."
    cd "${BRIEF_REPO_PATH}" || { echo "Error: Could not change to brief repo directory ${BRIEF_REPO_PATH}"; exit 1; }
    
    # Add the new files to git (including DEADLINES.md)
    git add inputs/ outputs/ summaries/ DEADLINES.md
    
    # Commit with a descriptive message
    git commit -m "Add daily brief for ${TODAY}"
    
    # Push to GitHub (assumes remote origin is set up)
    if git push origin main 2>/dev/null || git push origin master 2>/dev/null; then
        echo "Successfully pushed daily brief to GitHub"
    else
        echo "Warning: Could not push to GitHub. Make sure remote origin is configured."
        echo "You can manually push later with: cd ${BRIEF_REPO_PATH} && git push origin main"
    fi
else
    echo "Error generating daily brief. Check claude output for details."
    exit 1
fi
