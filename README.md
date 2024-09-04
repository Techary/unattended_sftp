
# Unattended SFTP File Transfer Scripts

## Overview

This project provides a set of PowerShell scripts to automate the process of importing and exporting files via SFTP using WinSCP. The scripts support configurable paths, robust error handling, and the ability to import/export files based on a given operation mode.

### Scripts

1. **main.ps1**
   - The main entry point for running the import or export operation.
   - Loads environment variables from a `.env` file and invokes either `import.ps1` or `export.ps1` based on the specified operation mode.

2. **import.ps1**
   - Handles the importing (downloading) of files from a remote SFTP server to a local directory.
   - Validates that all necessary environment variables are set and handles file transfers while avoiding modification of timestamps or permissions.

3. **export.ps1**
   - Handles the exporting (uploading) of files from a local directory to a remote SFTP server.
   - Ensures correct path construction for remote directories and disables timestamp or permission modification to avoid common errors.

### Configuration

The scripts rely on a `.env` file for configuration. This file should be placed in the root directory of the project and must define the necessary environment variables.

#### Example .env File

```plaintext
winscp_path = C:\Users\your_name\AppData\Local\Programs\WinSCP\WinSCPnet.dll
sftp_hostname = sftp.host.name
sftp_port = 22
sftp_username = sftp_user
local_export_path = 
remote_export_path =
local_import_path = 
remote_import_path =
privkey_path = <userprofile>\.ssh\winscpPrivKey.ppk
passphrase_path = C:\path\to\passphrase.txt
SshHostKeyFingerprint = <sh-rsa fingerprint>
```

### Usage

1. **Running the Scripts**
   - To run the import or export process, invoke the `main.ps1` script with the appropriate operation mode.

   ```powershell
   .\main.ps1 -mode "import"
   .\main.ps1 -mode "export"
   ```

   - `mode` should be either `"import"` or `"export"`.

2. **Customization**
   - Modify the `.env` file to suit your environment and directory structure.
   - Ensure that all paths are correctly set up in the `.env` file, and that the `WinSCPnet.dll` is correctly referenced.

### Error Handling

The scripts include basic error handling to manage issues such as connection failures, permission errors, and missing configuration. If an error occurs, it will be logged, and the script will attempt to safely close the SFTP session.

### Requirements

- **PowerShell 5.1 or later** (PowerShell Core may also be compatible).
- **WinSCP**: Ensure that the WinSCP .NET assembly (`WinSCPnet.dll`) is available and correctly referenced in the `.env` file.

### Notes

- The `passphrase_path` is optional and can be left blank in the `.env` file if not required.
- Ensure that the SFTP server supports the operations you intend to perform, especially concerning file permissions and timestamps.
