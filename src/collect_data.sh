#!/bin/bash

# calendar command: calme agenda
alias calme='gcalcli --calendar "Personal/Social" --calendar "abuzarmahmood@gmail.com" --calendar "abuzarmahmood@brandeis.edu" --calendar "Course Timetable"'

# New dedicated path for calendar logs
CALENDAR_LOG_PATH="/home/abuzarmahmood/Desktop/calendar_log"
LOG_PATH=/home/abuzarmahmood/Desktop/abu_log

# Create log directories if they don't exist
mkdir -p "${LOG_PATH}"
mkdir -p "${CALENDAR_LOG_PATH}"

# Get current date for logging and filename
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")
TODAY=$(date +"%Y-%m-%d")
CALENDAR_LOG_FILE="${CALENDAR_LOG_PATH}/calendar_${TODAY}.log"

# Run the calendar command and save output to daily log file
echo "=== Calendar data collected on ${CURRENT_DATE} ===" > "${CALENDAR_LOG_FILE}"
gcalcli --calendar "Personal/Social" --calendar "abuzarmahmood@gmail.com" --calendar "abuzarmahmood@brandeis.edu" --calendar "Course Timetable" agenda >> "${CALENDAR_LOG_FILE}" 2>&1
echo "" >> "${CALENDAR_LOG_FILE}"  # Add empty line for readability

echo "Calendar data collected and saved to ${CALENDAR_LOG_FILE}"

# Update regular log from git repository
echo "Updating regular log from git repository..."
cd "${LOG_PATH}" || { echo "Error: Could not change to log directory ${LOG_PATH}"; exit 1; }
git pull origin master

# Collect data from regular log
echo "=== Regular log data collected on ${CURRENT_DATE} ===" >> "${CALENDAR_LOG_FILE}"
if [ -f "${LOG_PATH}/log.txt" ]; then
    cat "${LOG_PATH}/log.txt" >> "${CALENDAR_LOG_FILE}"
else
    echo "No regular log file found at ${LOG_PATH}/log.txt" >> "${CALENDAR_LOG_FILE}"
fi
echo "" >> "${CALENDAR_LOG_FILE}"  # Add empty line for readability

echo "Regular log data collected and appended to ${CALENDAR_LOG_FILE}"
