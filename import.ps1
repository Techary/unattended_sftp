param(
    [Parameter(Mandatory)][WinSCP.Session]$Session
)

foreach ($path in $env:remote_import_path){
    try{
        # List files in the remote directory
        $directoryInfo = $session.ListDirectory($Path)

        # Iterate through each file in the directory
        foreach ($fileInfo in $directoryInfo.Files) {
            if ($fileInfo.IsDirectory -or $fileInfo.Name -eq "..") {
                continue
            }

            # # Check if the file is already in the completed folder
            # $completedFilePath = Join-Path $completedFolder $fileInfo.Name
            # if ($session.FileExists($completedFilePath)) {
            #     Write-Host "File '$($fileInfo.Name)' already in completed folder, skipping."
            #     continue
            # }

            # Download the new file to the local directory
            $localFilePath = Join-Path $env:local_import_path $fileInfo.Name
            $transferOptions = New-Object WinSCP.TransferOptions
            $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

            $transferResult = $session.GetFileToDirectory($path + "/" + $fileInfo.Name, $env:local_import_path, $False, $transferOptions)
            if (!$transferResult.error) {
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