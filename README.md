# Unattended SFTP File Transfer

Automated PowerShell scripts for unattended SFTP file transfers using WinSCP. Features include configurable retry logic, comprehensive logging, email notifications, file filtering, and backup capabilities.

## Features

- **Import/Export Operations** - Download files from or upload files to SFTP servers
- **Health Check Mode** - Test connectivity without transferring files
- **Retry Logic** - Automatic retry with exponential backoff for transient failures
- **Comprehensive Logging** - Timestamped logs with configurable levels
- **Notifications** - Alerts via Microsoft Teams, Slack, webhooks, or Microsoft Graph API (OAuth 2.0)
- **File Filtering** - Include/exclude patterns for selective transfers
- **Backup Before Delete** - Optional backup of files before deletion (export mode)
- **Transfer Summaries** - Detailed reports of transfer operations
- **Modular Architecture** - Reusable PowerShell modules

## Requirements

- **PowerShell 5.1** or later
- **WinSCP** with .NET assembly (`WinSCPnet.dll`)
  - Download from [winscp.net](https://winscp.net/eng/downloads.php)
  - Install WinSCP or download the .NET assembly separately
- **SSH Private Key** in PPK format (convert with PuTTYgen if needed)

## Quick Start

1. **Clone or download** this repository

2. **Copy configuration template**:
   ```powershell
   Copy-Item .env.example .env
   ```

3. **Edit `.env`** with your settings:
   - Set `winscp_path` to your WinSCPnet.dll location
   - Configure SFTP connection details
   - Set local and remote paths for transfers
   - See [Configuration](#configuration) for all options

4. **Test connectivity**:
   ```powershell
   .\main.ps1 -Mode healthcheck
   ```

5. **Run a transfer**:
   ```powershell
   # Download files from SFTP
   .\main.ps1 -Mode import

   # Upload files to SFTP
   .\main.ps1 -Mode export
   ```

## Usage

### Basic Commands

```powershell
# Health check - test connection without transfers
.\main.ps1 -Mode healthcheck

# Import - download files from remote to local
.\main.ps1 -Mode import

# Export - upload files from local to remote
.\main.ps1 -Mode export

# Verbose output
.\main.ps1 -Mode export -Verbose

# Custom config file
.\main.ps1 -Mode import -ConfigPath C:\configs\production.env
```

### Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success - all operations completed |
| 1 | Configuration error |
| 2 | Connection error |
| 3 | Transfer error - all transfers failed |
| 4 | Partial success - some transfers failed |

## Configuration

Copy `.env.example` to `.env` and configure:

### Required Settings

```ini
# Path to WinSCP .NET assembly
winscp_path = C:\Program Files (x86)\WinSCP\WinSCPnet.dll

# SFTP server connection
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = your_username
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx:xx...

# SSH private key
privkey_path = C:\path\to\key.ppk
```

### Transfer Paths

```ini
# Import: remote -> local
remote_import_path = /remote/path
local_import_path = C:\local\path

# Export: local -> remote (comma-separated for multiple)
local_export_path = C:\path1,C:\path2
remote_export_path = /remote/destination
```

### Optional Features

```ini
# Logging
log_enabled = true
log_path = logs
log_level = INFO

# Retry logic
retry_enabled = true
retry_attempts = 3

# File filtering
include_pattern = *.csv,*.xlsx
exclude_pattern = *.tmp

# Notifications (Teams, Slack, webhook, or Graph API)
notify_enabled = true
notify_provider = msteams
notify_webhook_url = https://your-teams-webhook-url

# Or use Microsoft Graph API for email (OAuth 2.0)
# notify_provider = graph
# notify_graph_tenant_id = your-tenant-id
# notify_graph_client_id = your-client-id
# notify_graph_client_secret_path = C:\secrets\client_secret.txt
# notify_graph_from = alerts@yourdomain.com
# notify_graph_to = admin@yourdomain.com

# Backup before delete (export mode)
backup_enabled = true
backup_path = backups
```

See [.env.example](.env.example) for all configuration options.

## Project Structure

```
unattended_sftp/
├── main.ps1              # Entry point
├── import.ps1            # Import (download) operations
├── export.ps1            # Export (upload) operations
├── .env.example          # Configuration template
├── .env                  # Your configuration (git-ignored)
│
├── modules/              # PowerShell modules
│   ├── SftpConfig/       # Configuration loading
│   ├── SftpLogger/       # Logging functionality
│   ├── SftpRetry/        # Retry logic
│   ├── SftpNotification/ # Email notifications
│   └── SftpTransfer/     # Core transfer operations
│
├── tests/                # Pester unit tests
├── docs/                 # Documentation
├── logs/                 # Log files (git-ignored)
└── backups/              # Backup files (git-ignored)
```

## Scheduling

For automated/scheduled transfers, see [Task Scheduler Setup](docs/TASK_SCHEDULER.md).

Quick example using PowerShell:

```powershell
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\sftp\main.ps1" -Mode export' `
    -WorkingDirectory "C:\sftp"

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"

Register-ScheduledTask -TaskName "SFTP Export" -Action $action -Trigger $trigger
```

## Testing

Run the Pester test suite:

```powershell
# Install Pester if needed
Install-Module Pester -Force -SkipPublisherCheck

# Run all tests
Invoke-Pester .\tests\

# Run specific test file
Invoke-Pester .\tests\SftpConfig.Tests.ps1

# Run with detailed output
Invoke-Pester .\tests\ -Output Detailed
```

## Documentation

- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Task Scheduler Setup](docs/TASK_SCHEDULER.md) - Windows scheduling guide
- [SSH Fingerprint Guide](docs/SSH_FINGERPRINT_GUIDE.md) - Obtaining and managing SSH fingerprints
- [Notifications Setup](docs/NOTIFICATIONS.md) - Teams, Slack, webhooks, and Microsoft Graph setup

## Backward Compatibility

This version is backward compatible with the original scripts:

- Existing `.env` files will work (new settings use defaults)
- Same command-line interface: `.\main.ps1 -Mode import|export`
- Same exit behavior

New features are opt-in through configuration.

## Modules

The functionality is organized into reusable PowerShell modules:

| Module | Description |
|--------|-------------|
| SftpConfig | Configuration loading, parsing, and validation |
| SftpLogger | Logging with timestamps, levels, and rotation |
| SftpRetry | Retry logic with exponential backoff |
| SftpNotification | Email notifications via SMTP |
| SftpTransfer | Core transfer operations and file filtering |

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## Support

- Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- Review log files in the `logs/` directory
- Open an issue on GitHub
