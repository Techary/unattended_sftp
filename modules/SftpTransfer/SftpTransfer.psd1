@{
    RootModule = 'SftpTransfer.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'e5f6a7b8-c9d0-1234-ef01-567890123456'
    Author = 'SFTP Automation'
    Description = 'Core transfer operations module for SFTP'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-SftpSession',
        'Test-SftpConnection',
        'Get-FilteredFiles',
        'Backup-LocalFile',
        'Clear-OldBackups'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
