param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("import", "export")]
    [string]$Mode
)
get-content .env | foreach {
    $name, $value = $_.split('=')
    set-content env:\$name $value
}
. .\import.ps1
. .\export.ps1
if(!$env:passphrase_path){
    $securePassphrase = Read-Host "Enter passphrase for the private key" -AsSecureString
    $securePassphrase | ConvertFrom-SecureString | Out-File $env:passphrase_path
}
Add-Type -Path $env:winscp_path
# Initialize session options
$sessionOptions = New-Object WinSCP.SessionOptions
$sessionOptions.Protocol = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName = $env:sftp_hostname
$sessionOptions.PortNumber = $env:sftp_port
$sessionOptions.UserName = $env:sftp_username 
$sessionOptions.SshPrivateKeyPath = $privateKeyPath
$securePassphrase = Get-Content $env:passphrase_path  | ConvertTo-SecureString
$sessionOptions.PrivateKeyPassphrase = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassphrase))
$sessionOptions.SshHostKeyFingerprint = $env:SshHostKeyFingerprint 
$session = New-Object WinSCP.Session
try {
    $session.Open($sessionOptions)

    # Run the appropriate operation based on the parameter
    if ($OperationMode -eq "import") {
        Import-Files -Session $session
    } elseif ($OperationMode -eq "export") {
        Export-Files -Session $session
    }
}
finally {
    # Ensure the session is closed
    $session.Dispose()
}