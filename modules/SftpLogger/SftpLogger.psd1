@{
    RootModule = 'SftpLogger.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b2c3d4e5-f6a7-8901-bcde-f23456789012'
    Author = 'SFTP Automation'
    Description = 'Logging module for SFTP transfers with timestamps and levels'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-SftpLogging',
        'Write-SftpLog',
        'Write-SftpProgress',
        'Add-TransferResult',
        'Get-TransferSummary',
        'Write-TransferSummary',
        'Clear-OldLogs',
        'Format-Bytes'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
