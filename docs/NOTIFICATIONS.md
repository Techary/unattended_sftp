# Notifications Setup Guide

The SFTP transfer system supports multiple notification providers for alerting on transfer success or failure.

## Supported Providers

| Provider | Description |
|----------|-------------|
| `msteams` | Microsoft Teams via Incoming Webhook |
| `slack` | Slack via Incoming Webhook |
| `webhook` | Generic webhook (JSON payload) |
| `graph` | Email via Microsoft Graph API (OAuth 2.0) |

## Configuration

### Basic Settings

```ini
notify_enabled = true
notify_provider = msteams    # or slack, webhook, graph
notify_on_success = false    # Send notification on successful transfer
notify_on_failure = true     # Send notification on failed transfer
```

---

## Microsoft Teams Setup

Microsoft Teams uses Incoming Webhooks to receive notifications.

### 1. Create an Incoming Webhook

1. Open Microsoft Teams
2. Navigate to the channel where you want notifications
3. Click the **...** menu next to the channel name
4. Select **Connectors** (or **Manage channel** > **Connectors**)
5. Search for **Incoming Webhook** and click **Configure**
6. Give your webhook a name (e.g., "SFTP Alerts")
7. Optionally upload an icon
8. Click **Create**
9. Copy the webhook URL

### 2. Configure .env

```ini
notify_enabled = true
notify_provider = msteams
notify_webhook_url = https://outlook.office.com/webhook/your-webhook-url
notify_on_failure = true
```

### Sample Teams Message

The notification will appear as a card with:
- Color-coded header (green/yellow/red)
- Transfer statistics (files, duration, data transferred)
- Error details if applicable

---

## Slack Setup

Slack uses Incoming Webhooks to receive notifications.

### 1. Create a Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **Create New App** > **From scratch**
3. Name your app (e.g., "SFTP Alerts") and select your workspace
4. Click **Create App**

### 2. Enable Incoming Webhooks

1. In your app settings, click **Incoming Webhooks**
2. Toggle **Activate Incoming Webhooks** to On
3. Click **Add New Webhook to Workspace**
4. Select the channel for notifications
5. Click **Allow**
6. Copy the webhook URL

### 3. Configure .env

```ini
notify_enabled = true
notify_provider = slack
notify_webhook_url = https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_SECRET
notify_on_failure = true
```

---

## Generic Webhook

For custom integrations or third-party services.

### Payload Format

The webhook receives a JSON POST request:

```json
{
  "type": "Success",
  "subject": "Transfer Completed Successfully",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "summary": {
    "mode": "export",
    "filesProcessed": 10,
    "filesSucceeded": 10,
    "filesFailed": 0,
    "bytesTransferred": 1048576,
    "duration": "00:01:23",
    "errors": []
  },
  "additionalInfo": null
}
```

### Configure .env

```ini
notify_enabled = true
notify_provider = webhook
notify_webhook_url = https://your-service.com/api/webhook
notify_on_failure = true
```

---

## Microsoft Graph API (OAuth 2.0 Email)

Send email notifications using Microsoft Graph API with OAuth 2.0 authentication. This is the recommended method for Microsoft 365 environments as basic SMTP authentication is being deprecated.

### Prerequisites

- Azure AD tenant
- Microsoft 365 mailbox for sending
- Admin access to register applications

### 1. Register an Azure AD Application

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** > **App registrations**
3. Click **New registration**
4. Configure:
   - **Name:** SFTP Transfer Notifications
   - **Supported account types:** Accounts in this organizational directory only
   - **Redirect URI:** Leave blank (not needed for client credentials)
5. Click **Register**
6. Note the **Application (client) ID** and **Directory (tenant) ID**

### 2. Configure API Permissions

1. In your app registration, go to **API permissions**
2. Click **Add a permission**
3. Select **Microsoft Graph**
4. Select **Application permissions**
5. Search for and add: `Mail.Send`
6. Click **Add permissions**
7. Click **Grant admin consent for [your organization]**
8. Confirm the consent

### 3. Create a Client Secret

1. Go to **Certificates & secrets**
2. Click **New client secret**
3. Add a description and select expiration
4. Click **Add**
5. **Immediately copy the secret value** (it won't be shown again)

### 4. Store the Client Secret Securely

Create a file to store the secret (e.g., `C:\sftp\secrets\graph_secret.txt`):

```
your-client-secret-value
```

Ensure proper file permissions:
```powershell
# Restrict access to the secret file
$acl = Get-Acl "C:\sftp\secrets\graph_secret.txt"
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "BUILTIN\Administrators", "FullControl", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "C:\sftp\secrets\graph_secret.txt" $acl
```

### 5. Configure .env

```ini
notify_enabled = true
notify_provider = graph
notify_on_failure = true

notify_graph_tenant_id = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
notify_graph_client_id = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
notify_graph_client_secret_path = C:\sftp\secrets\graph_secret.txt
notify_graph_from = sftp-alerts@yourdomain.com
notify_graph_to = admin@yourdomain.com,ops@yourdomain.com
notify_graph_subject_prefix = [SFTP Transfer]
```

**Note:** The `notify_graph_from` address must be a valid mailbox in your tenant that the application has permission to send as.

### Alternative: Direct Secret (Not Recommended)

For testing only, you can put the secret directly in .env:

```ini
notify_graph_client_secret = your-secret-value
```

**Warning:** This is less secure as the secret is stored in plain text in the configuration file.

---

## Testing Notifications

### Test Connection

Run a health check to verify basic connectivity (doesn't send notification):

```powershell
.\main.ps1 -Mode healthcheck
```

### Force a Test Notification

Create a test scenario by temporarily configuring `notify_on_success = true` and running an import/export with no files:

```powershell
.\main.ps1 -Mode import -Verbose
```

### Common Issues

#### Teams: "Webhook URL is invalid"
- Verify the webhook URL is correct
- Ensure the webhook hasn't been deleted in Teams
- Check for typos in the URL

#### Slack: "No response from webhook"
- Verify the app is still installed in your workspace
- Check the webhook URL is correct
- Ensure the target channel still exists

#### Graph: "Unauthorized" or "Access denied"
- Verify admin consent was granted
- Check client ID and tenant ID are correct
- Ensure the client secret hasn't expired
- Verify the `notify_graph_from` mailbox exists and the app has permission

#### Graph: "Request failed"
- Check network connectivity to Microsoft services
- Verify the recipient email addresses are valid
- Check Azure AD app registration is still active

---

## Security Considerations

1. **Protect webhook URLs** - Treat webhook URLs as secrets; don't commit them to source control
2. **Use secret files** - Store Graph client secrets in separate files with restricted permissions
3. **Limit permissions** - The Graph app only needs `Mail.Send` permission
4. **Rotate secrets** - Periodically rotate client secrets and webhook URLs
5. **Monitor usage** - Review Azure AD sign-in logs for the application
