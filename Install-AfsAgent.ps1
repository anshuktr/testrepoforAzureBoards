function Install-AfsAgent { 

    # Install the MSI. Start-Process is used to PowerShell blocks until the operation is complete. 

    Start-Process -FilePath "C:\Agents\StorageSyncAgent_V4_WS2016.msi" -ArgumentList "/quiet" -Wait 

} 

 

Install-AfsAgent