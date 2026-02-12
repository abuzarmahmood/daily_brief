#!/bin/bash

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
BRIEF_PATH=$(jq -r '.paths.brief' "${CONFIG_FILE}")
BRIEF_INPUTS_PATH=$(jq -r '.paths.brief_inputs' "${CONFIG_FILE}")
BRIEF_OUTPUTS_PATH=$(jq -r '.paths.brief_outputs' "${CONFIG_FILE}")

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

## Collect calendar data and save to daily log file
# Get current date for logging and filename
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")
TODAY=$(date +"%Y-%m-%d")
TOMORROW=$(date -d "tomorrow" +"%Y-%m-%d")
DATE_TWO_WEEKS_AGO=$(date -d "14 days ago" +"%Y-%m-%d") 
CALENDAR_LOG_FILE="${CALENDAR_LOG_PATH}/calendar_${TODAY}.log"
BRIEF_INPUT_FILE="${BRIEF_INPUTS_PATH}/brief_input_${TODAY}.txt"
BRIEF_OUTPUT_FILE="${BRIEF_OUTPUTS_PATH}/brief_output_${TODAY}.md"

# Run the calendar command and save output to daily log file
echo "=== Calendar data collected on ${CURRENT_DATE} ===" > "${CALENDAR_LOG_FILE}"
eval "gcalcli ${CALENDAR_ARGS} agenda $DATE_TWO_WEEKS_AGO $TOMORROW" >> "${CALENDAR_LOG_FILE}" 2>&1
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

# Create empty brief output file
touch "${BRIEF_OUTPUT_FILE}"

# Generate daily brief using aider
echo "Generating daily brief with aider..."
aider --message "Based on the provided journal entries and calendar data, please generate a concise daily brief and gameplan for today (${TODAY}). 

Instructions:
- The calendar output covers the past 2 weeks through tomorrow
- Mark any recurring events scheduled for today as 'recurring' in the brief
- Focus on actionable items and priorities for today
- Include relevant context from recent journal entries
- Format as GitHub markdown with proper headers, bullet points, and sections
- Use markdown formatting like ## for headers, - for bullet points, **bold** for emphasis
- Structure with clear sections like ## Today's Schedule, ## Action Items, ## Notes, etc.
- Make it visually appealing and easy to read in markdown viewers

Please populate the brief output file with a well-formatted GitHub markdown daily brief." --yes "${BRIEF_INPUT_FILE}" "${BRIEF_OUTPUT_FILE}"

if [ $? -eq 0 ]; then
    echo "Daily brief generated successfully at ${BRIEF_OUTPUT_FILE}"
else
    echo "Error generating daily brief. Check aider output for details."
fi
