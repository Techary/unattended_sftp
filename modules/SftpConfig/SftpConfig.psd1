@{
    RootModule = 'SftpConfig.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'SFTP Automation'
    Description = 'Configuration loading and validation for SFTP transfers'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Import-SftpConfig', 'Test-SftpConfig', 'Get-ConfigValue')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
