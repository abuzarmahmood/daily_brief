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
