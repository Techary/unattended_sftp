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
    It "Should remove folders older than retention period" {
        $backupDir = Join-Path $TestDrive "backups_old_$(Get-Random)"
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

        # Create a folder dated 10 days ago
        $oldDate = (Get-Date).AddDays(-10).ToString("yyyy-MM-dd")
        $oldFolder = Join-Path $backupDir $oldDate
        New-Item -Path $oldFolder -ItemType Directory -Force | Out-Null
        "content" | Out-File (Join-Path $oldFolder "file.txt")

        # Verify folder exists before cleanup
        Test-Path $oldFolder | Should -Be $true

        # Run cleanup with 7 day retention (folder is 10 days old, should be removed)
        Clear-OldBackups -BackupPath $backupDir -RetentionDays 7

        # Folder should be gone
        Test-Path $oldFolder | Should -Be $false
    }

    It "Should keep folders within retention period" {
        $backupDir = Join-Path $TestDrive "backups_recent_$(Get-Random)"
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

        # Create a folder dated 3 days ago
        $recentDate = (Get-Date).AddDays(-3).ToString("yyyy-MM-dd")
        $recentFolder = Join-Path $backupDir $recentDate
        New-Item -Path $recentFolder -ItemType Directory -Force | Out-Null
        "content" | Out-File (Join-Path $recentFolder "file.txt")

        # Verify folder exists before cleanup
        Test-Path $recentFolder | Should -Be $true

        # Run cleanup with 7 day retention (folder is 3 days old, should be kept)
        Clear-OldBackups -BackupPath $backupDir -RetentionDays 7

        # Folder should still exist
        Test-Path $recentFolder | Should -Be $true
    }
}

Describe "Get-RemotePathSeparator" {
    Context "Unix-style paths" {
        It "Should detect forward slash for absolute Unix path" {
            $separator = Get-RemotePathSeparator -Path "/remote/path/to/files"
            $separator | Should -Be "/"
        }

        It "Should detect forward slash for relative Unix path" {
            $separator = Get-RemotePathSeparator -Path "path/to/files"
            $separator | Should -Be "/"
        }

        It "Should default to forward slash for ambiguous paths" {
            $separator = Get-RemotePathSeparator -Path "filename.txt"
            $separator | Should -Be "/"
        }
    }

    Context "Windows-style paths" {
        It "Should detect backslash for drive letter path" {
            $separator = Get-RemotePathSeparator -Path "C:\remote\path"
            $separator | Should -Be "\"
        }

        It "Should detect backslash for UNC path" {
            $separator = Get-RemotePathSeparator -Path "\\server\share\folder"
            $separator | Should -Be "\"
        }

        It "Should detect backslash for relative Windows path" {
            $separator = Get-RemotePathSeparator -Path "folder\subfolder\file.txt"
            $separator | Should -Be "\"
        }
    }

    Context "Force separator" {
        It "Should use forced forward slash" {
            $separator = Get-RemotePathSeparator -Path "C:\windows\path" -ForceSeparator "/"
            $separator | Should -Be "/"
        }

        It "Should use forced backslash" {
            $separator = Get-RemotePathSeparator -Path "/unix/path" -ForceSeparator "\"
            $separator | Should -Be "\"
        }
    }
}

Describe "Join-RemotePath" {
    Context "Unix-style paths" {
        It "Should join Unix paths with forward slash" {
            $result = Join-RemotePath -BasePath "/remote/dir" -ChildPath "file.txt"
            $result | Should -Be "/remote/dir/file.txt"
        }

        It "Should handle trailing slash in base path" {
            $result = Join-RemotePath -BasePath "/remote/dir/" -ChildPath "file.txt"
            $result | Should -Be "/remote/dir/file.txt"
        }

        It "Should handle leading slash in child path" {
            $result = Join-RemotePath -BasePath "/remote/dir" -ChildPath "/file.txt"
            $result | Should -Be "/remote/dir/file.txt"
        }
    }

    Context "Windows-style paths" {
        It "Should join Windows paths with backslash" {
            $result = Join-RemotePath -BasePath "C:\remote\dir" -ChildPath "file.txt"
            $result | Should -Be "C:\remote\dir\file.txt"
        }

        It "Should handle trailing backslash in base path" {
            $result = Join-RemotePath -BasePath "C:\remote\dir\" -ChildPath "file.txt"
            $result | Should -Be "C:\remote\dir\file.txt"
        }

        It "Should handle UNC paths" {
            $result = Join-RemotePath -BasePath "\\server\share" -ChildPath "file.txt"
            $result | Should -Be "\\server\share\file.txt"
        }
    }

    Context "Force separator" {
        It "Should use forced separator regardless of path format" {
            $result = Join-RemotePath -BasePath "/unix/path" -ChildPath "file.txt" -Separator "\"
            $result | Should -Be "/unix/path\file.txt"
        }
    }
}
