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
CLAUDE_MODEL=$(jq -r '.claude.reflection_model // "sonnet"' "${CONFIG_FILE}")

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
    
    # Check for brief output file
    OUTPUT_FILE="${BRIEF_OUTPUTS_PATH}/${YEAR}/${MONTH}/${DAY}.md"
    
    if [ -f "${OUTPUT_FILE}" ]; then
        echo "Found brief for ${CURRENT_DATE}"
        DAYS_FOUND=$((DAYS_FOUND + 1))
        
        echo "=== ${CURRENT_DATE} ===" >> "${REFLECTION_INPUT_FILE}"
        echo "" >> "${REFLECTION_INPUT_FILE}"
        
        # Add output brief
        cat "${OUTPUT_FILE}" >> "${REFLECTION_INPUT_FILE}"
        echo "" >> "${REFLECTION_INPUT_FILE}"
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
    echo "  Output path: ${BRIEF_OUTPUTS_PATH}"
    echo ""
    echo "Looking for files like:"
    echo "  ${BRIEF_OUTPUTS_PATH}/YYYY/MM/DD.md"
fi

echo "Collected data from ${DAYS_FOUND} days"
echo "Reflection input file created at ${REFLECTION_INPUT_FILE}"

# Create empty reflection output file
touch "${REFLECTION_OUTPUT_FILE}"

# Generate reflection using claude (non-interactive/print mode)
echo "Generating reflection with claude..."

# Build the claude prompt. Unlike aider (which takes explicit file args), claude
# reads/writes files itself via its Read/Write tools, so the prompt just points
# it at the relevant absolute paths.
CLAUDE_MESSAGE="Based on the provided daily briefs from ${START_DATE} to ${END_DATE} in the file at ${REFLECTION_INPUT_FILE}, please generate a thoughtful longer-term reflection.

Instructions:
- Review all the daily briefs from the date range
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
- Be honest and constructive in the reflection

Write the resulting well-formatted GitHub markdown reflection directly to the file at ${REFLECTION_OUTPUT_FILE}, overwriting its current (empty) contents. Do not print the reflection in your response -- only write it to that file."

# Append user message if provided
if [ -n "${USER_MESSAGE}" ]; then
    echo "Adding user-provided focus context to claude prompt..."
    CLAUDE_MESSAGE="${CLAUDE_MESSAGE}

Additional focus areas requested by user:
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

# claude should have written directly to REFLECTION_OUTPUT_FILE via its Write
# tool; treat a still-empty output as a failure too
if [ ${CLAUDE_EXIT_CODE} -eq 0 ] && [ ! -s "${REFLECTION_OUTPUT_FILE}" ]; then
    echo "Error: claude exited successfully but ${REFLECTION_OUTPUT_FILE} is empty."
    CLAUDE_EXIT_CODE=1
fi

if [ ${CLAUDE_EXIT_CODE} -eq 0 ]; then
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
    echo "Error generating reflection. Check claude output for details."
    exit 1
fi

echo ""
echo "Reflection generation completed at: $(date '+%Y-%m-%d %H:%M:%S')"
