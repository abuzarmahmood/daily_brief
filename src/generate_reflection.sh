#!/bin/bash

# Parse command line arguments
START_DATE=""
END_DATE=$(date +"%Y-%m-%d")
USER_MESSAGE=""

while getopts "s:e:m:" opt; do
    case $opt in
        s)
            START_DATE="$OPTARG"
            ;;
        e)
            END_DATE="$OPTARG"
            ;;
        m)
            USER_MESSAGE="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Usage: $0 -s START_DATE [-e END_DATE] [-m \"focus message\"]"
            echo "  -s START_DATE    Start date in YYYY-MM-DD format (required)"
            echo "  -e END_DATE      End date in YYYY-MM-DD format (default: today)"
            echo "  -m MESSAGE       Additional context about what to focus the reflection on"
            exit 1
            ;;
    esac
done

# Validate that start date was provided
if [ -z "${START_DATE}" ]; then
    echo "Error: Start date is required"
    echo "Usage: $0 -s START_DATE [-e END_DATE] [-m \"focus message\"]"
    exit 1
fi

# Validate date formats
if ! date -d "${START_DATE}" &>/dev/null; then
    echo "Error: Invalid start date format. Use YYYY-MM-DD"
    exit 1
fi

if ! date -d "${END_DATE}" &>/dev/null; then
    echo "Error: Invalid end date format. Use YYYY-MM-DD"
    exit 1
fi

# Print current date and time
echo "Reflection generation started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Date range: ${START_DATE} to ${END_DATE}"
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
BRIEF_REPO_PATH=$(jq -r '.paths.brief_repo' "${CONFIG_FILE}")
BRIEF_INPUTS_PATH="${BRIEF_REPO_PATH}/inputs"
BRIEF_OUTPUTS_PATH="${BRIEF_REPO_PATH}/outputs"
AIDER_MODEL=$(jq -r '.aider.model' "${CONFIG_FILE}")

# Create reflections directory if it doesn't exist
REFLECTIONS_PATH="${BRIEF_REPO_PATH}/reflections"
mkdir -p "${REFLECTIONS_PATH}"

# Update brief repository to ensure latest version is present
if [ -d "${BRIEF_REPO_PATH}/.git" ]; then
    echo "Updating brief repository at ${BRIEF_REPO_PATH}..."
    cd "${BRIEF_REPO_PATH}" || { echo "Error: Could not change to brief repo directory ${BRIEF_REPO_PATH}"; exit 1; }
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || echo "No remote to pull from or pull failed, continuing..."
fi

# Create reflection input and output files
REFLECTION_INPUT_FILE="${REFLECTIONS_PATH}/reflection_input_${START_DATE}_to_${END_DATE}.txt"
REFLECTION_OUTPUT_FILE="${REFLECTIONS_PATH}/reflection_${START_DATE}_to_${END_DATE}.md"

# Initialize reflection input file
echo "=== Reflection Input Data ===" > "${REFLECTION_INPUT_FILE}"
echo "Date Range: ${START_DATE} to ${END_DATE}" >> "${REFLECTION_INPUT_FILE}"
echo "" >> "${REFLECTION_INPUT_FILE}"

# Collect all brief inputs and outputs in the date range
echo "Collecting brief data from ${START_DATE} to ${END_DATE}..."

CURRENT_DATE="${START_DATE}"
DAYS_FOUND=0

while [ "$(date -d "${CURRENT_DATE}" +%s)" -le "$(date -d "${END_DATE}" +%s)" ]; do
    YEAR=$(date -d "${CURRENT_DATE}" +"%Y")
    MONTH=$(date -d "${CURRENT_DATE}" +"%m")
    DAY=$(date -d "${CURRENT_DATE}" +"%d")
    
    # Check for brief input file
    INPUT_FILE="${BRIEF_INPUTS_PATH}/brief_input_${CURRENT_DATE}.txt"
    OUTPUT_FILE="${BRIEF_OUTPUTS_PATH}/${YEAR}/${MONTH}/${DAY}.md"
    
    if [ -f "${INPUT_FILE}" ] || [ -f "${OUTPUT_FILE}" ]; then
        echo "Found data for ${CURRENT_DATE}"
        echo "  Input file exists: $([ -f "${INPUT_FILE}" ] && echo "yes" || echo "no")"
        echo "  Output file exists: $([ -f "${OUTPUT_FILE}" ] && echo "yes" || echo "no")"
        DAYS_FOUND=$((DAYS_FOUND + 1))
        
        echo "=== ${CURRENT_DATE} ===" >> "${REFLECTION_INPUT_FILE}"
        echo "" >> "${REFLECTION_INPUT_FILE}"
        
        # Add input data if available
        if [ -f "${INPUT_FILE}" ]; then
            echo "## Raw Input Data (Journal & Calendar):" >> "${REFLECTION_INPUT_FILE}"
            cat "${INPUT_FILE}" >> "${REFLECTION_INPUT_FILE}"
            echo "" >> "${REFLECTION_INPUT_FILE}"
        fi
        
        # Add output brief if available
        if [ -f "${OUTPUT_FILE}" ]; then
            echo "## Generated Daily Brief:" >> "${REFLECTION_INPUT_FILE}"
            cat "${OUTPUT_FILE}" >> "${REFLECTION_INPUT_FILE}"
            echo "" >> "${REFLECTION_INPUT_FILE}"
        fi
        
        echo "---" >> "${REFLECTION_INPUT_FILE}"
        echo "" >> "${REFLECTION_INPUT_FILE}"
    fi
    
    # Move to next day
    CURRENT_DATE=$(date -d "${CURRENT_DATE} + 1 day" +"%Y-%m-%d")
