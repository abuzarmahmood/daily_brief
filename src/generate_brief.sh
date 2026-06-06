#!/bin/bash

# Parse command line arguments
USER_MESSAGE=""
while getopts "m:" opt; do
    case $opt in
        m)
            USER_MESSAGE="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Usage: $0 [-m \"additional message for aider\"]"
            exit 1
            ;;
    esac
done

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
AIDER_MODEL=$(jq -r '.aider.brief_model' "${CONFIG_FILE}")

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
TODAY=$(date +"%Y-%m-%d")
TODAY_DAY_NAME=$(date +"%A")
TOMORROW=$(date -d "tomorrow" +"%Y-%m-%d")
YESTERDAY=$(date -d "yesterday" +"%Y-%m-%d")
NEXT_WEEK=$(date -d "+7 days" +"%Y-%m-%d")
DATE_TWO_WEEKS_AGO=$(date -d "14 days ago" +"%Y-%m-%d")
YEAR=$(date +"%Y")
MONTH=$(date +"%m")
DAY=$(date +"%d")

# Create hierarchical directory structure for brief outputs
BRIEF_OUTPUT_DIR="${BRIEF_OUTPUTS_PATH}/${YEAR}/${MONTH}"
mkdir -p "${BRIEF_OUTPUT_DIR}"

CALENDAR_LOG_FILE="${CALENDAR_LOG_PATH}/calendar_${TODAY}.log"
BRIEF_INPUT_FILE="${BRIEF_INPUTS_PATH}/brief_input_${TODAY}.txt"
BRIEF_OUTPUT_FILE="${BRIEF_OUTPUT_DIR}/${DAY}.md"

# Run the calendar command and save output to daily log file
echo "=== Calendar data collected on ${CURRENT_DATE} ===" > "${CALENDAR_LOG_FILE}"
eval "gcalcli ${CALENDAR_ARGS} agenda $DATE_TWO_WEEKS_AGO $NEXT_WEEK --details description" >> "${CALENDAR_LOG_FILE}" 2>&1
echo "" >> "${CALENDAR_LOG_FILE}"  # Add empty line for readability

echo "Calendar data collected and saved to ${CALENDAR_LOG_FILE}"

## Collect regular log data 
# Update regular log from git repository
echo "Updating regular log from git repository at ${LOG_PATH}..."
cd "${LOG_PATH}" || { echo "Error: Could not change to log directory ${LOG_PATH}"; exit 1; }
git pull origin master

# Append calendar and jrnl data to brief input file
echo "Collecting journal entries from the last two weeks..."
if ! command -v jrnl &> /dev/null; then
    echo "Warning: jrnl command not found. Skipping journal entries."
    echo "Journal entries not available (jrnl not installed)" > "${BRIEF_INPUT_FILE}"
else
    jrnl -from $DATE_TWO_WEEKS_AGO --format md > "${BRIEF_INPUT_FILE}" 2>&1
    if [ $? -ne 0 ]; then
        echo "Warning: jrnl command failed. Check jrnl configuration."
        echo "Journal entries not available (jrnl command failed)" > "${BRIEF_INPUT_FILE}"
    else
        echo "Successfully collected journal entries"
    fi
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

echo "Brief input file created at ${BRIEF_INPUT_FILE}"
echo "Combined journal and calendar data ready for processing"

# Generate a summary of the past 7 days' briefs using summarize_outputs.py
# Store in a persistent file that is only created once per day
SEVEN_DAYS_AGO=$(date -d "7 days ago" +"%Y-%m-%d")
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
    echo "| Date | Deadline | Status | Notes |" >> "${DEADLINES_FILE}"
    echo "|------|----------|--------|-------|" >> "${DEADLINES_FILE}"
    echo "Created initial deadlines table at ${DEADLINES_FILE}"
fi

# Generate daily brief using aider
echo "Generating daily brief with aider..."

# Build the aider message
AIDER_MESSAGE="Based on the provided journal entries, calendar data, yesterday's incomplete items, and the deadlines table, please generate a concise daily brief and gameplan for today (${TODAY_DAY_NAME}, ${TODAY}). 

The calendar output covers the past 2 weeks through the next 7 days (until ${NEXT_WEEK}).

The DEADLINES.md file contains a table of tracked deadlines with their status.

Please follow the style guide in STYLE.md for formatting and content guidelines.

Populate the brief output file with a well-formatted GitHub markdown daily brief."

# Append user message if provided
if [ -n "${USER_MESSAGE}" ]; then
    echo "Adding user-provided context to aider prompt..."
    AIDER_MESSAGE="${AIDER_MESSAGE}

Additional context from user:
${USER_MESSAGE}"
fi

# Use configured model or aider's default
if [ "${AIDER_MODEL}" = "default" ]; then
    echo "Using aider's default model..."
    aider --message "${AIDER_MESSAGE}" --yes --read "${STYLE_FILE}" "${DEADLINES_FILE}" "${BRIEF_INPUT_FILE}" "${BRIEF_OUTPUT_FILE}"
else
    echo "Using configured model: ${AIDER_MODEL}..."
    aider --model "${AIDER_MODEL}" --message "${AIDER_MESSAGE}" --yes --read "${STYLE_FILE}" "${DEADLINES_FILE}" "${BRIEF_INPUT_FILE}" "${BRIEF_OUTPUT_FILE}"
fi

if [ $? -eq 0 ]; then
    echo "Daily brief generated successfully at ${BRIEF_OUTPUT_FILE}"
    
    # Update deadlines table based on the generated brief
    echo "Updating deadlines table with any deadlines mentioned in the brief..."
    
    # Use aider to update the deadlines table
    DEADLINES_MESSAGE="Review the daily brief and extract any deadlines mentioned. Update the DEADLINES.md table with:
- Any new deadlines found in the brief (add new rows)
- Update status of existing deadlines if mentioned in the brief
- Keep the table sorted by date (earliest first)
- Use format: YYYY-MM-DD for dates
- Status should be: Upcoming, In Progress, Completed, or Missed
- Add relevant notes from the brief

Only update the table if there are actual deadlines mentioned. If no deadlines are found, leave the table unchanged."
    
    if [ "${AIDER_MODEL}" = "default" ]; then
        aider --message "${DEADLINES_MESSAGE}" --yes --read "${BRIEF_OUTPUT_FILE}" "${DEADLINES_FILE}"
    else
        aider --model "${AIDER_MODEL}" --message "${DEADLINES_MESSAGE}" --yes --read "${BRIEF_OUTPUT_FILE}" "${DEADLINES_FILE}"
    fi
    
    if [ $? -eq 0 ]; then
        echo "Deadlines table updated successfully"
    else
        echo "Warning: Could not update deadlines table. Continuing..."
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
    echo "Error generating daily brief. Check aider output for details."
fi
