# SSH Host Key Fingerprint Guide

## What is an SSH Host Key Fingerprint?

The SSH host key fingerprint is a cryptographic hash that uniquely identifies an SFTP server. When you connect to a server, your client verifies the server's identity by checking its fingerprint against a known value.

This prevents **man-in-the-middle attacks** where an attacker could intercept your connection by impersonating the real server.

## Why is it Required?

WinSCP requires you to specify the expected host key fingerprint for automated/unattended connections. This ensures:

1. You're connecting to the legitimate server
2. The connection hasn't been intercepted
3. The server hasn't been compromised or replaced

## Obtaining the Fingerprint

### Method 1: WinSCP GUI (Recommended)

This is the safest method as you can visually verify you're connecting to the correct server.

1. Open WinSCP
2. Create a new session or edit an existing one
3. Enter your server details (hostname, port, username)
4. Click "Login"
5. When prompted about the host key:
   - **Verify** this is expected (first connection) or matches previous value
   - Click "Copy key fingerprint to clipboard"
6. Paste the fingerprint into your .env file

Alternatively, after connecting:
1. Go to **Session > Server/Protocol Information**
2. Find the "Server host key fingerprint" field
3. Copy the entire value

### Method 2: WinSCP Command Line

If you have WinSCP installed, you can retrieve the fingerprint from command line:

```cmd
"C:\Program Files (x86)\WinSCP\WinSCP.com" /command ^
    "open sftp://username@sftp.example.com/ -hostkey=*" ^
    "exit"
```

This will connect (accepting any host key) and display the fingerprint. **Only use this in a trusted network environment.**

### Method 3: OpenSSH (Linux/Mac/Windows with OpenSSH)

```bash
# Get the server's public key
ssh-keyscan -t rsa sftp.example.com 2>/dev/null | ssh-keygen -lf -

# Output example:
# 2048 SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz1234567890ABCDEF sftp.example.com (RSA)
```

### Method 4: Ask Your Server Administrator

If you're connecting to a corporate or managed server, request the fingerprint from the server administrator. They should be able to provide it from the server directly:

```bash
# On the server (Linux)
ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub
```

## Fingerprint Format

The fingerprint in your .env file should look like one of these formats:

### MD5 Format (Older)
```ini
SshHostKeyFingerprint = ssh-rsa 2048 xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
```

### SHA-256 Format (Modern)
```ini
SshHostKeyFingerprint = ssh-rsa 2048 SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Full Format
```ini
SshHostKeyFingerprint = ssh-rsa 2048 xxxxxxxxxxx...
```

**Note:** Include the full string including `ssh-rsa 2048` (or `ssh-ed25519`, etc.) prefix.

## Common Key Types

| Key Type | Description |
|----------|-------------|
| ssh-rsa | RSA key (most common, 2048+ bits recommended) |
| ssh-ed25519 | EdDSA key (modern, highly secure) |
| ecdsa-sha2-nistp256 | ECDSA key with NIST P-256 curve |
| ssh-dss | DSA key (deprecated, avoid if possible) |

## Updating the Fingerprint

If the server's host key changes legitimately (server rebuild, key rotation, security update), you'll see this error:

```
Host key wasn't verified!
```

or

```
Server's host key does not match the one WinSCP has in cache.
```

### Before Updating

**IMPORTANT:** Verify with your server administrator that the key change is legitimate!

Reasons for legitimate key changes:
- Server was rebuilt/reinstalled
- Scheduled key rotation
- Security incident requiring new keys
- Migration to a new server

### How to Update

1. **Verify the change is legitimate** with your administrator
2. Get the new fingerprint using the methods above
3. Update `SshHostKeyFingerprint` in your .env file
4. Test with health check:
   ```powershell
   .\main.ps1 -Mode healthcheck
   ```

## Security Best Practices

### DO:
- Verify fingerprints out-of-band (phone call, secure email) for initial setup
- Keep a record of known fingerprints
- Investigate any unexpected fingerprint changes
- Use SHA-256 fingerprints when available

### DON'T:
- Accept fingerprint changes without verification
- Share fingerprints over insecure channels
- Use wildcard (`*`) fingerprint matching in production
- Ignore host key warnings

## Troubleshooting

### "Host key wasn't verified"

The fingerprint doesn't match. Either:
1. The fingerprint in .env is incorrect
2. The server's key has changed
3. You're connecting to a different server

**Solution:** Verify the correct fingerprint and update .env

### "Algorithm not supported"

The server uses a key type your WinSCP version doesn't support.

**Solution:** Update WinSCP to the latest version

### "Multiple host keys"

Some servers present multiple key types.

**Solution:** Use the fingerprint for the strongest key type available (prefer ed25519 > ecdsa > rsa)

## Example Configuration

```ini
# Modern server with Ed25519 key
SshHostKeyFingerprint = ssh-ed25519 255 SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz1234567890ABCDEF

# Legacy server with RSA key
SshHostKeyFingerprint = ssh-rsa 2048 SHA256:XyZaBcDeFgHiJkLmNoPqRsTuVwXyZ0987654321fedcba

# Multiple keys (separate with semicolon)
SshHostKeyFingerprint = ssh-ed25519 255 SHA256:xxx;ssh-rsa 2048 SHA256:yyy
```
