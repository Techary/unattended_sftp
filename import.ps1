param(
    [Parameter(Mandatory=$true)]
    [WinSCP.Session]$Session
)
foreach ($path in $env:remote_import_path){
    try{
        write-verbose "Searching in $path"
        # List files in the remote directory
        $directoryInfo = $session.ListDirectory($Path)
        write-verbose "Found $($directoryinfo.files)"
        # Iterate through each file in the directory
        foreach ($fileInfo in $directoryInfo.Files) {
            if ($fileInfo.IsDirectory -or $fileInfo.Name -eq "..") {
                continue
            }
            # Download the new file to the local directory
            $localFilePath = Join-Path $env:local_import_path $fileInfo.Name
            $transferOptions = New-Object WinSCP.TransferOptions
            $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary
            write-verbose "Moving $($fileInfo.Name)"
            $transferResult = $session.GetFileToDirectory($path + "/" + $fileInfo.Name, $env:local_import_path, $False, $transferOptions)
            if ($transferResult.IsSuccess) {
                Write-Host "Downloaded '$($fileInfo.Name)' to '$localFilePath'"
            } else {
                Write-Host "Failed to download '$($fileInfo.Name)'"
            }
        }
        # Close the session
        $session.Dispose()
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
        #exit 1
    }
}
Write-Host "Script completed successfully."