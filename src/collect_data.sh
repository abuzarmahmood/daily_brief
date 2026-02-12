#!/bin/bash

# calendar command: calme agenda
alias calme='gcalcli --calendar "Personal/Social" --calendar "abuzarmahmood@gmail.com" --calendar "abuzarmahmood@brandeis.edu" --calendar "Course Timetable"'

# New dedicated path for calendar logs
CALENDAR_LOG_PATH="/home/abuzarmahmood/Desktop/calendar_log"
LOG_PATH=/home/abuzarmahmood/Desktop/abu_log
BRIEF_PATH=/home/abuzarmahmood/Desktop/brief_log
BRIEF_INPUTS_PATH=/home/abuzarmahmood/Desktop/brief_inputs
BRIEF_OUTPUTS_PATH=/home/abuzarmahmood/Desktop/brief_outputs

# Create log directories if they don't exist
mkdir -p "${CALENDAR_LOG_PATH}"
mkdir -p "${BRIEF_INPUTS_PATH}"
mkdir -p "${BRIEF_OUTPUTS_PATH}"

## Collect calendar data and save to daily log file
# Get current date for logging and filename
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")
TODAY=$(date +"%Y-%m-%d")
TOMORROW=$(date -d "tomorrow" +"%Y-%m-%d")
DATE_LAST_WEEK=$(date -d "7 days ago" +"%Y-%m-%d") 
CALENDAR_LOG_FILE="${CALENDAR_LOG_PATH}/calendar_${TODAY}.log"
BRIEF_INPUT_FILE="${BRIEF_INPUTS_PATH}/brief_input_${TODAY}.txt"
BRIEF_OUTPUT_FILE="${BRIEF_OUTPUTS_PATH}/brief_output_${TODAY}.txt"

# Run the calendar command and save output to daily log file
echo "=== Calendar data collected on ${CURRENT_DATE} ===" > "${CALENDAR_LOG_FILE}"
gcalcli --calendar "Personal/Social" --calendar "abuzarmahmood@gmail.com" --calendar "abuzarmahmood@brandeis.edu" --calendar "Course Timetable" agenda $DATE_LAST_WEEK $TOMORROW >> "${CALENDAR_LOG_FILE}" 2>&1
echo "" >> "${CALENDAR_LOG_FILE}"  # Add empty line for readability

echo "Calendar data collected and saved to ${CALENDAR_LOG_FILE}"

## Collect regular log data 
# Update regular log from git repository
echo "Updating regular log from git repository at ${LOG_PATH}..."
cd "${LOG_PATH}" || { echo "Error: Could not change to log directory ${LOG_PATH}"; exit 1; }
git pull origin master

# Append calendar and jrnl data to brief input file
echo "Collecting journal entries from the last week..."
jrnl -from $DATE_LAST_WEEK --format md > "${BRIEF_INPUT_FILE}" 
echo "" >> "${BRIEF_INPUT_FILE}"  # Add empty line for readability
echo "Calendar data:" >> "${BRIEF_INPUT_FILE}"
cat "${CALENDAR_LOG_FILE}" >> "${BRIEF_INPUT_FILE}"

echo "Brief input file created at ${BRIEF_INPUT_FILE}"
echo "Combined journal and calendar data ready for processing"

# Generate daily brief using aider
echo "Generating daily brief with aider..."
aider --message "Based on the provided journal entries and calendar data, please generate a concise daily brief and gameplan for today (${TODAY}). 

Instructions:
- The calendar output covers the past 2 weeks through tomorrow
- Mark any recurring events scheduled for today as 'recurring' in the brief
- Focus on actionable items and priorities for today
- Include relevant context from recent journal entries
- Format as a clear, organized brief suitable for daily planning

Please save the output as a well-formatted daily brief." --yes "${BRIEF_INPUT_FILE}" > "${BRIEF_OUTPUT_FILE}" 2>&1

if [ $? -eq 0 ]; then
    echo "Daily brief generated successfully at ${BRIEF_OUTPUT_FILE}"
else
    echo "Error generating daily brief. Check ${BRIEF_OUTPUT_FILE} for details."
fi
