@{
    RootModule = 'SftpRetry.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c3d4e5f6-a7b8-9012-cdef-345678901234'
    Author = 'SFTP Automation'
    Description = 'Retry logic module with exponential backoff for SFTP transfers'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-WithRetry', 'Test-RetryableException', 'Get-RetryDelay')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
