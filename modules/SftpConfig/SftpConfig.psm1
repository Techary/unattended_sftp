#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP Configuration module for loading and validating .env configuration.
.DESCRIPTION
    Provides functions to load, parse, and validate configuration from .env files
    with support for arrays, type conversion, and validation.
#>

function Import-SftpConfig {
    <#
    .SYNOPSIS
        Loads configuration from .env file and returns a configuration object.
    .PARAMETER Path
        Path to the .env file.
    .PARAMETER Mode
        Operation mode: 'import', 'export', or 'healthcheck'.
    .OUTPUTS
        PSCustomObject with configuration properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet("import", "export", "healthcheck")]
        [string]$Mode
    )

    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }

    $config = [PSCustomObject]@{
        # Connection settings
        winscp_path = $null
        sftp_hostname = $null
        sftp_port = 22
        sftp_username = $null
        SshHostKeyFingerprint = $null

        # Authentication
        privkey_path = $null
        passphrase_path = $null

        # Transfer paths
        local_export_path = @()
        remote_export_path = $null
        local_import_path = $null
        remote_import_path = @()

        # Logging
        log_enabled = $true
        log_path = "logs"
        log_retention_days = 30
        log_level = "INFO"

        # Retry
        retry_enabled = $true
        retry_attempts = 3
        retry_delay_seconds = 5
        retry_exponential_backoff = $true

        # File filtering
        include_pattern = @("*")
        exclude_pattern = @()

        # Notifications
        notify_enabled = $false
        notify_provider = $null  # webhook, msteams, slack, graph
        notify_on_success = $false
        notify_on_failure = $true

        # Webhook settings (for webhook, msteams, slack providers)
        notify_webhook_url = $null

        # Microsoft Graph settings (for graph provider)
        notify_graph_tenant_id = $null
        notify_graph_client_id = $null
        notify_graph_client_secret = $null
        notify_graph_client_secret_path = $null
        notify_graph_from = $null
        notify_graph_to = @()
        notify_graph_subject_prefix = "[SFTP Transfer]"

        # Backup
        backup_enabled = $false
        backup_path = "backups"
        backup_retention_days = 7

        # Progress
        progress_enabled = $true
        progress_interval_seconds = 10

        # Connection
        connection_timeout_seconds = 30
    }

    $envContent = Get-Content $Path -ErrorAction Stop

    foreach ($line in $envContent) {
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        $parts = $line.Split('=', 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")

        # Skip if value is empty (except for optional fields)
        $optionalFields = @('passphrase_path',
                           'local_export_path', 'remote_export_path', 'local_import_path', 'remote_import_path',
                           'include_pattern', 'exclude_pattern',
                           'notify_webhook_url', 'notify_graph_tenant_id', 'notify_graph_client_id',
                           'notify_graph_client_secret', 'notify_graph_client_secret_path',
                           'notify_graph_from', 'notify_graph_to', 'notify_provider')

        if ([string]::IsNullOrWhiteSpace($value) -and $name -notin $optionalFields) {
            continue
        }

        # Check if property exists on config object
        if ($config.PSObject.Properties.Name -contains $name) {
            $currentValue = $config.$name

            # Handle type conversion based on default value type
            if ($currentValue -is [bool]) {
                $config.$name = $value -eq 'true' -or $value -eq '1' -or $value -eq 'yes'
            }
            elseif ($currentValue -is [int]) {
                $config.$name = [int]$value
            }
            elseif ($currentValue -is [array]) {
                if ($value -match ',') {
                    $config.$name = $value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                }
                elseif (-not [string]::IsNullOrWhiteSpace($value)) {
                    $config.$name = @($value)
                }
            }
            else {
                $config.$name = $value
            }
        }
    }

    return $config
}

