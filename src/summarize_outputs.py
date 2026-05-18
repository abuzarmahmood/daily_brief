#!/usr/bin/env python3
"""
Summarize daily briefs from a date range into a single compiled document.

This script reads daily brief files from the outputs directory, uses aider
to extract non-redundant information, and compiles it into a single summary document.
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Tuple


def load_config() -> dict:
    """Load configuration from config.json."""
    script_dir = Path(__file__).parent
    config_path = script_dir.parent / "config.json"
    
    if not config_path.exists():
        print(f"Error: Config file not found at {config_path}", file=sys.stderr)
        sys.exit(1)
    
    with open(config_path, 'r') as f:
        return json.load(f)


def parse_date(date_str: str) -> datetime:
    """Parse a date string in YYYY-MM-DD format."""
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        print(f"Error: Invalid date format '{date_str}'. Use YYYY-MM-DD format.", file=sys.stderr)
        sys.exit(1)


def get_date_range(start_date: datetime, end_date: datetime) -> List[datetime]:
    """Generate a list of dates between start_date and end_date (inclusive)."""
    dates = []
    current = start_date
    while current <= end_date:
        dates.append(current)
        current += timedelta(days=1)
    return dates


def find_brief_files(brief_outputs_path: Path, dates: List[datetime]) -> List[Tuple[datetime, Path]]:
    """Find all brief files for the given dates."""
    brief_files = []
    
    for date in dates:
        year = date.strftime("%Y")
        month = date.strftime("%m")
        day = date.strftime("%d")
        
        brief_file = brief_outputs_path / year / month / f"{day}.md"
        
        if brief_file.exists():
            brief_files.append((date, brief_file))
        else:
            print(f"Warning: No brief found for {date.strftime('%Y-%m-%d')}", file=sys.stderr)
    
    return brief_files


def create_combined_input_file(brief_files: List[Tuple[datetime, Path]], input_file_path: Path) -> None:
    """Create a combined input file with all briefs for the date range."""
    with open(input_file_path, 'w') as f:
        for date, file_path in brief_files:
            date_str = date.strftime("%Y-%m-%d (%A)")
            
            with open(file_path, 'r') as brief_file:
                brief_content = brief_file.read()
            
            f.write(f"# Brief for {date_str}\n\n")
            f.write(brief_content)
            f.write("\n\n" + "="*80 + "\n\n")


def summarize_with_aider(input_file: Path, output_file: Path, start_date: str, end_date: str, config: dict) -> None:
    """Use aider to extract non-redundant information and create a summary."""
    
    aider_message = f"""You are tasked with creating a comprehensive summary of daily briefs from {start_date} to {end_date}.

The input file contains all the daily briefs for this period, separated by lines of equal signs.

Please analyze these briefs and populate the output file with a single compiled summary document that:

1. Extracts all non-redundant information (avoid repeating the same information that appears across multiple days)
2. Organizes information by themes or categories (e.g., work projects, personal goals, meetings, accomplishments)
3. Highlights key accomplishments and progress made during this period
4. Identifies recurring themes, patterns, or ongoing tasks
5. Notes any incomplete items or tasks that carried over multiple days
6. Provides a coherent narrative of the time period

Format the output as a well-structured markdown document with:
- A title: "# Summary: {start_date} to {end_date}"
- A generation timestamp
- Clear sections with headers (##, ###) to organize different themes or categories
- Bullet points for details
- Be concise but comprehensive - capture the essential information without unnecessary repetition

Write the complete summary to the output file."""

    # Build aider command
    aider_model = config.get('aider', {}).get('model', 'default')
    
    cmd = ['aider', '--message', aider_message, '--yes']
    
    # Add model flag if not default
    if aider_model != 'default':
        cmd.extend(['--model', aider_model])
    
    # Add read-only input file and writable output file
    cmd.extend(['--read', str(input_file), str(output_file)])
    
    print(f"Running aider to generate summary...", file=sys.stderr)
    
    # Run aider
    result = subprocess.run(cmd, capture_output=False)
    
    if result.returncode != 0:
        print(f"Error: aider command failed with return code {result.returncode}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Summarize daily briefs from a date range into a single document using aider."
    )
    parser.add_argument(
        "--start",
        required=True,
        help="Start date in YYYY-MM-DD format"
    )
    parser.add_argument(
        "--end",
        required=True,
        help="End date in YYYY-MM-DD format"
    )
    parser.add_argument(
        "--output",
        help="Output file path (default: summary_START_to_END.md in brief repo root)"
    )
    
    args = parser.parse_args()
    
    # Parse dates
    start_date = parse_date(args.start)
    end_date = parse_date(args.end)
    
    if start_date > end_date:
        print("Error: Start date must be before or equal to end date.", file=sys.stderr)
        sys.exit(1)
    
    # Load configuration
    config = load_config()
    brief_repo_path = Path(config['paths']['brief_repo'])
    brief_outputs_path = brief_repo_path / "outputs"
    
    if not brief_outputs_path.exists():
        print(f"Error: Brief outputs directory not found at {brief_outputs_path}", file=sys.stderr)
        sys.exit(1)
    
    # Generate date range
    dates = get_date_range(start_date, end_date)
    print(f"Processing {len(dates)} days from {args.start} to {args.end}...", file=sys.stderr)
    
    # Find brief files
    brief_files = find_brief_files(brief_outputs_path, dates)
    
    if not brief_files:
        print("Error: No brief files found for the specified date range.", file=sys.stderr)
        sys.exit(1)
    
    print(f"Found {len(brief_files)} brief files.", file=sys.stderr)
    
    # Create temporary input file with all briefs
    input_filename = f"summary_input_{args.start}_to_{args.end}.txt"
    input_file_path = brief_repo_path / input_filename
    
    print(f"Creating combined input file at {input_file_path}...", file=sys.stderr)
    create_combined_input_file(brief_files, input_file_path)
    
    # Determine output file path
    if args.output:
        output_path = Path(args.output)
    else:
        output_filename = f"summary_{args.start}_to_{args.end}.md"
        output_path = brief_repo_path / output_filename
    
    # Create empty output file
    output_path.touch()
    
    # Generate summary using aider
    summarize_with_aider(input_file_path, output_path, args.start, args.end, config)
    
    print(f"\nSummary successfully generated at: {output_path}", file=sys.stderr)
    print(f"\nTo view the summary, run:", file=sys.stderr)
    print(f"  cat {output_path}", file=sys.stderr)
    
    # Clean up temporary input file
    print(f"\nCleaning up temporary input file...", file=sys.stderr)
    input_file_path.unlink()


if __name__ == "__main__":
    main()
