@{
    RootModule = 'SftpNotification.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'd4e5f6a7-b8c9-0123-def0-456789012345'
    Author = 'SFTP Automation'
    Description = 'Notification module for SFTP transfers via webhooks (Teams, Slack) or Microsoft Graph API'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Initialize-SftpNotifications', 'Send-SftpNotification')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
