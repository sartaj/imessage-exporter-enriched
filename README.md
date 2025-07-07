# iMessage Complete Export & Rename Tool

A comprehensive Swift script that builds on top of [imessage-exporter](https://github.com/ReagentX/imessage-exporter) to export your iMessage conversations and automatically rename them with contact names instead of phone numbers, plus set proper file timestamps based on conversation dates.

## Overview

- **Built on imessage-exporter** - Uses the proven, comprehensive iMessage export tool as its foundation
- **Adds contact name resolution** - Converts phone numbers to readable contact names
- **Smart timestamp management** - Sets file dates based on actual conversation timeline
- **One-command workflow** - Combines export + rename + timestamp in a single step

## Requirements

- macOS (uses Apple's Contacts framework)
- Swift (comes with Xcode or Command Line Tools)
- **[imessage-exporter](https://github.com/ReagentX/imessage-exporter)** - **REQUIRED** - This tool depends entirely on imessage-exporter
- Contacts app with your contacts
- Contacts permission (script will request automatically)

## Installation

### 1. Install imessage-exporter (Required)

This tool **requires** imessage-exporter to function. Install it first:

```
cargo install imessage-exporter
```

or 

```
brew install imessage-exporter
```

### 2. Download This Script

```bash
curl -O https://raw.githubusercontent.com/your-username/imessage-complete/main/imessage_complete.swift
chmod +x imessage_complete.swift
```

### 3. Grant Permissions
- **Contacts permission** (first run will prompt)
- **Full Disk Access** may be required for imessage-exporter to access the Messages database

## Usage

### Basic Usage

```bash
# Export to ./imessage_export with contact names
swift imessage_complete.swift
```

### Advanced Options

```bash
# Export specific date range
swift imessage_complete.swift -s 2023-01-01 -e 2023-12-31

# Skip contact renaming (keep phone numbers)
swift imessage_complete.swift --no-rename

# Custom database path
swift imessage_complete.swift -p /path/to/custom/chat.db

# Verbose output for troubleshooting
swift imessage_complete.swift --verbose
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-o, --output DIR` | Output directory | `./imessage_export` |
| `-f, --format FORMAT` | Export format: `txt` or `html` | `txt` |
| `-c, --copy-method METHOD` | Attachment handling: `disabled`, `clone`, `basic`, `full` | `disabled` |
| `-p, --db-path PATH` | Custom iMessage database path | Default system path |
| `-r, --attachment-root PATH` | Custom attachment root path | Default system path |
| `-s, --start-date DATE` | Start date (YYYY-MM-DD) | None |
| `-e, --end-date DATE` | End date (YYYY-MM-DD) | None |
| `--no-rename` | Skip contact name renaming | False |
| `--dry-run` | Show what would be done without making changes | False |
| `--verbose` | Show detailed output | False |
| `-h, --help` | Show help message | - |

## How It Works

This tool wraps and extends [imessage-exporter](https://github.com/ReagentX/imessage-exporter) with a complete automation workflow:

### Step 1: Export Messages (via imessage-exporter)
Calls `imessage-exporter` with your specified options to export your iMessage database to TXT or HTML files. All imessage-exporter features are supported including:
- Multiple export formats (TXT, HTML)
- Attachment handling options
- Date range filtering
- Custom database paths
- All other [imessage-exporter options](https://github.com/ReagentX/imessage-exporter#usage)

### Step 2: Load Contacts (Swift Contacts Framework)
Accesses your system contacts using Apple's native Contacts framework, which works with all contact sources (iCloud, Exchange, local, etc.).

### Step 3: Rename Files (Custom Logic)
Matches phone numbers and email addresses from export filenames to contact names, handling various phone number formats:
- `+14694268449` → `John Smith.txt`
- `john@example.com` → `John Smith.txt`
- `+14694268449, +15551234567` → `John Smith, Sarah Johnson.txt`

### Step 4: Update Timestamps (Custom Logic)
Parses message content (from imessage-exporter output) to find first and last message dates, then sets:
- **File creation date** = First message timestamp
- **File modification date** = Last message timestamp

## Phone Number Matching

The script handles various phone number formats automatically:
- International: `+1234567890`
- National: `1234567890`
- Local: `234567890`
- Formatted: `(234) 567-890`

All variations are generated and matched against your contacts.

## Troubleshooting

### Contacts Permission
If you get "Contacts access not authorized":
1. Go to **System Preferences → Security & Privacy → Privacy → Contacts**
2. Add Terminal (or your terminal app) to the allowed apps

### No Contacts Found
- Ensure you have contacts in the Contacts app
- Check that contacts have phone numbers/emails
- Verify contacts permission is granted

### No Timestamps Updated
- Check that exported files contain readable timestamps
- Use `--verbose` to see timestamp extraction details
- Ensure files aren't locked by other applications

### Debug Mode
Use verbose output to troubleshoot issues:
```bash
swift imessage_complete.swift --verbose --dry-run
```

**Note**: This tool reads your local iMessage database and contacts. It does not send any data externally and works entirely offline.
