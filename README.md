# Daily AI Brief Generator

Automated daily brief generation using:

## Requirements

- **jq** - JSON parser for reading configuration file
- **gcalcli** - Google Calendar CLI for fetching calendar events
- **jrnl** - Journal CLI for accessing journal entries
- **git** - Version control (usually pre-installed)
- **aider** - AI assistant for generating daily briefs

## Installation

### 1. Install system dependencies

**macOS (using Homebrew):**
```bash
brew install jq gcalcli jrnl git
pip install aider
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y jq git
pip install gcalcli jrnl aider
```

**Fedora/RHEL:**
```bash
sudo dnf install jq git
pip install gcalcli jrnl aider
```

### 2. Configure Google Calendar

1. Install gcalcli following the instructions at https://github.com/insanum/gcalcli
2. Run `gcalcli oauth` to authenticate with Google Calendar
3. Or use `gcalcli --config-folder <path> add` to add your Google account

### 3. Configure jrnl

1. Install jrnl following the instructions at https://jrnl.sh/
2. Run `jrnl --setup` to initialize your journal
3. Configure your journal settings in `~/.jrnlrc`

### 4. Configure the application

Copy `config.json` to your home directory or adjust the paths in `config.json`:
- Update calendar paths to point to your log directories
- Update the brief repository path to your preferred location

### 5. Set up the GitHub repository

Create a GitHub repository for storing daily briefs and configure the remote:
```bash
cd /path/to/your/brief/repo
git remote add origin https://github.com/yourusername/your-repo.git
```

## Data Sources
- **Calendar** (via gcalcli)
  - Personal/Social calendar
  - Email calendars
  - Course timetable
- **Journal entries** (via jrnl)
  - Past two weeks of entries
- **Todo log**
  - Access to GitHub log repository

## Features
- Hierarchical organization of briefs by year/month/day
- GitHub markdown formatting for easy viewing
- Consolidated git repository for inputs and outputs
- Dynamic configuration loading from JSON

## Usage
```bash
./src/generate_brief.sh
```

### Command-line Options
- `-m "message"` - Add additional context/message for aider when generating the brief
- `-d YYYY-MM-DD` - Generate brief for a specific date (defaults to today)

Example:
```bash
./src/generate_brief.sh -m "Focus on project deadline" -d 2024-01-15
```

### Scheduling with Crontab

You can automate daily brief generation by adding entries to your crontab. Here are two common approaches:

#### Option 1: Morning Brief (Recommended)
Generate a fresh brief each morning with the latest calendar and journal data:

```bash
crontab -e
```

Add this line to generate a brief at 7:00 AM every weekday:
```
0 7 * * 1-5 cd /path/to/brief/repo && /path/to/src/generate_brief.sh >> /tmp/brief_generation.log 2>&1
```

#### Option 2: End-of-Day Update
Update logs and calendar data at the end of the day (useful for tracking incomplete items):

```bash
0 18 * * 1-5 cd /path/to/brief/repo && /path/to/src/generate_brief.sh -m "End of day update - review incomplete items" >> /tmp/brief_generation.log 2>&1
```

#### Option 3: Both Morning and Evening
Combine both approaches for comprehensive daily tracking:

```bash
# Morning brief at 7:00 AM
0 7 * * 1-5 cd /path/to/brief/repo && /path/to/src/generate_brief.sh >> /tmp/brief_generation.log 2>&1

# Evening update at 6:00 PM
0 18 * * 1-5 cd /path/to/brief/repo && /path/to/src/generate_brief.sh -m "End of day review" >> /tmp/brief_generation.log 2>&1
```

**Notes:**
- Replace `/path/to/brief/repo` and `/path/to/src/generate_brief.sh` with your actual paths
- The `>> /tmp/brief_generation.log 2>&1` redirects output to a log file for debugging
- `1-5` in the cron schedule means Monday-Friday; use `*` for every day
- Ensure the script has execute permissions: `chmod +x src/generate_brief.sh`
- Make sure all required tools (gcalcli, jrnl, aider) are accessible in your cron environment

#### Important: PATH Configuration for Cron

Cron runs with a minimal PATH environment, which can cause commands like `jrnl`, `aider`, and `gcalcli` to not be found. To fix this, you have two options:

**Option A: Extend the PATH in your crontab**

Add this line at the top of your crontab (before your cron jobs):
```bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/home/USERNAME/.local/bin
```

Then your cron entries will work:
```bash
0 7 * * 1-5 cd /path/to/brief/repo && /path/to/src/generate_brief.sh >> /tmp/brief_generation.log 2>&1
```

**Option B: Use a Python virtual environment (Recommended)**

If you installed Python packages in a virtual environment:
```bash
0 7 * * 1-5 source /path/to/venv/bin/activate && cd /path/to/brief/repo && /path/to/src/generate_brief.sh >> /tmp/brief_generation.log 2>&1
```

**Option C: Use full paths to commands**

Find the full paths to your commands:
```bash
which jrnl
which aider
which gcalcli
```

Then update your crontab to use these full paths in the script, or set them as environment variables.

**Debugging cron issues:**

If your cron job fails, check the log file:
```bash
tail -f /tmp/brief_generation.log
```

Common issues:
- `jrnl command not found` - jrnl is not in the cron PATH
- `aider command not found` - aider is not in the cron PATH
- `gcalcli command not found` - gcalcli is not in the cron PATH
- `jq command not found` - jq is not installed or not in PATH

To verify your cron environment, add this test job:
```bash
0 6 * * 1-5 env > /tmp/cron_env.log 2>&1
```

Then check `/tmp/cron_env.log` to see what PATH and other variables are available.

## Configuration
Personal information and paths are stored in `config.json` (not committed to repo).

### config.json Structure
```json
{
  "calendars": [
    "Calendar Name 1",
    "Calendar Name 2"
  ],
  "paths": {
    "calendar_log": "/path/to/calendar/logs",
    "log": "/path/to/todo/log/repo",
    "brief_repo": "/path/to/brief/repo"
  },
  "aider": {
    "model": "default"
  }
}
```

### AI Model Configuration
The `aider.model` setting controls which AI model is used to generate daily briefs:
- Set to `"default"` to use aider's default model
- Set to a specific model name (e.g., `"gpt-4"`, `"claude-3-opus-20240229"`, `"gpt-3.5-turbo"`) to use that model
- See [aider's model documentation](https://aider.chat/docs/llms.html) for available models and configuration

Example with specific model:
```json
{
  "aider": {
    "model": "gpt-4"
  }
}
```
