#Requires -Version 5.1
<#
.SYNOPSIS
    Unattended SFTP file transfer utility.
.DESCRIPTION
    Automated SFTP import/export with logging, retry logic,
    notifications, and comprehensive error handling.
.PARAMETER Mode
    Operation mode: import, export, or healthcheck.
.PARAMETER ConfigPath
    Path to .env configuration file. Defaults to .env in script directory.
.EXAMPLE
    .\main.ps1 -Mode export
.EXAMPLE
    .\main.ps1 -Mode healthcheck -ConfigPath C:\config\prod.env
.EXAMPLE
    .\main.ps1 -Mode import -Verbose
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("import", "export", "healthcheck")]
    [string]$Mode,

    [Parameter()]
    [string]$ConfigPath
)

# Exit codes
$script:EXIT_SUCCESS = 0
$script:EXIT_CONFIG_ERROR = 1
$script:EXIT_CONNECTION_ERROR = 2
$script:EXIT_TRANSFER_ERROR = 3
$script:EXIT_PARTIAL_SUCCESS = 4

$scriptPath = $PSScriptRoot
$exitCode = $EXIT_SUCCESS

# Import modules
$modulesPath = Join-Path $scriptPath "modules"
try {
    Import-Module (Join-Path $modulesPath "SftpConfig\SftpConfig.psd1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesPath "SftpLogger\SftpLogger.psd1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesPath "SftpRetry\SftpRetry.psd1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesPath "SftpNotification\SftpNotification.psd1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesPath "SftpTransfer\SftpTransfer.psd1") -Force -ErrorAction Stop
}
catch {
    Write-Error "Failed to load required modules: $($_.Exception.Message)"
    Write-Error "Please ensure all modules are present in the 'modules' directory."
    exit $EXIT_CONFIG_ERROR
}

