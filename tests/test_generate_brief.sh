#!/bin/bash

# Test script to verify changes to generate_brief.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATE_BRIEF_SCRIPT="${SCRIPT_DIR}/../src/generate_brief.sh"

# Test 1: Verify NEXT_WEEK variable is defined
test_next_week_defined() {
    if grep -q 'NEXT_WEEK=$(date -d "+7 days"' "$GENERATE_BRIEF_SCRIPT"; then
        echo "✓ Test 1 PASSED: NEXT_WEEK variable is defined"
        return 0
    else
        echo "✗ Test 1 FAILED: NEXT_WEEK variable is not defined"
        return 1
    fi
}

# Test 2: Verify calendar command uses NEXT_WEEK instead of TOMORROW
test_calendar_uses_next_week() {
    if grep -q 'agenda $DATE_TWO_WEEKS_AGO $NEXT_WEEK' "$GENERATE_BRIEF_SCRIPT"; then
        echo "✓ Test 2 PASSED: Calendar command uses NEXT_WEEK"
        return 0
    else
        echo "✗ Test 2 FAILED: Calendar command does not use NEXT_WEEK"
        return 1
    fi
}

# Test 3: Verify aider message includes upcoming events briefing
test_aider_message_upcoming_events() {
    if grep -q 'upcoming events in the next 7 days' "$GENERATE_BRIEF_SCRIPT"; then
        echo "✓ Test 3 PASSED: Aider message includes upcoming events instruction"
        return 0
    else
        echo "✗ Test 3 FAILED: Aider message does not include upcoming events instruction"
        return 1
    fi
}

# Test 4: Verify aider message includes NEXT_WEEK in instructions
test_aider_message_includes_next_week() {
    if grep -q 'through the next 7 days (until ${NEXT_WEEK})' "$GENERATE_BRIEF_SCRIPT"; then
        echo "✓ Test 4 PASSED: Aider message includes NEXT_WEEK in instructions"
        return 0
    else
        echo "✗ Test 4 FAILED: Aider message does not include NEXT_WEEK in instructions"
        return 1
    fi
}

# Test 5: Verify aider message includes Upcoming Events section
test_aider_message_upcoming_section() {
    if grep -q '## Upcoming Events (Next 7 Days)' "$GENERATE_BRIEF_SCRIPT"; then
        echo "✓ Test 5 PASSED: Aider message includes Upcoming Events section"
        return 0
    else
        echo "✗ Test 5 FAILED: Aider message does not include Upcoming Events section"
        return 1
    fi
}

# Run all tests
echo "Running tests for generate_brief.sh changes..."
echo ""

FAILED=0

test_next_week_defined || FAILED=1
test_calendar_uses_next_week || FAILED=1
test_aider_message_upcoming_events || FAILED=1
test_aider_message_includes_next_week || FAILED=1
test_aider_message_upcoming_section || FAILED=1

echo ""
if [ $FAILED -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