done

if [ ${DAYS_FOUND} -eq 0 ]; then
    echo "Warning: No brief data found in the specified date range"
    echo "Make sure you have generated daily briefs for dates in this range"
    echo ""
    echo "Searched in:"
    echo "  Input path: ${BRIEF_INPUTS_PATH}"
    echo "  Output path: ${BRIEF_OUTPUTS_PATH}"
    echo ""
    echo "Looking for files like:"
    echo "  ${BRIEF_INPUTS_PATH}/brief_input_YYYY-MM-DD.txt"
    echo "  ${BRIEF_OUTPUTS_PATH}/YYYY/MM/DD.md"
fi

echo "Collected data from ${DAYS_FOUND} days"
echo "Reflection input file created at ${REFLECTION_INPUT_FILE}"

# Create empty reflection output file
touch "${REFLECTION_OUTPUT_FILE}"

# Generate reflection using aider
echo "Generating reflection with aider..."

# Build the aider message
AIDER_MESSAGE="Based on the provided daily briefs, journal entries, and calendar data from ${START_DATE} to ${END_DATE}, please generate a thoughtful longer-term reflection.

Instructions:
- Review all the daily briefs and raw input data from the date range
- Identify patterns, themes, and trends across the time period
- Highlight key accomplishments and progress made
- Note any recurring challenges or obstacles
- Reflect on how time was spent and priorities managed
- Provide insights about productivity, habits, and work-life balance
- Suggest areas for improvement or focus going forward
- Format as GitHub markdown with clear sections like:
  ## Overview
  ## Key Accomplishments
  ## Patterns & Themes
  ## Challenges & Obstacles
  ## Time Management & Priorities
  ## Insights & Learnings
  ## Recommendations for Moving Forward
- Use ## for headers, - for bullet points, **bold** for emphasis
- Make it thoughtful, actionable, and easy to read
- Be honest and constructive in the reflection"

# Append user message if provided
if [ -n "${USER_MESSAGE}" ]; then
    echo "Adding user-provided focus context to aider prompt..."
    AIDER_MESSAGE="${AIDER_MESSAGE}

Additional focus areas requested by user:
${USER_MESSAGE}"
fi

# Use configured model or aider's default
if [ "${AIDER_MODEL}" = "default" ]; then
    echo "Using aider's default model..."
    aider --message "${AIDER_MESSAGE}" --yes "${REFLECTION_INPUT_FILE}" "${REFLECTION_OUTPUT_FILE}"
else
    echo "Using configured model: ${AIDER_MODEL}..."
    aider --model "${AIDER_MODEL}" --message "${AIDER_MESSAGE}" --yes "${REFLECTION_INPUT_FILE}" "${REFLECTION_OUTPUT_FILE}"
fi

if [ $? -eq 0 ]; then
    echo "Reflection generated successfully at ${REFLECTION_OUTPUT_FILE}"
    
    # Commit and push the generated reflection to GitHub
    echo "Committing and pushing reflection to GitHub..."
    cd "${BRIEF_REPO_PATH}" || { echo "Error: Could not change to brief repo directory ${BRIEF_REPO_PATH}"; exit 1; }
    
    # Add the new files to git
    git add reflections/
    
    # Commit with a descriptive message
    git commit -m "Add reflection for ${START_DATE} to ${END_DATE}"
    
    # Push to GitHub (assumes remote origin is set up)
    if git push origin main 2>/dev/null || git push origin master 2>/dev/null; then
        echo "Successfully pushed reflection to GitHub"
    else
        echo "Warning: Could not push to GitHub. Make sure remote origin is configured."
        echo "You can manually push later with: cd ${BRIEF_REPO_PATH} && git push origin main"
    fi
else
    echo "Error generating reflection. Check aider output for details."
    exit 1
fi

echo ""
echo "Reflection generation completed at: $(date '+%Y-%m-%d %H:%M:%S')"
