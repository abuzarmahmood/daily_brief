# calendar command: calme agenda

LOG_PATH=/home/abuzarmahmood/Desktop/abu_log
CALENDAR_LOG="${LOG_PATH}/calendar_data.log"

# Create log directory if it doesn't exist
mkdir -p "${LOG_PATH}"

# Get current date for logging
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")

# Run the calendar command and save output to log file
echo "=== Calendar data collected on ${CURRENT_DATE} ===" >> "${CALENDAR_LOG}"
calme agenda >> "${CALENDAR_LOG}" 2>&1
echo "" >> "${CALENDAR_LOG}"  # Add empty line for readability

echo "Calendar data collected and saved to ${CALENDAR_LOG}"
