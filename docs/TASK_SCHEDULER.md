# Windows Task Scheduler Setup

This guide explains how to schedule the SFTP transfer scripts to run automatically using Windows Task Scheduler.

## Prerequisites

Before creating a scheduled task:

1. Ensure the scripts work correctly when run manually
2. Test with the health check: `.\main.ps1 -Mode healthcheck`
3. If using passphrase encryption, run the script once manually to create the encrypted passphrase file
4. Note the full path to your script directory

## Creating a Scheduled Task

### Option 1: Task Scheduler GUI

1. Open Task Scheduler (press Win+R, type `taskschd.msc`, press Enter)
2. Click "Create Task" (not "Create Basic Task") in the right panel

#### General Tab

- **Name:** `SFTP Export` (or Import)
- **Description:** `Automated SFTP file transfer`
- **Security options:**
  - Select "Run whether user is logged on or not"
  - Check "Run with highest privileges" if accessing protected directories
  - Configure for: Windows 10 (or your Windows version)

#### Triggers Tab

Click "New" to create a trigger:

- **Begin the task:** On a schedule
- **Settings:** Daily, Weekly, or as needed
- **Start:** Set your desired time
- **Advanced settings:**
  - Check "Enabled"
  - Optionally set "Repeat task every" for frequent runs

#### Actions Tab

Click "New" to create an action:

- **Action:** Start a program
- **Program/script:** `powershell.exe`
- **Add arguments:**
  ```
  -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\main.ps1" -Mode export
  ```
- **Start in:** `C:\path\to\script\directory`

#### Conditions Tab

- Check "Start only if the following network connection is available"
- Select your network or "Any connection"
- Optionally uncheck "Start the task only if the computer is on AC power" for laptops

#### Settings Tab

- Check "Allow task to be run on demand"
- Check "Run task as soon as possible after a scheduled start is missed"
- Set "Stop the task if it runs longer than" to an appropriate value (e.g., 1 hour)
- Select "Do not start a new instance" if the task is already running

### Option 2: PowerShell Script

Create the scheduled task programmatically:

```powershell
# Configuration
$TaskName = "SFTP Export"
$ScriptPath = "C:\sftp\main.ps1"
$WorkingDirectory = "C:\sftp"
$Mode = "export"
$ScheduleTime = "02:00AM"

# Create the action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Mode $Mode" `
    -WorkingDirectory $WorkingDirectory

# Create the trigger (daily at 2 AM)
$trigger = New-ScheduledTaskTrigger -Daily -At $ScheduleTime

# Create settings
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 3 `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)

# Create the principal (run as SYSTEM for unattended operation)
$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Register the task
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Automated SFTP file transfer"

Write-Host "Scheduled task '$TaskName' created successfully"
```

### Running as a Service Account

For production environments, consider using a dedicated service account:

1. Create a service account in Active Directory or local users
2. Grant the account:
   - Read/write access to local transfer directories
   - Read access to private key file
   - Read/write access to log directory
3. Use that account when creating the scheduled task

```powershell
# Using a specific user account
$credential = Get-Credential -Message "Enter service account credentials"

Register-ScheduledTask `
    -TaskName "SFTP Export" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User $credential.UserName `
    -Password $credential.GetNetworkCredential().Password
```

## Monitoring Scheduled Tasks

### Check Task Status

```powershell
# View task info
Get-ScheduledTaskInfo -TaskName "SFTP Export"

# Example output:
# LastRunTime      : 1/15/2024 2:00:00 AM
# LastTaskResult   : 0
# NextRunTime      : 1/16/2024 2:00:00 AM
# NumberOfMissedRuns : 0
```

### Result Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | Configuration Error |
| 2 | Connection Error |
| 3 | Transfer Error |
| 4 | Partial Success |
| 267009 | Task is currently running |
| 267014 | Task was terminated by user |

### View Task History

1. Open Task Scheduler
2. Select your task
3. Click "History" tab (enable history if disabled: Action > Enable All Tasks History)

### PowerShell Monitoring

```powershell
# Get last run result
$task = Get-ScheduledTask -TaskName "SFTP Export"
$taskInfo = Get-ScheduledTaskInfo -TaskName "SFTP Export"

Write-Host "Last Run: $($taskInfo.LastRunTime)"
Write-Host "Result: $($taskInfo.LastTaskResult)"
Write-Host "Next Run: $($taskInfo.NextRunTime)"

# Check if task is currently running
if ($task.State -eq "Running") {
    Write-Host "Task is currently running"
}
```

## Multiple Schedules

To run both import and export on different schedules:

```powershell
# Export task - runs at 2 AM
$exportAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\sftp\main.ps1" -Mode export' `
    -WorkingDirectory "C:\sftp"

$exportTrigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"

Register-ScheduledTask -TaskName "SFTP Export" -Action $exportAction -Trigger $exportTrigger ...

# Import task - runs at 6 AM
$importAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\sftp\main.ps1" -Mode import' `
    -WorkingDirectory "C:\sftp"

$importTrigger = New-ScheduledTaskTrigger -Daily -At "06:00AM"

Register-ScheduledTask -TaskName "SFTP Import" -Action $importAction -Trigger $importTrigger ...
```

## Troubleshooting Scheduled Tasks

### Task doesn't run

1. Check the task history for errors
2. Verify the user account has "Log on as a batch job" rights
3. Test running the task manually: Right-click > Run

### Authentication issues

1. If using encrypted passphrase, ensure it was created by the same user account running the task
2. For service accounts, create the passphrase file while logged in as that account

### Scripts work manually but fail in scheduler

1. Check the "Start in" directory is set correctly
2. Verify all paths in .env are absolute paths
3. Check the account has network access if VPN is required