try {
    # Load and validate configuration
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $scriptPath ".env"
    }

    Write-Verbose "Loading configuration from: $ConfigPath"
    $config = Import-SftpConfig -Path $ConfigPath -Mode $Mode
    $validation = Test-SftpConfig -Config $config -Mode $Mode

    if (-not $validation.IsValid) {
        Write-Error "Configuration validation failed:"
        foreach ($err in $validation.Errors) {
            Write-Error "  - $err"
        }
        exit $EXIT_CONFIG_ERROR
    }

    # Initialize logging
    $logPath = Get-ConfigValue $config "log_path" -Default "logs"
    if (-not [System.IO.Path]::IsPathRooted($logPath)) {
        $logPath = Join-Path $scriptPath $logPath
    }

    Initialize-SftpLogging -LogPath $logPath `
                           -LogLevel (Get-ConfigValue $config "log_level" -Default "INFO") `
                           -RetentionDays (Get-ConfigValue $config "log_retention_days" -Default 30 -Type "int") `
                           -Enabled (Get-ConfigValue $config "log_enabled" -Default $true -Type "bool") `
                           -Mode $Mode

    Write-SftpLog "========================================" -Level INFO
    Write-SftpLog "Starting SFTP $Mode operation" -Level INFO
    Write-SftpLog "Configuration: $ConfigPath" -Level DEBUG

    # Initialize notifications if enabled
    if (Get-ConfigValue $config "notify_enabled" -Default $false -Type "bool") {
        $provider = Get-ConfigValue $config "notify_provider"
        Write-SftpLog "Initializing $provider notifications" -Level DEBUG

        $notifyParams = @{
            Provider = $provider
            NotifyOnSuccess = Get-ConfigValue $config "notify_on_success" -Default $false -Type "bool"
            NotifyOnFailure = Get-ConfigValue $config "notify_on_failure" -Default $true -Type "bool"
        }

        switch ($provider) {
            { $_ -in @("webhook", "msteams", "slack") } {
                $notifyParams.WebhookUrl = Get-ConfigValue $config "notify_webhook_url"
            }
            "graph" {
                $notifyParams.GraphTenantId = Get-ConfigValue $config "notify_graph_tenant_id"
                $notifyParams.GraphClientId = Get-ConfigValue $config "notify_graph_client_id"

                # Load client secret from file if path is specified
                $secretPath = Get-ConfigValue $config "notify_graph_client_secret_path"
                if ($secretPath -and (Test-Path $secretPath)) {
                    $notifyParams.GraphClientSecret = Get-Content $secretPath -Raw | ForEach-Object { $_.Trim() }
                }
                else {
                    $notifyParams.GraphClientSecret = Get-ConfigValue $config "notify_graph_client_secret"
                }

                $notifyParams.GraphFrom = Get-ConfigValue $config "notify_graph_from"
                $notifyParams.GraphTo = Get-ConfigValue $config "notify_graph_to" -Type "array"
                $notifyParams.SubjectPrefix = Get-ConfigValue $config "notify_graph_subject_prefix" -Default "[SFTP Transfer]"
            }
        }

        Initialize-SftpNotifications @notifyParams
    }

    # Health check mode
    if ($Mode -eq "healthcheck") {
        Write-SftpLog "Performing health check..." -Level INFO

        # Load WinSCP for health check
        Add-Type -Path $config.winscp_path

        $healthResult = Test-SftpConnection -Config $config

        if ($healthResult.IsConnected) {
            Write-SftpLog "Health check PASSED" -Level INFO
            Write-SftpLog $healthResult.ServerInfo -Level INFO

            if ($healthResult.Errors.Count -gt 0) {
                foreach ($err in $healthResult.Errors) {
                    Write-SftpLog "Warning: $err" -Level WARNING
                }
            }

            exit $EXIT_SUCCESS
        }
        else {
            Write-SftpLog "Health check FAILED" -Level ERROR
            foreach ($err in $healthResult.Errors) {
                Write-SftpLog "Error: $err" -Level ERROR
            }
            exit $EXIT_CONNECTION_ERROR
        }
    }

    # Load WinSCP
    Write-SftpLog "Loading WinSCP from: $($config.winscp_path)" -Level DEBUG
    Add-Type -Path $config.winscp_path

    $session = $null
    try {
        # Create session with retry
        $retryEnabled = Get-ConfigValue $config "retry_enabled" -Default $true -Type "bool"
        $retryAttempts = Get-ConfigValue $config "retry_attempts" -Default 3 -Type "int"
        $retryDelay = Get-ConfigValue $config "retry_delay_seconds" -Default 5 -Type "int"
        $retryBackoff = Get-ConfigValue $config "retry_exponential_backoff" -Default $true -Type "bool"

        Write-SftpLog "Connecting to $($config.sftp_hostname):$($config.sftp_port)..." -Level INFO

        if ($retryEnabled) {
            $session = Invoke-WithRetry -ScriptBlock {
                New-SftpSession -Config $config
            } -MaxAttempts $retryAttempts `
              -DelaySeconds $retryDelay `
              -ExponentialBackoff $retryBackoff `
              -OnRetry {
                Write-SftpLog "Connection failed, retrying..." -Level WARNING
              }
        }
        else {
            $session = New-SftpSession -Config $config
        }

        Write-SftpLog "Session opened successfully" -Level INFO

        # Execute transfer operation
        $importPath = Join-Path $scriptPath "import.ps1"
        $exportPath = Join-Path $scriptPath "export.ps1"

        $result = switch ($Mode) {
            "import" {
                Write-SftpLog "Starting import operation" -Level INFO
                & $importPath -Session $session -Config $config
            }
            "export" {
                Write-SftpLog "Starting export operation" -Level INFO
                & $exportPath -Session $session -Config $config
            }
        }

        # Determine exit code based on results
        if ($result -and $result.Success -and $result.Errors.Count -eq 0) {
            $exitCode = $EXIT_SUCCESS
        }
        elseif ($result -and $result.FilesTransferred -gt 0 -and $result.Errors.Count -gt 0) {
            $exitCode = $EXIT_PARTIAL_SUCCESS
        }
        elseif ($result -and $result.FilesTransferred -eq 0 -and $result.Errors.Count -eq 0) {
            # No files to transfer is still success
            $exitCode = $EXIT_SUCCESS
        }
        else {
            $exitCode = $EXIT_TRANSFER_ERROR
        }

    }
    catch {
        Write-SftpLog "Connection error: $($_.Exception.Message)" -Level ERROR
        $exitCode = $EXIT_CONNECTION_ERROR
        throw
    }
    finally {
        if ($session) {
            $session.Dispose()
            Write-SftpLog "Session closed" -Level DEBUG
        }
    }

    # Write summary
    Write-TransferSummary
    $summary = Get-TransferSummary

    # Send notification
    if ($exitCode -eq $EXIT_SUCCESS) {
        Send-SftpNotification -Type Success -Summary $summary
    }
    elseif ($exitCode -eq $EXIT_PARTIAL_SUCCESS) {
        Send-SftpNotification -Type Warning -Summary $summary `
            -AdditionalInfo "Some files failed to transfer. Check logs for details."
    }
    else {
        Send-SftpNotification -Type Failure -Summary $summary
    }

}
catch {
    Write-SftpLog "Fatal error: $($_.Exception.Message)" -Level ERROR
    Write-SftpLog $_.ScriptStackTrace -Level DEBUG

    try {
        $summary = Get-TransferSummary
        Send-SftpNotification -Type Failure `
            -Subject "Fatal Error in $Mode operation" `
            -Summary $summary `
            -AdditionalInfo $_.Exception.Message
    }
    catch {
        # Ignore notification errors
    }

    if ($exitCode -eq $EXIT_SUCCESS) {
        $exitCode = $EXIT_TRANSFER_ERROR
    }
}

Write-SftpLog "Exiting with code $exitCode" -Level INFO
exit $exitCode
