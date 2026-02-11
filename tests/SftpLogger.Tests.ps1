#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for SftpLogger module.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\modules\SftpLogger\SftpLogger.psd1"
    Import-Module $modulePath -Force
}

Describe "Initialize-SftpLogging" {
    It "Should create log directory if it does not exist" {
        $testLogPath = Join-Path $TestDrive "newlogs"

        Initialize-SftpLogging -LogPath $testLogPath -LogLevel "INFO"

        Test-Path $testLogPath | Should -Be $true
    }

    It "Should create log file with correct naming" {
        $testLogPath = Join-Path $TestDrive "logs"

        Initialize-SftpLogging -LogPath $testLogPath -LogLevel "INFO" -Mode "export"

        # Write a log entry to create the file
        Write-SftpLog "Test message" -Level INFO

        $dateStr = Get-Date -Format "yyyyMMdd"
        $expectedFile = Join-Path $testLogPath "sftp_export_$dateStr.log"
        Test-Path $expectedFile | Should -Be $true
    }
}

Describe "Write-SftpLog" {
    BeforeEach {
        $testLogPath = Join-Path $TestDrive "logs_$(Get-Random)"
        Initialize-SftpLogging -LogPath $testLogPath -LogLevel "DEBUG"
    }

    It "Should write log entry with timestamp" {
        Write-SftpLog "Test message" -Level INFO -NoConsole

        $logFiles = Get-ChildItem $testLogPath -Filter "*.log"
        $logContent = Get-Content $logFiles[0].FullName -Raw

        $logContent | Should -Match "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}"
    }

    It "Should include log level in entry" {
        Write-SftpLog "Warning message" -Level WARNING -NoConsole

        $logFiles = Get-ChildItem $testLogPath -Filter "*.log"
        $logContent = Get-Content $logFiles[0].FullName -Raw

        $logContent | Should -Match "\[WARN \]"
    }

    It "Should respect log level filtering" {
        Initialize-SftpLogging -LogPath $testLogPath -LogLevel "ERROR"

        Write-SftpLog "Debug message" -Level DEBUG -NoConsole
        Write-SftpLog "Error message" -Level ERROR -NoConsole

        $logFiles = Get-ChildItem $testLogPath -Filter "*.log"
        $logContent = Get-Content $logFiles[0].FullName -Raw

        $logContent | Should -Not -Match "Debug message"
        $logContent | Should -Match "Error message"
    }
}

Describe "Add-TransferResult and Get-TransferSummary" {
    BeforeEach {
        $testLogPath = Join-Path $TestDrive "logs_$(Get-Random)"
        Initialize-SftpLogging -LogPath $testLogPath -LogLevel "INFO" -Mode "test"
    }

    It "Should track successful transfers" {
        Add-TransferResult -FileName "file1.txt" -Success $true -Bytes 1000
        Add-TransferResult -FileName "file2.txt" -Success $true -Bytes 2000

        $summary = Get-TransferSummary

        $summary.FilesSucceeded | Should -Be 2
        $summary.FilesFailed | Should -Be 0
        $summary.BytesTransferred | Should -Be 3000
    }

    It "Should track failed transfers" {
        Add-TransferResult -FileName "file1.txt" -Success $false -ErrorMessage "Connection lost"

        $summary = Get-TransferSummary

        $summary.FilesSucceeded | Should -Be 0
        $summary.FilesFailed | Should -Be 1
        $summary.Errors.Count | Should -Be 1
    }

    It "Should track mixed results" {
        Add-TransferResult -FileName "file1.txt" -Success $true -Bytes 1000
        Add-TransferResult -FileName "file2.txt" -Success $false -ErrorMessage "Error"
        Add-TransferResult -FileName "file3.txt" -Success $true -Bytes 500

        $summary = Get-TransferSummary

        $summary.FilesProcessed | Should -Be 3
        $summary.FilesSucceeded | Should -Be 2
        $summary.FilesFailed | Should -Be 1
        $summary.Success | Should -Be $false
    }
}

Describe "Format-Bytes" {
    It "Should format bytes correctly" {
        Format-Bytes -Bytes 500 | Should -Be "500 bytes"
    }

    It "Should format kilobytes correctly" {
        Format-Bytes -Bytes 2048 | Should -Match "2.*KB"
    }

    It "Should format megabytes correctly" {
        Format-Bytes -Bytes (5 * 1MB) | Should -Match "5.*MB"
    }

    It "Should format gigabytes correctly" {
        Format-Bytes -Bytes (2 * 1GB) | Should -Match "2.*GB"
    }
}
