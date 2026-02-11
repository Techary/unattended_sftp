#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP Notification module for alerts via webhooks or Microsoft Graph API.
.DESCRIPTION
    Provides functions for sending notifications about transfer results
    using webhooks (Teams, Slack, generic) or Microsoft Graph API with OAuth 2.0.
#>

# Module-level configuration
$script:NotificationConfig = @{
    Enabled = $false
    Provider = $null  # webhook, msteams, slack, graph
    NotifyOnSuccess = $false
    NotifyOnFailure = $true

    # Webhook settings
    WebhookUrl = $null

    # Microsoft Graph settings
    GraphTenantId = $null
    GraphClientId = $null
    GraphClientSecret = $null
    GraphFrom = $null
    GraphTo = @()
    GraphSubjectPrefix = "[SFTP Transfer]"
}

function Initialize-SftpNotifications {
    <#
    .SYNOPSIS
        Configures the notification system.
    .PARAMETER Provider
        Notification provider: webhook, msteams, slack, or graph.
    .PARAMETER WebhookUrl
        Webhook URL for Teams, Slack, or generic webhook.
    .PARAMETER GraphTenantId
        Azure AD tenant ID for Microsoft Graph.
    .PARAMETER GraphClientId
        Azure AD application (client) ID.
    .PARAMETER GraphClientSecret
        Azure AD client secret.
    .PARAMETER GraphFrom
        Sender email address (must be valid in tenant).
    .PARAMETER GraphTo
        Array of recipient email addresses.
    .PARAMETER SubjectPrefix
        Prefix for email subjects (Graph only).
    .PARAMETER NotifyOnSuccess
        Send notification on successful transfers.
    .PARAMETER NotifyOnFailure
        Send notification on failed transfers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("webhook", "msteams", "slack", "graph")]
        [string]$Provider,

        [Parameter()]
        [string]$WebhookUrl = $null,

        [Parameter()]
        [string]$GraphTenantId = $null,

        [Parameter()]
        [string]$GraphClientId = $null,

        [Parameter()]
        [string]$GraphClientSecret = $null,

        [Parameter()]
        [string]$GraphFrom = $null,

        [Parameter()]
        [string[]]$GraphTo = @(),

        [Parameter()]
        [string]$SubjectPrefix = "[SFTP Transfer]",

        [Parameter()]
        [bool]$NotifyOnSuccess = $false,

        [Parameter()]
        [bool]$NotifyOnFailure = $true
    )

    $script:NotificationConfig = @{
        Enabled = $true
        Provider = $Provider
        NotifyOnSuccess = $NotifyOnSuccess
        NotifyOnFailure = $NotifyOnFailure
        WebhookUrl = $WebhookUrl
        GraphTenantId = $GraphTenantId
        GraphClientId = $GraphClientId
        GraphClientSecret = $GraphClientSecret
        GraphFrom = $GraphFrom
        GraphTo = $GraphTo
        GraphSubjectPrefix = $SubjectPrefix
    }
}

function Send-SftpNotification {
    <#
    .SYNOPSIS
        Sends a notification about transfer results.
    .PARAMETER Type
        Notification type: Success, Failure, Warning.
    .PARAMETER Subject
        Notification subject/title.
    .PARAMETER Summary
        Transfer summary object from Get-TransferSummary.
    .PARAMETER AdditionalInfo
        Additional text to include.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Success", "Failure", "Warning")]
        [string]$Type,

        [Parameter()]
        [string]$Subject = $null,

        [Parameter()]
        [PSCustomObject]$Summary = $null,

        [Parameter()]
        [string]$AdditionalInfo = $null
    )

    if (-not $script:NotificationConfig.Enabled) {
        return
    }

    # Check if we should send for this type
    if ($Type -eq "Success" -and -not $script:NotificationConfig.NotifyOnSuccess) {
        return
    }
    if (($Type -eq "Failure" -or $Type -eq "Warning") -and -not $script:NotificationConfig.NotifyOnFailure) {
        return
    }

    # Build subject
    if (-not $Subject) {
        $Subject = switch ($Type) {
            "Success" { "Transfer Completed Successfully" }
            "Warning" { "Transfer Completed with Warnings" }
            "Failure" { "Transfer Failed" }
        }
    }

    try {
        switch ($script:NotificationConfig.Provider) {
            "webhook" {
                Send-WebhookNotification -Type $Type -Subject $Subject -Summary $Summary -AdditionalInfo $AdditionalInfo
            }
            "msteams" {
                Send-TeamsNotification -Type $Type -Subject $Subject -Summary $Summary -AdditionalInfo $AdditionalInfo
            }
            "slack" {
                Send-SlackNotification -Type $Type -Subject $Subject -Summary $Summary -AdditionalInfo $AdditionalInfo
            }
            "graph" {
                Send-GraphNotification -Type $Type -Subject $Subject -Summary $Summary -AdditionalInfo $AdditionalInfo
            }
        }
    }
    catch {
        Write-Warning "Failed to send notification: $($_.Exception.Message)"
    }
}

