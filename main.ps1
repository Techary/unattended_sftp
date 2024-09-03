param (
    #Set the mode during script initiation
    [Parameter(Mandatory=$true)]
    [ValidateSet("import", "export")]
    [string]$Mode
)
# Load the .env file and set environment variables
$envFileContent = Get-Content .env
$envFileContent | ForEach-Object {
    $name, $value = $_.Split('=', 2)
    $value = $value.Trim('"')  # Remove any surrounding quotes if present
    # Check if the value is blank (but allow 'passphrase_path' to be blank)
    if ($name -ne "passphrase_path" -and ([string]::IsNullOrWhiteSpace($value))) {
        throw "Environment variable '$name' is required and cannot be blank."
    }
    # Check if the variable should be an array (comma-separated values)
    if ($value -match ',') {
        $arrayValue = $value -split ','
        Set-Content -Path "env:\$name" -Value ($arrayValue -join ',')
    } else {
        Set-Content -Path "env:\$name" -Value $value
    }
}
#Load WinSCP DLL
Add-Type -Path $env:winscp_path
. .\import.ps1
. .\export.ps1
# Initialize session options from .env
$sessionOptions = New-Object WinSCP.SessionOptions
$sessionOptions.Protocol = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName = $env:sftp_hostname
$sessionOptions.PortNumber = $env:sftp_port
$sessionOptions.UserName = $env:sftp_username 
$sessionOptions.SshPrivateKeyPath = $env:privkey_path
#Check to see if passphrase_path is set. If not, move on
if($env:passphrase_path){
    #Check to see if the passphrase exists for privkey
    if (!(test-path $env:passphrase_path)){
        #If not, ask for it, encrypted
        $securePassphrase = Read-Host "Enter passphrase for the private key" -AsSecureString
        #Save it to disk
        $securePassphrase | ConvertFrom-SecureString | Out-File $env:passphrase_path
    }
    $securePassphrase = Get-Content $env:passphrase_path  | ConvertTo-SecureString
    $sessionOptions.PrivateKeyPassphrase = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassphrase))
}
$sessionOptions.SshHostKeyFingerprint = $env:SshHostKeyFingerprint 
#Create a new empty WinSCP session
$session = New-Object WinSCP.Session
try {
    #Fill the session with the .env session options
    $session.Open($sessionOptions)

    # Run the appropriate operation based on the parameter
    switch ($OperationMode) {
        "import" { Import-Files -Session $session }
        "export" { Export-Files -Session $session }
    }
    
}
finally {
    # Ensure the session is closed
    $session.Dispose()
}