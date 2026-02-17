#!/bin/bash

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
eval "gcalcli ${CALENDAR_ARGS} agenda $DATE_TWO_WEEKS_AGO $NEXT_WEEK" >> "${CALENDAR_LOG_FILE}" 2>&1
echo "" >> "${CALENDAR_LOG_FILE}"  # Add empty line for readability

echo "Calendar data collected and saved to ${CALENDAR_LOG_FILE}"

## Collect regular log data 
# Update regular log from git repository
echo "Updating regular log from git repository at ${LOG_PATH}..."
cd "${LOG_PATH}" || { echo "Error: Could not change to log directory ${LOG_PATH}"; exit 1; }
git pull origin master

# Append calendar and jrnl data to brief input file
echo "Collecting journal entries from the last two weeks..."
jrnl -from $DATE_TWO_WEEKS_AGO --format md > "${BRIEF_INPUT_FILE}" 
echo "" >> "${BRIEF_INPUT_FILE}"  # Add empty line for readability
echo "Calendar data:" >> "${BRIEF_INPUT_FILE}"
cat "${CALENDAR_LOG_FILE}" >> "${BRIEF_INPUT_FILE}"

echo "Brief input file created at ${BRIEF_INPUT_FILE}"
echo "Combined journal and calendar data ready for processing"

# Find yesterday's brief file to include in aider input
YESTERDAY_YEAR=$(date -d "yesterday" +"%Y")
YESTERDAY_MONTH=$(date -d "yesterday" +"%m")
YESTERDAY_DAY=$(date -d "yesterday" +"%d")
YESTERDAY_BRIEF_FILE="${BRIEF_OUTPUTS_PATH}/${YESTERDAY_YEAR}/${YESTERDAY_MONTH}/${YESTERDAY_DAY}.md"

if [ -f "${YESTERDAY_BRIEF_FILE}" ]; then
    echo "Found yesterday's brief at ${YESTERDAY_BRIEF_FILE}"
    # Append yesterday's brief content to input for AI to review
    echo "" >> "${BRIEF_INPUT_FILE}"
    echo "Yesterday's brief (${YESTERDAY}):" >> "${BRIEF_INPUT_FILE}"
    cat "${YESTERDAY_BRIEF_FILE}" >> "${BRIEF_INPUT_FILE}"
    echo "Added yesterday's brief to input for AI review"
else
    echo "No brief found from yesterday (${YESTERDAY_BRIEF_FILE}), skipping"
fi

# Create empty brief output file
touch "${BRIEF_OUTPUT_FILE}"

# Generate daily brief using aider
echo "Generating daily brief with aider..."
aider --message "Based on the provided journal entries, calendar data, and yesterday's incomplete items, please generate a concise daily brief and gameplan for today (${TODAY}). 

Instructions:
- The calendar output covers the past 2 weeks through the next 7 days (until ${NEXT_WEEK})
- Also consider yesterday's brief (${YESTERDAY}) when generating today's brief - review any incomplete items listed below and incorporate them into today's action items
- Mark any recurring events scheduled for today as 'recurring' in the brief
- Focus on actionable items and priorities for today
- Include relevant context from recent journal entries
- Also provide a brief overview of upcoming events in the next 7 days
- Include any incomplete items from yesterday's brief in today's Action Items section, clearly marking them as carryover from yesterday
- Format as GitHub markdown with proper headers, bullet points, and sections
- Use markdown formatting like ## for headers, - for bullet points, **bold** for emphasis
- Structure with clear sections like ## Today's Schedule, ## Upcoming Events (Next 7 Days), ## Action Items, ## Notes, etc.
- Make it visually appealing and easy to read in markdown viewers

Please populate the brief output file with a well-formatted GitHub markdown daily brief." --yes "${BRIEF_INPUT_FILE}" "${BRIEF_OUTPUT_FILE}"

if [ $? -eq 0 ]; then
    echo "Daily brief generated successfully at ${BRIEF_OUTPUT_FILE}"
    
    # Commit and push the generated brief to GitHub
    echo "Committing and pushing brief to GitHub..."
    cd "${BRIEF_REPO_PATH}" || { echo "Error: Could not change to brief repo directory ${BRIEF_REPO_PATH}"; exit 1; }
    
    # Add the new files to git
    git add inputs/ outputs/
    
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