function Send-WebhookNotification {
    <#
    .SYNOPSIS
        Sends a generic webhook notification.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,
        [string]$Subject,
        [PSCustomObject]$Summary,
        [string]$AdditionalInfo
    )

    $body = @{
        type = $Type
        subject = $Subject
        timestamp = (Get-Date).ToString("o")
        summary = if ($Summary) {
            @{
                mode = $Summary.Mode
                filesProcessed = $Summary.FilesProcessed
                filesSucceeded = $Summary.FilesSucceeded
                filesFailed = $Summary.FilesFailed
                bytesTransferred = $Summary.BytesTransferred
                duration = $Summary.DurationFormatted
                errors = @($Summary.Errors)
            }
        } else { $null }
        additionalInfo = $AdditionalInfo
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $script:NotificationConfig.WebhookUrl `
                      -Method Post `
                      -ContentType "application/json" `
                      -Body $body `
                      -ErrorAction Stop
}

function Send-TeamsNotification {
    <#
    .SYNOPSIS
        Sends a Microsoft Teams notification via webhook.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,
        [string]$Subject,
        [PSCustomObject]$Summary,
        [string]$AdditionalInfo
    )

    $themeColor = switch ($Type) {
        "Success" { "28a745" }
        "Warning" { "ffc107" }
        "Failure" { "dc3545" }
    }

    $facts = @()
    if ($Summary) {
        $facts += @{ name = "Mode"; value = $Summary.Mode }
        $facts += @{ name = "Duration"; value = $Summary.DurationFormatted }
        $facts += @{ name = "Files Processed"; value = $Summary.FilesProcessed.ToString() }
        $facts += @{ name = "Files Succeeded"; value = $Summary.FilesSucceeded.ToString() }
        $facts += @{ name = "Files Failed"; value = $Summary.FilesFailed.ToString() }
        $facts += @{ name = "Data Transferred"; value = $Summary.BytesTransferredFormatted }
    }

    $sections = @(
        @{
            activityTitle = "SFTP Transfer $Type"
            activitySubtitle = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            facts = $facts
            markdown = $true
        }
    )

    if ($Summary -and $Summary.Errors.Count -gt 0) {
        $errorText = ($Summary.Errors | ForEach-Object { "- $_" }) -join "`n"
        $sections += @{
            title = "Errors"
            text = $errorText
        }
    }

    if ($AdditionalInfo) {
        $sections += @{
            text = $AdditionalInfo
        }
    }

    $body = @{
        "@type" = "MessageCard"
        "@context" = "http://schema.org/extensions"
        themeColor = $themeColor
        summary = $Subject
        sections = $sections
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $script:NotificationConfig.WebhookUrl `
                      -Method Post `
                      -ContentType "application/json" `
                      -Body $body `
                      -ErrorAction Stop
}

function Send-SlackNotification {
    <#
    .SYNOPSIS
        Sends a Slack notification via webhook.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,
        [string]$Subject,
        [PSCustomObject]$Summary,
        [string]$AdditionalInfo
    )

    $color = switch ($Type) {
        "Success" { "good" }
        "Warning" { "warning" }
        "Failure" { "danger" }
    }

    $emoji = switch ($Type) {
        "Success" { ":white_check_mark:" }
        "Warning" { ":warning:" }
        "Failure" { ":x:" }
    }

    $fields = @()
    if ($Summary) {
        $fields += @{ title = "Mode"; value = $Summary.Mode; short = $true }
        $fields += @{ title = "Duration"; value = $Summary.DurationFormatted; short = $true }
        $fields += @{ title = "Files Processed"; value = $Summary.FilesProcessed.ToString(); short = $true }
        $fields += @{ title = "Files Succeeded"; value = $Summary.FilesSucceeded.ToString(); short = $true }
        $fields += @{ title = "Files Failed"; value = $Summary.FilesFailed.ToString(); short = $true }
        $fields += @{ title = "Data Transferred"; value = $Summary.BytesTransferredFormatted; short = $true }
    }

    $attachments = @(
        @{
            color = $color
            title = "$emoji $Subject"
            fields = $fields
            footer = "SFTP Transfer System"
            ts = [int][double]::Parse((Get-Date -UFormat %s))
        }
    )

    if ($Summary -and $Summary.Errors.Count -gt 0) {
        $errorText = ($Summary.Errors | ForEach-Object { "• $_" }) -join "`n"
        $attachments += @{
            color = "danger"
            title = "Errors"
            text = $errorText
        }
    }

    if ($AdditionalInfo) {
        $attachments[0].text = $AdditionalInfo
    }

    $body = @{
        attachments = $attachments
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $script:NotificationConfig.WebhookUrl `
                      -Method Post `
                      -ContentType "application/json" `
                      -Body $body `
                      -ErrorAction Stop
}

