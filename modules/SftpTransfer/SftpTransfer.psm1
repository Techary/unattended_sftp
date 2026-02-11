#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP Transfer module for core transfer operations.
.DESCRIPTION
    Provides functions for SFTP session management, file filtering,
    backup operations, and connection health checks.
#>

function New-SftpSession {
    <#
    .SYNOPSIS
        Creates and opens a WinSCP SFTP session.
    .PARAMETER Config
        Configuration object from Import-SftpConfig.
    .OUTPUTS
        WinSCP.Session object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $sessionOptions = New-Object WinSCP.SessionOptions
    $sessionOptions.Protocol = [WinSCP.Protocol]::Sftp
    $sessionOptions.HostName = $Config.sftp_hostname
    $sessionOptions.PortNumber = [int]$Config.sftp_port
    $sessionOptions.UserName = $Config.sftp_username
    $sessionOptions.SshPrivateKeyPath = $Config.privkey_path
    $sessionOptions.SshHostKeyFingerprint = $Config.SshHostKeyFingerprint

    # Set timeout if specified
    if ($Config.connection_timeout_seconds -and $Config.connection_timeout_seconds -gt 0) {
        $sessionOptions.Timeout = New-TimeSpan -Seconds $Config.connection_timeout_seconds
    }

    # Handle passphrase
    if ($Config.passphrase_path -and (Test-Path $Config.passphrase_path)) {
        $securePassphrase = Get-Content $Config.passphrase_path | ConvertTo-SecureString
        $sessionOptions.PrivateKeyPassphrase = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassphrase)
        )
    }
    elseif ($Config.passphrase_path -and -not (Test-Path $Config.passphrase_path)) {
        # Passphrase path specified but file doesn't exist - prompt for it
        $securePassphrase = Read-Host "Enter passphrase for the private key" -AsSecureString
        $securePassphrase | ConvertFrom-SecureString | Out-File $Config.passphrase_path
        $sessionOptions.PrivateKeyPassphrase = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassphrase)
        )
    }

    $session = New-Object WinSCP.Session
    $session.Open($sessionOptions)

    return $session
}

function Test-SftpConnection {
    <#
    .SYNOPSIS
        Tests SFTP connectivity without transferring files.
    .PARAMETER Config
        Configuration object.
    .OUTPUTS
        PSCustomObject with IsConnected, ServerInfo, and Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $result = @{
        IsConnected = $false
        ServerInfo = $null
        Errors = @()
    }

    $session = $null
    try {
        $session = New-SftpSession -Config $Config
        $result.IsConnected = $session.Opened
        $result.ServerInfo = "Connected to $($Config.sftp_hostname):$($Config.sftp_port) as $($Config.sftp_username)"

        # Try to list root directory to verify access
        try {
            $session.ListDirectory("/") | Out-Null
        }
        catch {
            $result.Errors += "Connected but cannot list root directory: $($_.Exception.Message)"
        }
    }
    catch {
        $result.IsConnected = $false
        $result.Errors += $_.Exception.Message
    }
    finally {
        if ($session) {
            $session.Dispose()
        }
    }

    return [PSCustomObject]$result
}

function Get-FilteredFiles {
    <#
    .SYNOPSIS
        Returns files matching include pattern and not matching exclude pattern.
    .PARAMETER Path
        Directory path to search (local path string or WinSCP RemoteDirectoryInfo).
    .PARAMETER IncludePattern
        Wildcard patterns to include.
    .PARAMETER ExcludePattern
        Wildcard patterns to exclude.
    .PARAMETER Remote
        If true, Path is a WinSCP RemoteDirectoryInfo object.
    .PARAMETER Session
        WinSCP session for remote operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Path,

        [Parameter()]
        [string[]]$IncludePattern = @("*"),

        [Parameter()]
        [string[]]$ExcludePattern = @(),

        [Parameter()]
        [switch]$Remote,

        [Parameter()]
        [object]$Session = $null
    )

    $filteredFiles = @()

    if ($Remote) {
        # Path is a RemoteDirectoryInfo object
        $files = $Path.Files | Where-Object { -not $_.IsDirectory -and $_.Name -ne ".." -and $_.Name -ne "." }

        foreach ($file in $files) {
            $include = $false
            foreach ($pattern in $IncludePattern) {
                if ($file.Name -like $pattern) {
                    $include = $true
                    break
                }
            }

            if ($include) {
                $exclude = $false
                foreach ($pattern in $ExcludePattern) {
                    if ($file.Name -like $pattern) {
                        $exclude = $true
                        break
                    }
                }

                if (-not $exclude) {
                    $filteredFiles += $file
                }
            }
        }
    }
    else {
        # Local path
        $files = Get-ChildItem -Path $Path -File -ErrorAction Stop

        foreach ($file in $files) {
            $include = $false
            foreach ($pattern in $IncludePattern) {
                if ($file.Name -like $pattern) {
                    $include = $true
                    break
                }
            }

            if ($include) {
                $exclude = $false
                foreach ($pattern in $ExcludePattern) {
                    if ($file.Name -like $pattern) {
                        $exclude = $true
                        break
                    }
                }

                if (-not $exclude) {
                    $filteredFiles += $file
                }
            }
        }
    }

    return $filteredFiles
}

function Backup-LocalFile {
    <#
    .SYNOPSIS
        Creates a backup copy of a file before deletion.
    .PARAMETER FilePath
        Full path to the file to backup.
    .PARAMETER BackupPath
        Directory to store backups.
    .PARAMETER RetentionDays
        Days to retain backups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter()]
        [int]$RetentionDays = 7
    )

    if (-not (Test-Path $FilePath)) {
        return
    }

    # Ensure backup directory exists
    if (-not (Test-Path $BackupPath)) {
        New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
    }

    # Create dated subfolder
    $dateFolder = Join-Path $BackupPath (Get-Date -Format "yyyy-MM-dd")
    if (-not (Test-Path $dateFolder)) {
        New-Item -Path $dateFolder -ItemType Directory -Force | Out-Null
    }

    # Generate unique backup filename
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $timestamp = Get-Date -Format "HHmmss"
    $backupFileName = "${timestamp}_${fileName}"
    $backupFilePath = Join-Path $dateFolder $backupFileName

    # Copy file to backup
    Copy-Item -Path $FilePath -Destination $backupFilePath -Force
}

function Clear-OldBackups {
    <#
    .SYNOPSIS
        Removes backup files older than retention period.
    .PARAMETER BackupPath
        Directory containing backups.
    .PARAMETER RetentionDays
        Number of days to retain backups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter()]
        [int]$RetentionDays = 7
    )

    if (-not (Test-Path $BackupPath)) {
        return
    }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

    # Remove old dated folders
    Get-ChildItem -Path $BackupPath -Directory |
        Where-Object {
            # Try to parse folder name as date
            $folderDate = $null
            if ([DateTime]::TryParseExact($_.Name, "yyyy-MM-dd", $null, [System.Globalization.DateTimeStyles]::None, [ref]$folderDate)) {
                return $folderDate -lt $cutoffDate
            }
            return $false
        } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Also clean any loose files older than retention
    Get-ChildItem -Path $BackupPath -File |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function New-SftpSession, Test-SftpConnection, Get-FilteredFiles,
                              Backup-LocalFile, Clear-OldBackups
