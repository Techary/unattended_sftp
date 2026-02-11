#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for SftpConfig module.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\modules\SftpConfig\SftpConfig.psd1"
    Import-Module $modulePath -Force
}

Describe "Import-SftpConfig" {
    BeforeAll {
        $testEnvPath = Join-Path $TestDrive "test.env"
    }

    Context "Valid .env file" {
        BeforeEach {
            @"
winscp_path = C:\WinSCP\WinSCPnet.dll
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = testuser
privkey_path = C:\keys\test.ppk
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx:xx
local_import_path = C:\import
remote_import_path = /remote/import
local_export_path = C:\export1,C:\export2
remote_export_path = /remote/export
log_enabled = true
log_level = DEBUG
retry_attempts = 5
"@ | Out-File $testEnvPath -Encoding utf8
        }

        It "Should load all configuration values" {
            $config = Import-SftpConfig -Path $testEnvPath -Mode "import"

            $config.sftp_hostname | Should -Be "sftp.example.com"
            $config.sftp_port | Should -Be 22
            $config.sftp_username | Should -Be "testuser"
        }

        It "Should handle comma-separated values as arrays" {
            $config = Import-SftpConfig -Path $testEnvPath -Mode "export"

            $config.local_export_path | Should -BeOfType [System.Object[]]
            $config.local_export_path.Count | Should -Be 2
            $config.local_export_path[0] | Should -Be "C:\export1"
        }

        It "Should convert boolean values" {
            $config = Import-SftpConfig -Path $testEnvPath -Mode "import"

            $config.log_enabled | Should -Be $true
            $config.log_enabled | Should -BeOfType [bool]
        }

        It "Should convert integer values" {
            $config = Import-SftpConfig -Path $testEnvPath -Mode "import"

            $config.retry_attempts | Should -Be 5
            $config.retry_attempts | Should -BeOfType [int]
        }
    }

    Context "Missing .env file" {
        It "Should throw FileNotFoundException" {
            { Import-SftpConfig -Path "C:\nonexistent\file.env" -Mode "import" } |
                Should -Throw "*not found*"
        }
    }

    Context "Comments and empty lines" {
        BeforeEach {
            @"
# This is a comment
winscp_path = C:\WinSCP\WinSCPnet.dll

# Another comment
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = testuser
privkey_path = C:\keys\test.ppk
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx
"@ | Out-File $testEnvPath -Encoding utf8
        }

        It "Should skip comments and empty lines" {
            $config = Import-SftpConfig -Path $testEnvPath -Mode "healthcheck"

            $config.sftp_hostname | Should -Be "sftp.example.com"
        }
    }
}

Describe "Test-SftpConfig" {
    BeforeAll {
        $testEnvPath = Join-Path $TestDrive "test.env"
    }

    Context "Import mode validation" {
        It "Should fail when remote_import_path is missing" {
            @"
winscp_path = C:\WinSCP\WinSCPnet.dll
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = testuser
privkey_path = C:\keys\test.ppk
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx
local_import_path = C:\import
"@ | Out-File $testEnvPath -Encoding utf8

            $config = Import-SftpConfig -Path $testEnvPath -Mode "import"
            $validation = Test-SftpConfig -Config $config -Mode "import"

            $validation.IsValid | Should -Be $false
            $validation.Errors | Should -Contain "remote_import_path is required for import mode"
        }
    }

    Context "Export mode validation" {
        It "Should fail when local_export_path is missing" {
            @"
winscp_path = C:\WinSCP\WinSCPnet.dll
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = testuser
privkey_path = C:\keys\test.ppk
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx
remote_export_path = /remote/export
"@ | Out-File $testEnvPath -Encoding utf8

            $config = Import-SftpConfig -Path $testEnvPath -Mode "export"
            $validation = Test-SftpConfig -Config $config -Mode "export"

            $validation.IsValid | Should -Be $false
            $validation.Errors | Should -Contain "local_export_path is required for export mode"
        }
    }
}

Describe "Get-ConfigValue" {
    BeforeAll {
        $testEnvPath = Join-Path $TestDrive "test.env"
        @"
winscp_path = C:\WinSCP\WinSCPnet.dll
sftp_hostname = sftp.example.com
sftp_port = 22
sftp_username = testuser
privkey_path = C:\keys\test.ppk
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx
log_enabled = true
retry_attempts = 3
email_to = user1@test.com,user2@test.com
"@ | Out-File $testEnvPath -Encoding utf8
        $script:testConfig = Import-SftpConfig -Path $testEnvPath -Mode "healthcheck"
    }

    It "Should return string value" {
        $value = Get-ConfigValue $script:testConfig "sftp_hostname"
        $value | Should -Be "sftp.example.com"
    }

    It "Should return default for missing value" {
        $value = Get-ConfigValue $script:testConfig "nonexistent_key" -Default "default_value"
        $value | Should -Be "default_value"
    }

    It "Should convert to int" {
        $value = Get-ConfigValue $script:testConfig "retry_attempts" -Type "int"
        $value | Should -Be 3
        $value | Should -BeOfType [int]
    }

    It "Should convert to bool" {
        $value = Get-ConfigValue $script:testConfig "log_enabled" -Type "bool"
        $value | Should -Be $true
    }

    It "Should convert to array" {
        $value = Get-ConfigValue $script:testConfig "email_to" -Type "array"
        $value | Should -BeOfType [System.Object[]]
        $value.Count | Should -Be 2
    }
}
