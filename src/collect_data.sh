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
