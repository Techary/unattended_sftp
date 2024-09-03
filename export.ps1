param(
    [Parameter(Mandatory=$true)]
    [WinSCP.Session]$Session
)
foreach ($path in $env:local_export_path) {
    try {
        write-verbose "Processing local path $path"
        # Get a list of files to upload from the local directory
        $files = Get-ChildItem -Path $path -File
        # Iterate through each file in the directory
        foreach ($file in $files) {
            # Construct the correct remote file path
            $remoteFilePath = Join-Path $env:remote_export_path $file.Name
            # Set transfer options to avoid setting permissions or timestamps
            $transferOptions = New-Object WinSCP.TransferOptions
            $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary
            $transferOptions.PreserveTimestamp = $false
            $transferOptions.FilePermissions = $null  # Do not attempt to set permissions
            write-verbose "Uploading $($file.Name)"
            # Upload the file to the remote directory
            $transferResult = $Session.PutFiles($file.FullName, $remoteFilePath, $False, $transferOptions)
            $transferResult.Check()  # Check for errors
            if (!$transferResult.error) {
                Write-Host "Uploaded '$($file.Name)' to '$remoteFilePath'"
            } else {
                Write-Host "Failed to upload '$($file.Name)'"
            }
        }
        # Close the session
        $Session.Dispose()
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
        #exit 1
    }
}
Write-Host "Export script completed successfully."