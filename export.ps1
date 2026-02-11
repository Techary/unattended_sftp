#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP export (upload) operations.
.DESCRIPTION
    Uploads files from local directory to remote SFTP server.
    Optionally backs up files before deletion.
    Called by main.ps1 with session and configuration.
.PARAMETER Session
    Active WinSCP session object.
.PARAMETER Config
    Configuration object from Import-SftpConfig.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [WinSCP.Session]$Session,

    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Config
)

$scriptPath = $PSScriptRoot
$modulesPath = Join-Path $scriptPath "modules"

# Import required modules if not already loaded
if (-not (Get-Module SftpLogger)) {
    Import-Module (Join-Path $modulesPath "SftpLogger\SftpLogger.psd1") -Force
}
if (-not (Get-Module SftpTransfer)) {
    Import-Module (Join-Path $modulesPath "SftpTransfer\SftpTransfer.psd1") -Force
}
if (-not (Get-Module SftpRetry)) {
    Import-Module (Join-Path $modulesPath "SftpRetry\SftpRetry.psd1") -Force
}
if (-not (Get-Module SftpConfig)) {
    Import-Module (Join-Path $modulesPath "SftpConfig\SftpConfig.psd1") -Force
}

# Get configuration values
$localPaths = Get-ConfigValue $Config "local_export_path" -Type "array"
$remotePath = Get-ConfigValue $Config "remote_export_path"
$includePattern = Get-ConfigValue $Config "include_pattern" -Default "*" -Type "array"
$excludePattern = Get-ConfigValue $Config "exclude_pattern" -Default @() -Type "array"
$retryEnabled = Get-ConfigValue $Config "retry_enabled" -Default $true -Type "bool"
$retryAttempts = Get-ConfigValue $Config "retry_attempts" -Default 3 -Type "int"
$retryDelay = Get-ConfigValue $Config "retry_delay_seconds" -Default 5 -Type "int"
$retryBackoff = Get-ConfigValue $Config "retry_exponential_backoff" -Default $true -Type "bool"
$backupEnabled = Get-ConfigValue $Config "backup_enabled" -Default $false -Type "bool"
$backupPath = Get-ConfigValue $Config "backup_path" -Default "backups"
$backupRetention = Get-ConfigValue $Config "backup_retention_days" -Default 7 -Type "int"
$remotePathSeparator = Get-ConfigValue $Config "remote_path_separator" -Default $null

# Ensure backup path is absolute
if ($backupEnabled -and -not [System.IO.Path]::IsPathRooted($backupPath)) {
    $backupPath = Join-Path $scriptPath $backupPath
}

$result = @{
    Success = $true
    FilesTransferred = 0
    Errors = [System.Collections.ArrayList]@()
}

# Clean old backups if enabled
if ($backupEnabled) {
    Write-SftpLog "Cleaning old backups (retention: $backupRetention days)" -Level DEBUG
    Clear-OldBackups -BackupPath $backupPath -RetentionDays $backupRetention
}

foreach ($localPath in $localPaths) {
    Write-SftpLog "Processing local path: $localPath" -Level INFO

    try {
        # Get and filter files
        $files = Get-FilteredFiles -Path $localPath `
                                   -IncludePattern $includePattern `
                                   -ExcludePattern $excludePattern

        $totalFiles = @($files).Count
        Write-SftpLog "Found $totalFiles files matching filters" -Level INFO

        if ($totalFiles -eq 0) {
            Write-SftpLog "No files to upload from $localPath" -Level INFO
            continue
        }

        $currentFile = 0
        foreach ($file in $files) {
            $currentFile++
            $joinParams = @{
                BasePath = $remotePath
                ChildPath = $file.Name
            }
            if ($remotePathSeparator) {
                $joinParams.Separator = $remotePathSeparator
            }
            $remoteFilePath = Join-RemotePath @joinParams

            Write-SftpProgress -FileName $file.Name `
                              -CurrentFile $currentFile `
                              -TotalFiles $totalFiles `
                              -TotalBytes $file.Length

            $transferBlock = {
                $transferOptions = New-Object WinSCP.TransferOptions
                $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary
                $transferOptions.PreserveTimestamp = $false
                $transferOptions.FilePermissions = $null

                $transferResult = $Session.PutFiles(
                    $file.FullName,
                    $remoteFilePath,
                    $false,
                    $transferOptions
                )
                $transferResult.Check()

                if (-not $transferResult.IsSuccess) {
                    throw "Transfer failed for $($file.Name)"
                }

                return $transferResult
            }

            try {
                if ($retryEnabled) {
                    $transferResult = Invoke-WithRetry -ScriptBlock $transferBlock `
                        -MaxAttempts $retryAttempts `
                        -DelaySeconds $retryDelay `
                        -ExponentialBackoff $retryBackoff `
                        -OnRetry {
                            Write-SftpLog "Retrying upload of $($file.Name)..." -Level WARNING
                        }
                }
                else {
                    $transferResult = & $transferBlock
                }

                Write-SftpLog "Uploaded '$($file.Name)' to '$remoteFilePath'" -Level INFO
                Add-TransferResult -FileName $file.Name -Success $true -Bytes $file.Length
                $result.FilesTransferred++

                # Backup and delete local file
                if ($backupEnabled) {
                    Backup-LocalFile -FilePath $file.FullName -BackupPath $backupPath -RetentionDays $backupRetention
                    Write-SftpLog "Backed up '$($file.Name)'" -Level DEBUG
                }

                Remove-Item $file.FullName -Force
                Write-SftpLog "Deleted local file '$($file.Name)'" -Level DEBUG

            }
            catch {
                $errorMsg = "Failed to upload '$($file.Name)': $($_.Exception.Message)"
                Write-SftpLog $errorMsg -Level ERROR
                Add-TransferResult -FileName $file.Name -Success $false -ErrorMessage $_.Exception.Message
                [void]$result.Errors.Add($errorMsg)
                $result.Success = $false
            }
        }

    }
    catch {
        $errorMsg = "Error processing path '$localPath': $($_.Exception.Message)"
        Write-SftpLog $errorMsg -Level ERROR
        [void]$result.Errors.Add($errorMsg)
        $result.Success = $false
    }
}

# Return result object (do NOT dispose session here - main.ps1 handles that)
return [PSCustomObject]$result
