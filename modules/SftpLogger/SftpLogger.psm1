#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP Logging module for comprehensive logging with timestamps and levels.
.DESCRIPTION
    Provides functions for logging with timestamps, log levels, file rotation,
    transfer statistics tracking, and summary reporting.
#>

# Module-level variables
$script:LogPath = $null
$script:LogFile = $null
$script:LogLevel = "INFO"
$script:LogEnabled = $true
$script:LogLevels = @{
    "DEBUG" = 0
    "INFO" = 1
    "WARNING" = 2
    "ERROR" = 3
}
$script:TransferStats = @{
    StartTime = $null
    EndTime = $null
    Mode = $null
    FilesProcessed = 0
    FilesSucceeded = 0
    FilesFailed = 0
    BytesTransferred = 0
    Errors = [System.Collections.ArrayList]@()
    TransferResults = [System.Collections.ArrayList]@()
}

function Initialize-SftpLogging {
    <#
    .SYNOPSIS
        Initializes the logging system with specified configuration.
    .PARAMETER LogPath
        Directory for log files.
    .PARAMETER LogLevel
        Minimum level to log: DEBUG, INFO, WARNING, ERROR.
    .PARAMETER RetentionDays
        Number of days to retain log files.
    .PARAMETER Enabled
        Whether logging is enabled.
    .PARAMETER Mode
        Operation mode for log file naming.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,

        [Parameter()]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")]
        [string]$LogLevel = "INFO",

        [Parameter()]
        [int]$RetentionDays = 30,

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [string]$Mode = "transfer"
    )

    $script:LogEnabled = $Enabled
    $script:LogLevel = $LogLevel

    if (-not $Enabled) {
        return
    }

    # Ensure log path is absolute
    if (-not [System.IO.Path]::IsPathRooted($LogPath)) {
        $LogPath = Join-Path $PSScriptRoot $LogPath
    }

    $script:LogPath = $LogPath

    # Create log directory if it doesn't exist
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    # Create log file with date
    $dateStr = Get-Date -Format "yyyyMMdd"
    $script:LogFile = Join-Path $LogPath "sftp_${Mode}_${dateStr}.log"

    # Clean old logs
    Clear-OldLogs -RetentionDays $RetentionDays

    # Reset transfer stats
    $script:TransferStats = @{
        StartTime = Get-Date
        EndTime = $null
        Mode = $Mode
        FilesProcessed = 0
        FilesSucceeded = 0
        FilesFailed = 0
        BytesTransferred = 0
        Errors = [System.Collections.ArrayList]@()
        TransferResults = [System.Collections.ArrayList]@()
    }
}

function Write-SftpLog {
    <#
    .SYNOPSIS
        Writes a log entry with timestamp and level.
    .PARAMETER Message
        Log message text.
    .PARAMETER Level
        Log level: DEBUG, INFO, WARNING, ERROR.
    .PARAMETER NoConsole
        Suppress console output, write to file only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO",

        [Parameter()]
        [switch]$NoConsole
    )

    process {
        # Check if this level should be logged
        if ($script:LogLevels[$Level] -lt $script:LogLevels[$script:LogLevel]) {
            return
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $levelPadded = $Level.PadRight(5).Substring(0, 5)
        if ($Level -eq "WARNING") { $levelPadded = "WARN " }

        $logEntry = "$timestamp [$levelPadded] $Message"

        # Write to console
        if (-not $NoConsole) {
            $color = switch ($Level) {
                "DEBUG" { "Gray" }
                "INFO" { "White" }
                "WARNING" { "Yellow" }
                "ERROR" { "Red" }
                default { "White" }
            }
            Write-Host $logEntry -ForegroundColor $color
        }

        # Write to file if enabled
        if ($script:LogEnabled -and $script:LogFile) {
            try {
                Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
            }
            catch {
                # Silently fail if we can't write to log
            }
        }
    }
}

function Write-SftpProgress {
    <#
    .SYNOPSIS
        Writes transfer progress information.
    .PARAMETER FileName
        Current file being transferred.
    .PARAMETER CurrentFile
        Current file number in batch.
    .PARAMETER TotalFiles
        Total files in batch.
    .PARAMETER BytesTransferred
        Bytes transferred so far for current file.
    .PARAMETER TotalBytes
        Total bytes for current file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter()]
        [int]$CurrentFile = 0,

        [Parameter()]
        [int]$TotalFiles = 0,

        [Parameter()]
        [long]$BytesTransferred = 0,

        [Parameter()]
        [long]$TotalBytes = 0
    )

    $sizeStr = if ($TotalBytes -gt 0) {
        $sizeMB = [math]::Round($TotalBytes / 1MB, 2)
        if ($sizeMB -ge 1) { "${sizeMB} MB" } else { "$([math]::Round($TotalBytes / 1KB, 1)) KB" }
    } else { "" }

    $progressStr = if ($TotalFiles -gt 0) { "($CurrentFile of $TotalFiles" } else { "(" }
    if ($sizeStr) { $progressStr += ", $sizeStr" }
    $progressStr += ")"

    Write-SftpLog "Processing '$FileName' $progressStr" -Level INFO
}

