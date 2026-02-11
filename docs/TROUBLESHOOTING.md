# Troubleshooting Guide

## Exit Code Reference

| Code | Description | Common Causes |
|------|-------------|---------------|
| 0 | Success | All operations completed successfully |
| 1 | Configuration Error | Missing .env file, invalid values, paths don't exist |
| 2 | Connection Error | Network issues, invalid credentials, wrong fingerprint |
| 3 | Transfer Error | All file transfers failed |
| 4 | Partial Success | Some files transferred, others failed |

## Common Issues

### Connection Issues

#### "Host key wasn't verified"

The SSH host key fingerprint in your .env doesn't match the server.

**Solution:**
1. Connect to the server manually with WinSCP GUI
2. Accept the host key when prompted
3. Copy the fingerprint from Session > Server/Protocol Information
4. Update `SshHostKeyFingerprint` in your .env file

See [SSH_FINGERPRINT_GUIDE.md](SSH_FINGERPRINT_GUIDE.md) for detailed instructions.

#### "Connection timed out"

Network connectivity issue or firewall blocking.

**Solution:**
1. Test basic connectivity:
   ```powershell
   Test-NetConnection -ComputerName sftp.example.com -Port 22
   ```
2. Check firewall rules for outbound port 22
3. Verify VPN connection if required
4. Increase `connection_timeout_seconds` in .env

#### "Connection refused"

Server is not accepting connections on the specified port.

**Solution:**
1. Verify the hostname and port are correct
2. Check if the SFTP service is running on the server
3. Confirm you're not IP-blocked by the server

### Authentication Issues

#### "Authentication failed"

Private key or passphrase incorrect.

**Solution:**
1. Verify private key path exists and is readable:
   ```powershell
   Test-Path "C:\path\to\your\key.ppk"
   ```
2. Delete the passphrase file and re-enter on next run:
   ```powershell
   Remove-Item "C:\path\to\passphrase.txt"
   ```
3. Ensure key format is PPK (convert with PuTTYgen if needed)
4. Verify the public key is registered on the server

#### "Private key not found"

The path to your private key is incorrect.

**Solution:**
1. Check `privkey_path` in your .env file
2. Use absolute paths to avoid confusion
3. Ensure no extra spaces or quotes in the path

### Transfer Issues

#### "Permission denied" on upload

Remote server doesn't allow write access to the destination.

**Solution:**
1. Verify SFTP user has write permissions on remote directory
2. Check `remote_export_path` is correct and accessible
3. Contact server administrator to verify permissions

#### "Permission denied" on download

Cannot write to local directory.

**Solution:**
1. Verify the local directory exists:
   ```powershell
   Test-Path "C:\local\import\path"
   ```
2. Check that the user running the script has write permissions
3. Run PowerShell as Administrator if needed

#### Files not appearing in destination

Filters may be excluding files.

**Solution:**
1. Check `include_pattern` and `exclude_pattern` in .env
2. Run with `-Verbose` to see filtering decisions:
   ```powershell
   .\main.ps1 -Mode export -Verbose
   ```
3. Temporarily set filters to include all:
   ```ini
   include_pattern = *
   exclude_pattern =
   ```

#### "No files to transfer"

No files match the configured filters, or source directory is empty.

**Solution:**
1. Verify source directory contains files
2. Check filter patterns match your files
3. Enable DEBUG logging to see detailed file discovery

### Module Loading Issues

#### "Failed to load required modules"

Modules directory is missing or corrupted.

**Solution:**
1. Verify the `modules` directory exists in the same location as main.ps1
2. Check all module subdirectories are present:
   - modules/SftpConfig
   - modules/SftpLogger
   - modules/SftpRetry
   - modules/SftpNotification
   - modules/SftpTransfer
3. Re-download or restore the modules if missing

### Logging Issues

#### Log files not being created

Logging may be disabled or path is invalid.

**Solution:**
1. Check `log_enabled = true` in .env
2. Verify `log_path` directory exists or can be created
3. Ensure the user has write permissions to the log directory

## Log Analysis

Log files are stored in the `logs/` directory with format:
`sftp_<mode>_YYYYMMDD.log`

### Log Entry Format

```
2024-01-15 10:30:45.123 [INFO ] Session opened to sftp.example.com:22
2024-01-15 10:30:46.234 [DEBUG] Found 5 files matching pattern '*'
2024-01-15 10:30:47.345 [WARN ] Retrying upload of data.csv...
2024-01-15 10:30:55.456 [ERROR] Failed to upload 'data.csv': Connection reset
```

- **Timestamp:** When the event occurred (millisecond precision)
- **Level:** DEBUG, INFO, WARN, ERROR
- **Message:** Description of what happened

### Log Levels

| Level | Description |
|-------|-------------|
| DEBUG | Detailed diagnostic information |
| INFO | General operational messages |
| WARN | Warning conditions (retries, non-fatal issues) |
| ERROR | Error conditions (failed transfers) |

### Enabling Debug Logging

Set in .env:
```ini
log_level = DEBUG
```

This provides detailed information about:
- Configuration loading
- File filtering decisions
- Retry attempts and delays
- Session state changes

## Health Check Mode

Use health check mode to test connectivity without transferring files:

```powershell
.\main.ps1 -Mode healthcheck
```

This will:
1. Load and validate configuration
2. Attempt to connect to the SFTP server
3. Verify authentication
4. Report success or detailed error information

## Getting Help

If you're still experiencing issues:

1. Enable DEBUG logging and review the log file
2. Run the health check to isolate connection vs transfer issues
3. Test manually with WinSCP GUI to verify credentials work
4. Check the [GitHub issues](https://github.com/your-repo/issues) for known problems
