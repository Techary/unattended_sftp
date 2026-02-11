#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for SftpTransfer module.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\modules\SftpTransfer\SftpTransfer.psd1"
    Import-Module $modulePath -Force
}

Describe "Get-FilteredFiles" {
    BeforeAll {
        # Create test files
        $testDir = Join-Path $TestDrive "files"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null

        "content" | Out-File (Join-Path $testDir "file1.txt")
        "content" | Out-File (Join-Path $testDir "file2.txt")
        "content" | Out-File (Join-Path $testDir "data.csv")
        "content" | Out-File (Join-Path $testDir "image.png")
        "content" | Out-File (Join-Path $testDir "temp.tmp")
        "content" | Out-File (Join-Path $testDir "debug.log")
    }

    Context "Include patterns" {
        It "Should include all files with wildcard" {
            $files = Get-FilteredFiles -Path $testDir -IncludePattern "*"

            $files.Count | Should -Be 6
        }

        It "Should include only .txt files" {
            $files = Get-FilteredFiles -Path $testDir -IncludePattern "*.txt"

            $files.Count | Should -Be 2
            $files.Name | Should -Contain "file1.txt"
            $files.Name | Should -Contain "file2.txt"
        }

        It "Should include multiple patterns" {
            $files = Get-FilteredFiles -Path $testDir -IncludePattern @("*.txt", "*.csv")

            $files.Count | Should -Be 3
        }
    }

    Context "Exclude patterns" {
        It "Should exclude .tmp files" {
            $files = Get-FilteredFiles -Path $testDir -IncludePattern "*" -ExcludePattern "*.tmp"

            $files.Count | Should -Be 5
            $files.Name | Should -Not -Contain "temp.tmp"
        }

        It "Should exclude multiple patterns" {
            $files = Get-FilteredFiles -Path $testDir -IncludePattern "*" -ExcludePattern @("*.tmp", "*.log")

            $files.Count | Should -Be 4
            $files.Name | Should -Not -Contain "temp.tmp"
            $files.Name | Should -Not -Contain "debug.log"
        }
    }

    Context "Combined include and exclude" {
        It "Should apply both patterns correctly" {
            $files = Get-FilteredFiles -Path $testDir -IncludePattern "*.txt" -ExcludePattern "file1*"

            $files.Count | Should -Be 1
            $files.Name | Should -Contain "file2.txt"
        }
    }
}

Describe "Backup-LocalFile" {
    BeforeAll {
        $testFile = Join-Path $TestDrive "source\testfile.txt"
        $backupDir = Join-Path $TestDrive "backups"

        New-Item -Path (Split-Path $testFile) -ItemType Directory -Force | Out-Null
        "test content" | Out-File $testFile
    }

    It "Should create backup directory if not exists" {
        $newBackupDir = Join-Path $TestDrive "newbackups_$(Get-Random)"

        Backup-LocalFile -FilePath $testFile -BackupPath $newBackupDir

        Test-Path $newBackupDir | Should -Be $true
    }

    It "Should create dated subfolder" {
        $backupDir = Join-Path $TestDrive "backups_$(Get-Random)"

        Backup-LocalFile -FilePath $testFile -BackupPath $backupDir

        $dateFolder = Join-Path $backupDir (Get-Date -Format "yyyy-MM-dd")
        Test-Path $dateFolder | Should -Be $true
    }

    It "Should copy file to backup location" {
        $backupDir = Join-Path $TestDrive "backups_$(Get-Random)"

        Backup-LocalFile -FilePath $testFile -BackupPath $backupDir

        $dateFolder = Join-Path $backupDir (Get-Date -Format "yyyy-MM-dd")
        $backupFiles = Get-ChildItem $dateFolder -Filter "*testfile.txt"
        $backupFiles.Count | Should -Be 1
    }
}

Describe "Clear-OldBackups" {
    BeforeAll {
        $backupDir = Join-Path $TestDrive "backups_cleanup"
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

        # Create old dated folders
        $oldDate = (Get-Date).AddDays(-10).ToString("yyyy-MM-dd")
        $recentDate = (Get-Date).AddDays(-3).ToString("yyyy-MM-dd")

        $oldFolder = Join-Path $backupDir $oldDate
        $recentFolder = Join-Path $backupDir $recentDate

        New-Item -Path $oldFolder -ItemType Directory -Force | Out-Null
        New-Item -Path $recentFolder -ItemType Directory -Force | Out-Null

        "old" | Out-File (Join-Path $oldFolder "old.txt")
        "recent" | Out-File (Join-Path $recentFolder "recent.txt")
    }

    It "Should remove folders older than retention period" {
        Clear-OldBackups -BackupPath $backupDir -RetentionDays 7

        $oldDate = (Get-Date).AddDays(-10).ToString("yyyy-MM-dd")
        $oldFolder = Join-Path $backupDir $oldDate

        Test-Path $oldFolder | Should -Be $false
    }

    It "Should keep folders within retention period" {
        Clear-OldBackups -BackupPath $backupDir -RetentionDays 7

        $recentDate = (Get-Date).AddDays(-3).ToString("yyyy-MM-dd")
        $recentFolder = Join-Path $backupDir $recentDate

        Test-Path $recentFolder | Should -Be $true
    }
}