function Add-TransferResult {
    <#
    .SYNOPSIS
        Records the result of a file transfer for summary reporting.
    .PARAMETER FileName
        Name of the transferred file.
    .PARAMETER Success
        Whether the transfer succeeded.
    .PARAMETER Bytes
        Number of bytes transferred.
    .PARAMETER ErrorMessage
        Error message if transfer failed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [bool]$Success,

        [Parameter()]
        [long]$Bytes = 0,

        [Parameter()]
        [string]$ErrorMessage = ""
    )

    $script:TransferStats.FilesProcessed++

    if ($Success) {
        $script:TransferStats.FilesSucceeded++
        $script:TransferStats.BytesTransferred += $Bytes
    }
    else {
        $script:TransferStats.FilesFailed++
        if ($ErrorMessage) {
            [void]$script:TransferStats.Errors.Add("$FileName : $ErrorMessage")
        }
    }

    [void]$script:TransferStats.TransferResults.Add([PSCustomObject]@{
        FileName = $FileName
        Success = $Success
        Bytes = $Bytes
        ErrorMessage = $ErrorMessage
        Timestamp = Get-Date
    })
}

function Get-TransferSummary {
    <#
    .SYNOPSIS
        Returns a summary of all transfers in the current session.
    .OUTPUTS
        PSCustomObject with transfer statistics.
    #>
    [CmdletBinding()]
    param()

    $script:TransferStats.EndTime = Get-Date
    $duration = $script:TransferStats.EndTime - $script:TransferStats.StartTime

    return [PSCustomObject]@{
        Mode = $script:TransferStats.Mode
        StartTime = $script:TransferStats.StartTime
        EndTime = $script:TransferStats.EndTime
        Duration = $duration
        DurationFormatted = "{0:hh\:mm\:ss}" -f $duration
        FilesProcessed = $script:TransferStats.FilesProcessed
        FilesSucceeded = $script:TransferStats.FilesSucceeded
        FilesFailed = $script:TransferStats.FilesFailed
        BytesTransferred = $script:TransferStats.BytesTransferred
        BytesTransferredFormatted = Format-Bytes $script:TransferStats.BytesTransferred
        Errors = $script:TransferStats.Errors
        TransferResults = $script:TransferStats.TransferResults
        Success = $script:TransferStats.FilesFailed -eq 0
    }
}

function Write-TransferSummary {
    <#
    .SYNOPSIS
        Writes a formatted transfer summary to log and console.
    .PARAMETER NoConsole
        Suppress console output.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$NoConsole
    )

    $summary = Get-TransferSummary

    Write-SftpLog "========================================" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "TRANSFER SUMMARY" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "========================================" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "Mode:              $($summary.Mode)" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "Duration:          $($summary.DurationFormatted)" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "Files Processed:   $($summary.FilesProcessed)" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "Files Succeeded:   $($summary.FilesSucceeded)" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "Files Failed:      $($summary.FilesFailed)" -Level INFO -NoConsole:$NoConsole
    Write-SftpLog "Data Transferred:  $($summary.BytesTransferredFormatted)" -Level INFO -NoConsole:$NoConsole

    if ($summary.Errors.Count -gt 0) {
        Write-SftpLog "----------------------------------------" -Level INFO -NoConsole:$NoConsole
        Write-SftpLog "ERRORS:" -Level ERROR -NoConsole:$NoConsole
        foreach ($error in $summary.Errors) {
            Write-SftpLog "  - $error" -Level ERROR -NoConsole:$NoConsole
        }
    }

    Write-SftpLog "========================================" -Level INFO -NoConsole:$NoConsole

    $status = if ($summary.Success) { "SUCCESS" }
              elseif ($summary.FilesSucceeded -gt 0) { "PARTIAL SUCCESS" }
              else { "FAILED" }
    Write-SftpLog "Status: $status" -Level $(if ($summary.Success) { "INFO" } else { "ERROR" }) -NoConsole:$NoConsole
}

function Clear-OldLogs {
    <#
    .SYNOPSIS
        Removes log files older than retention period.
    .PARAMETER RetentionDays
        Number of days to retain logs.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$RetentionDays = 30
    )

    if (-not $script:LogPath -or -not (Test-Path $script:LogPath)) {
        return
    }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

    Get-ChildItem -Path $script:LogPath -Filter "*.log" -File |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Format-Bytes {
    <#
    .SYNOPSIS
        Formats bytes into human-readable string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

Export-ModuleMember -Function Initialize-SftpLogging, Write-SftpLog, Write-SftpProgress,
                              Add-TransferResult, Get-TransferSummary, Write-TransferSummary,
                              Clear-OldLogs, Format-Bytes
