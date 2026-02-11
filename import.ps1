#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP import (download) operations.
.DESCRIPTION
    Downloads files from remote SFTP server to local directory.
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
$remotePaths = Get-ConfigValue $Config "remote_import_path" -Type "array"
$localPath = Get-ConfigValue $Config "local_import_path"
$includePattern = Get-ConfigValue $Config "include_pattern" -Default "*" -Type "array"
$excludePattern = Get-ConfigValue $Config "exclude_pattern" -Default @() -Type "array"
$retryEnabled = Get-ConfigValue $Config "retry_enabled" -Default $true -Type "bool"
$retryAttempts = Get-ConfigValue $Config "retry_attempts" -Default 3 -Type "int"
$retryDelay = Get-ConfigValue $Config "retry_delay_seconds" -Default 5 -Type "int"
$retryBackoff = Get-ConfigValue $Config "retry_exponential_backoff" -Default $true -Type "bool"
$remotePathSeparator = Get-ConfigValue $Config "remote_path_separator" -Default $null

$result = @{
    Success = $true
    FilesTransferred = 0
    Errors = [System.Collections.ArrayList]@()
}

foreach ($remotePath in $remotePaths) {
    Write-SftpLog "Processing remote path: $remotePath" -Level INFO

    try {
        # List and filter files
        $directoryInfo = $Session.ListDirectory($remotePath)
        $files = Get-FilteredFiles -Path $directoryInfo `
                                   -IncludePattern $includePattern `
                                   -ExcludePattern $excludePattern `
                                   -Remote

        $totalFiles = @($files).Count
        Write-SftpLog "Found $totalFiles files matching filters" -Level INFO

        if ($totalFiles -eq 0) {
            Write-SftpLog "No files to download from $remotePath" -Level INFO
            continue
        }

        $currentFile = 0
        foreach ($fileInfo in $files) {
            $currentFile++
            $joinParams = @{
                BasePath = $remotePath
                ChildPath = $fileInfo.Name
            }
            if ($remotePathSeparator) {
                $joinParams.Separator = $remotePathSeparator
            }
            $remoteFilePath = Join-RemotePath @joinParams
            $localFilePath = Join-Path $localPath $fileInfo.Name

            Write-SftpProgress -FileName $fileInfo.Name `
                              -CurrentFile $currentFile `
                              -TotalFiles $totalFiles `
                              -TotalBytes $fileInfo.Length

            $transferBlock = {
                $transferOptions = New-Object WinSCP.TransferOptions
                $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

                $transferResult = $Session.GetFileToDirectory(
                    $remoteFilePath,
                    $localPath,
                    $false,
                    $transferOptions
                )

                if (-not $transferResult.IsSuccess) {
                    throw "Transfer failed for $($fileInfo.Name)"
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
                            Write-SftpLog "Retrying download of $($fileInfo.Name)..." -Level WARNING
                        }
                }
                else {
                    $transferResult = & $transferBlock
                }

                Write-SftpLog "Downloaded '$($fileInfo.Name)' to '$localFilePath'" -Level INFO
                Add-TransferResult -FileName $fileInfo.Name -Success $true -Bytes $fileInfo.Length
                $result.FilesTransferred++

            }
            catch {
                $errorMsg = "Failed to download '$($fileInfo.Name)': $($_.Exception.Message)"
                Write-SftpLog $errorMsg -Level ERROR
                Add-TransferResult -FileName $fileInfo.Name -Success $false -ErrorMessage $_.Exception.Message
                [void]$result.Errors.Add($errorMsg)
                $result.Success = $false
            }
        }

    }
    catch {
        $errorMsg = "Error processing path '$remotePath': $($_.Exception.Message)"
        Write-SftpLog $errorMsg -Level ERROR
        [void]$result.Errors.Add($errorMsg)
        $result.Success = $false
    }
}

# Return result object (do NOT dispose session here - main.ps1 handles that)
return [PSCustomObject]$result