function Test-SftpConfig {
    <#
    .SYNOPSIS
        Validates configuration completeness and path existence.
    .PARAMETER Config
        Configuration object from Import-SftpConfig.
    .PARAMETER Mode
        Operation mode to validate.
    .OUTPUTS
        PSCustomObject with IsValid boolean and Errors array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [ValidateSet("import", "export", "healthcheck")]
        [string]$Mode
    )

    $errors = @()

    # Required for all modes
    if ([string]::IsNullOrWhiteSpace($Config.winscp_path)) {
        $errors += "winscp_path is required"
    }
    elseif (-not (Test-Path $Config.winscp_path)) {
        $errors += "WinSCP DLL not found: $($Config.winscp_path)"
    }

    if ([string]::IsNullOrWhiteSpace($Config.sftp_hostname)) {
        $errors += "sftp_hostname is required"
    }

    if ([string]::IsNullOrWhiteSpace($Config.sftp_username)) {
        $errors += "sftp_username is required"
    }

    if ([string]::IsNullOrWhiteSpace($Config.privkey_path)) {
        $errors += "privkey_path is required"
    }
    elseif (-not (Test-Path $Config.privkey_path)) {
        $errors += "Private key not found: $($Config.privkey_path)"
    }

    if ([string]::IsNullOrWhiteSpace($Config.SshHostKeyFingerprint)) {
        $errors += "SshHostKeyFingerprint is required"
    }

    # Mode-specific validation
    switch ($Mode) {
        "import" {
            if ($Config.remote_import_path.Count -eq 0) {
                $errors += "remote_import_path is required for import mode"
            }
            if ([string]::IsNullOrWhiteSpace($Config.local_import_path)) {
                $errors += "local_import_path is required for import mode"
            }
            elseif (-not (Test-Path $Config.local_import_path -PathType Container)) {
                $errors += "Local import directory not found: $($Config.local_import_path)"
            }
        }
        "export" {
            if ($Config.local_export_path.Count -eq 0) {
                $errors += "local_export_path is required for export mode"
            }
            else {
                foreach ($path in $Config.local_export_path) {
                    if (-not (Test-Path $path -PathType Container)) {
                        $errors += "Local export directory not found: $path"
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($Config.remote_export_path)) {
                $errors += "remote_export_path is required for export mode"
            }
        }
    }

    # Validate notification settings if enabled
    if ($Config.notify_enabled) {
        if ([string]::IsNullOrWhiteSpace($Config.notify_provider)) {
            $errors += "notify_provider is required when notifications are enabled (webhook, msteams, slack, or graph)"
        }
        else {
            switch ($Config.notify_provider) {
                { $_ -in @("webhook", "msteams", "slack") } {
                    if ([string]::IsNullOrWhiteSpace($Config.notify_webhook_url)) {
                        $errors += "notify_webhook_url is required for $($Config.notify_provider) provider"
                    }
                }
                "graph" {
                    if ([string]::IsNullOrWhiteSpace($Config.notify_graph_tenant_id)) {
                        $errors += "notify_graph_tenant_id is required for graph provider"
                    }
                    if ([string]::IsNullOrWhiteSpace($Config.notify_graph_client_id)) {
                        $errors += "notify_graph_client_id is required for graph provider"
                    }
                    if ([string]::IsNullOrWhiteSpace($Config.notify_graph_client_secret) -and
                        [string]::IsNullOrWhiteSpace($Config.notify_graph_client_secret_path)) {
                        $errors += "notify_graph_client_secret or notify_graph_client_secret_path is required for graph provider"
                    }
                    if ([string]::IsNullOrWhiteSpace($Config.notify_graph_from)) {
                        $errors += "notify_graph_from is required for graph provider"
                    }
                    if ($Config.notify_graph_to.Count -eq 0) {
                        $errors += "notify_graph_to is required for graph provider"
                    }
                }
            }
        }
    }

    return [PSCustomObject]@{
        IsValid = $errors.Count -eq 0
        Errors = $errors
    }
}

function Get-ConfigValue {
    <#
    .SYNOPSIS
        Retrieves a configuration value with type conversion and default support.
    .PARAMETER Config
        Configuration object.
    .PARAMETER Key
        Configuration key name.
    .PARAMETER Default
        Default value if not found.
    .PARAMETER Type
        Type to convert to: string, int, bool, array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        [object]$Default = $null,

        [Parameter()]
        [ValidateSet("string", "int", "bool", "array")]
        [string]$Type = "string"
    )

    $value = $Config.$Key

    if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
        $value = $Default
    }

    if ($null -eq $value) {
        return $null
    }

    switch ($Type) {
        "int" { return [int]$value }
        "bool" {
            if ($value -is [bool]) { return $value }
            return $value -eq 'true' -or $value -eq '1' -or $value -eq 'yes'
        }
        "array" {
            if ($value -is [array]) { return $value }
            if ($value -match ',') { return $value -split ',' | ForEach-Object { $_.Trim() } }
            return @($value)
        }
        default { return [string]$value }
    }
}

Export-ModuleMember -Function Import-SftpConfig, Test-SftpConfig, Get-ConfigValue