function Send-GraphNotification {
    <#
    .SYNOPSIS
        Sends an email notification via Microsoft Graph API with OAuth 2.0.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,
        [string]$Subject,
        [PSCustomObject]$Summary,
        [string]$AdditionalInfo
    )

    # Get OAuth token
    $tokenUrl = "https://login.microsoftonline.com/$($script:NotificationConfig.GraphTenantId)/oauth2/v2.0/token"

    $tokenBody = @{
        client_id = $script:NotificationConfig.GraphClientId
        client_secret = $script:NotificationConfig.GraphClientSecret
        scope = "https://graph.microsoft.com/.default"
        grant_type = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    $accessToken = $tokenResponse.access_token

    # Build email content
    $fullSubject = "$($script:NotificationConfig.GraphSubjectPrefix) $Subject"
    $htmlBody = Format-GraphEmailBody -Type $Type -Summary $Summary -AdditionalInfo $AdditionalInfo

    # Build recipients
    $toRecipients = $script:NotificationConfig.GraphTo | ForEach-Object {
        @{
            emailAddress = @{
                address = $_
            }
        }
    }

    # Build email message
    $emailBody = @{
        message = @{
            subject = $fullSubject
            body = @{
                contentType = "HTML"
                content = $htmlBody
            }
            toRecipients = @($toRecipients)
        }
        saveToSentItems = $false
    } | ConvertTo-Json -Depth 10

    # Send email via Graph API
    $graphUrl = "https://graph.microsoft.com/v1.0/users/$($script:NotificationConfig.GraphFrom)/sendMail"

    $headers = @{
        Authorization = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    Invoke-RestMethod -Uri $graphUrl -Method Post -Headers $headers -Body $emailBody -ErrorAction Stop
}

function Format-GraphEmailBody {
    <#
    .SYNOPSIS
        Creates HTML email body for Graph API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,
        [PSCustomObject]$Summary,
        [string]$AdditionalInfo
    )

    $statusColor = switch ($Type) {
        "Success" { "#28a745" }
        "Warning" { "#ffc107" }
        "Failure" { "#dc3545" }
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; }
        .header { background-color: $statusColor; color: white; padding: 20px; text-align: center; }
        .header h2 { margin: 0; }
        .content { padding: 20px; background-color: #f9f9f9; }
        .summary-table { width: 100%; border-collapse: collapse; margin: 15px 0; background: white; }
        .summary-table td { padding: 10px; border-bottom: 1px solid #eee; }
        .summary-table td:first-child { font-weight: 600; width: 40%; color: #555; }
        .errors { background-color: #fff3cd; padding: 15px; margin: 15px 0; border-left: 4px solid #ffc107; border-radius: 4px; }
        .errors h4 { margin: 0 0 10px 0; color: #856404; }
        .errors ul { margin: 0; padding-left: 20px; }
        .errors li { margin: 5px 0; }
        .footer { font-size: 12px; color: #666; padding: 15px 20px; text-align: center; background: #eee; }
        .info { background-color: #e7f3ff; padding: 15px; margin: 15px 0; border-left: 4px solid #0078d4; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>SFTP Transfer $Type</h2>
        </div>
        <div class="content">
"@

    if ($Summary) {
        $html += @"
            <table class="summary-table">
                <tr><td>Operation Mode</td><td>$($Summary.Mode)</td></tr>
                <tr><td>Start Time</td><td>$($Summary.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))</td></tr>
                <tr><td>End Time</td><td>$($Summary.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))</td></tr>
                <tr><td>Duration</td><td>$($Summary.DurationFormatted)</td></tr>
                <tr><td>Files Processed</td><td>$($Summary.FilesProcessed)</td></tr>
                <tr><td>Files Succeeded</td><td>$($Summary.FilesSucceeded)</td></tr>
                <tr><td>Files Failed</td><td>$($Summary.FilesFailed)</td></tr>
                <tr><td>Data Transferred</td><td>$($Summary.BytesTransferredFormatted)</td></tr>
            </table>
"@

        if ($Summary.Errors -and $Summary.Errors.Count -gt 0) {
            $html += @"
            <div class="errors">
                <h4>Errors</h4>
                <ul>
"@
            foreach ($err in $Summary.Errors) {
                $escapedError = [System.Web.HttpUtility]::HtmlEncode($err)
                $html += "                    <li>$escapedError</li>`n"
            }
            $html += @"
                </ul>
            </div>
"@
        }
    }

    if ($AdditionalInfo) {
        $escapedInfo = [System.Web.HttpUtility]::HtmlEncode($AdditionalInfo)
        $html += @"
            <div class="info">
                <p>$escapedInfo</p>
            </div>
"@
    }

    $html += @"
        </div>
        <div class="footer">
            <p>This is an automated message from the SFTP Transfer System</p>
            <p>Generated at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        </div>
    </div>
</body>
</html>
"@

    return $html
}

Export-ModuleMember -Function Initialize-SftpNotifications, Send-SftpNotification
