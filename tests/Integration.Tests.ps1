#Requires -Module Pester
<#
.SYNOPSIS
    Integration tests for SFTP transfer system.
.DESCRIPTION
    These tests verify the integration between modules.
    Tests marked with -Skip require a real SFTP server.
#>

BeforeAll {
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $modulesPath = Join-Path $projectRoot "modules"

    Import-Module (Join-Path $modulesPath "SftpConfig\SftpConfig.psd1") -Force
    Import-Module (Join-Path $modulesPath "SftpLogger\SftpLogger.psd1") -Force
    Import-Module (Join-Path $modulesPath "SftpRetry\SftpRetry.psd1") -Force
    Import-Module (Join-Path $modulesPath "SftpTransfer\SftpTransfer.psd1") -Force
}

Describe "Configuration and Logging Integration" {
    BeforeAll {
        $testEnvPath = Join-Path $TestDrive "test.env"
        @"
winscp_path = C:\WinSCP\WinSCPnet.dll
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = testuser
privkey_path = C:\keys\test.ppk
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx:xx
local_import_path = C:\import
remote_import_path = /remote/import
log_enabled = true
log_path = logs
log_level = DEBUG
"@ | Out-File $testEnvPath -Encoding utf8
    }

    It "Should load config and initialize logging" {
        $testLogPath = Join-Path $TestDrive "intlogs"

        $config = Import-SftpConfig -Path $testEnvPath -Mode "import"

        Initialize-SftpLogging -LogPath $testLogPath `
                               -LogLevel (Get-ConfigValue $config "log_level" -Default "INFO") `
                               -Enabled (Get-ConfigValue $config "log_enabled" -Default $true -Type "bool") `
                               -Mode "import"

        Write-SftpLog "Integration test message" -Level INFO -NoConsole

        $logFiles = Get-ChildItem $testLogPath -Filter "*.log"
        $logFiles.Count | Should -BeGreaterThan 0
    }
}

Describe "Retry and Transfer Integration" {
    It "Should retry operations with logging" {
        $testLogPath = Join-Path $TestDrive "retrylogs_$(Get-Random)"
        Initialize-SftpLogging -LogPath $testLogPath -LogLevel "DEBUG" -Mode "test"

        $script:attempts = 0

        $result = Invoke-WithRetry -ScriptBlock {
            $script:attempts++
            if ($script:attempts -lt 2) {
                throw [System.IO.IOException]::new("Simulated failure")
            }
            return "success"
        } -MaxAttempts 3 -DelaySeconds 0 -OnRetry {
            Write-SftpLog "Retry attempt" -Level WARNING -NoConsole
        }

        $result | Should -Be "success"

        $logFiles = Get-ChildItem $testLogPath -Filter "*.log"
        $logContent = Get-Content $logFiles[0].FullName -Raw
        $logContent | Should -Match "Retry attempt"
    }
}

Describe "End-to-End Workflow" {
    BeforeAll {
        $testRoot = Join-Path $TestDrive "e2e"
        $localExport = Join-Path $testRoot "export"
        $localImport = Join-Path $testRoot "import"
        $backupDir = Join-Path $testRoot "backups"
        $logDir = Join-Path $testRoot "logs"

        New-Item -Path $localExport -ItemType Directory -Force | Out-Null
        New-Item -Path $localImport -ItemType Directory -Force | Out-Null

        # Create test files
        "content1" | Out-File (Join-Path $localExport "file1.txt")
        "content2" | Out-File (Join-Path $localExport "file2.txt")
        "temp" | Out-File (Join-Path $localExport "temp.tmp")

        $testEnvPath = Join-Path $testRoot "test.env"
        @"
winscp_path = C:\WinSCP\WinSCPnet.dll
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = testuser
privkey_path = C:\keys\test.ppk
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx:xx
local_export_path = $localExport
remote_export_path = /remote/export
local_import_path = $localImport
remote_import_path = /remote/import
log_enabled = true
log_path = $logDir
log_level = DEBUG
include_pattern = *.txt
exclude_pattern = *.tmp
backup_enabled = true
backup_path = $backupDir
backup_retention_days = 7
"@ | Out-File $testEnvPath -Encoding utf8
    }

    It "Should load config with all settings" {
        $config = Import-SftpConfig -Path $testEnvPath -Mode "export"

        $config.sftp_hostname | Should -Be "sftp.example.com"
        $config.include_pattern | Should -Contain "*.txt"
        $config.exclude_pattern | Should -Contain "*.tmp"
        $config.backup_enabled | Should -Be $true
    }

    It "Should filter files correctly" {
        $config = Import-SftpConfig -Path $testEnvPath -Mode "export"

        $files = Get-FilteredFiles -Path $localExport `
                                   -IncludePattern (Get-ConfigValue $config "include_pattern" -Type "array") `
                                   -ExcludePattern (Get-ConfigValue $config "exclude_pattern" -Type "array")

        $files.Count | Should -Be 2
        $files.Name | Should -Contain "file1.txt"
        $files.Name | Should -Contain "file2.txt"
        $files.Name | Should -Not -Contain "temp.tmp"
    }

    It "Should track transfer results in summary" {
        $config = Import-SftpConfig -Path $testEnvPath -Mode "export"
        Initialize-SftpLogging -LogPath $logDir -LogLevel "DEBUG" -Mode "export"

        Add-TransferResult -FileName "file1.txt" -Success $true -Bytes 1000
        Add-TransferResult -FileName "file2.txt" -Success $true -Bytes 2000

        $summary = Get-TransferSummary

        $summary.FilesSucceeded | Should -Be 2
        $summary.BytesTransferred | Should -Be 3000
        $summary.Success | Should -Be $true
    }
}

Describe "Live SFTP Tests" -Tag "Integration", "RequiresSFTP" {
    # These tests are skipped by default - run with:
    # Invoke-Pester -Tag "RequiresSFTP" when you have a test SFTP server

    It "Should connect to SFTP server" -Skip {
        # Requires actual SFTP server configuration
        $config = Import-SftpConfig -Path ".env" -Mode "healthcheck"
        $result = Test-SftpConnection -Config $config

        $result.IsConnected | Should -Be $true
    }
}
