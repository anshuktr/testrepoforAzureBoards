function Login-Azure {
    param (
        [string]$username,
        [string]$password # Use [secureString] outside of secure environments
    )
    # Convert password to secure string (required for creating login credential)
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force

    # Create login cretential with username and password
    $credential = New-Object -typename System.Management.Automation.PSCredential `
        -argumentlist $username, $securePassword
 
    # Login non-interactively using the credential
    $acctInfo = Login-AzAccount -Credential $credential
    return $credential, $acctInfo
}

function Login-StorageSync {
    param (
        $credential,
        $acctInfo,
        [string]$resourceGroupName
    )
    # The location of the Azure File Sync Agent
    $agentPath = "C:\Agents"

    # Import the Azure File Sync management cmdlets 
    # (cmdlets not yet included in the Azure PowerShell Module)
    Import-Module "$agentPath\StorageSync.Management.PowerShell.Cmdlets.dll"

    # Store your subscription and Azure Active Directory tenant ID 
    $subID = $acctInfo.Context.Subscription.Id
    $tenantID = $acctInfo.Context.Tenant.Id

    # Get the resource group to determine the location of the sync service
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName
    $location = $resourceGroup.Location

    # The following (non-interactive) login creates an AFS context 
    # it enables subsequent AFS cmdlets to be executed with minimal 
    # repetition of parameters or separate authentication 
    Login-AzStorageSync `
        -SubscriptionId $subID `
        -ResourceGroupName $resourceGroupName `
        -TenantId $tenantID `
        -Location $location `
        -Credential $credential
}

function New-StorageSyncService {
    param (
        [string]$storageSyncName
    )
    # Create a new Storage Sync Service in the
    # Login-AzStorageSync context
    New-AzStorageSyncService -StorageSyncServiceName $storageSyncName
}

function Register-StorageSyncServer {
    param (
        [string]$storageSyncName
    )
    # Register the server executing the script as a server endpoint
    $registeredServer = Register-AzStorageSyncServer -StorageSyncServiceName $storageSyncName
    return $registeredServer
}

function New-SyncGroup {
    param (
        [string]$storageSyncName,
        [string]$syncGroupName
    )
    # Create new Sync group
    New-AzStorageSyncGroup -SyncGroupName $syncGroupName -StorageSyncService $storageSyncName
}

function New-CloudEndpoint {
    param (
        [string]$storageSyncName,
        [string]$syncGroupName,
        [string]$resourceGroupName,
        [string]$storageAccountName,
        [string]$fileShareName
    )
    # Get the storage account with desired name
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
 
    # Create the sync group with a cloud endpoint (file share)
    New-AzStorageSyncCloudEndpoint `
        -StorageSyncServiceName $storageSyncName `
        -SyncGroupName $syncGroupName `
        -StorageAccountResourceId $storageAccount.Id `
        -StorageAccountShareName $fileShareName
}

function New-ServerEndpoint {
    param (
        [string]$storageSyncName,
        [string]$syncGroupName,
        $registeredServer,
        [string]$serverEndpointPath,
        [bool]$cloudTieringDesired,
        [int]$volumeFreeSpacePercentage
    )
    # Prepare a settings hashtable for splatting
    $settings = @{
        StorageSyncServiceName = $storageSyncName
        SyncGroupName = $syncGroupName 
        ServerId = $registeredServer.Id
        ServerLocalPath = $serverEndpointPath 
    }

    # Add additional settings if cloud tiering is desired
    if ($cloudTieringDesired) {
        # Ensure endpoint path is not the system volume
        $directoryRoot = [System.IO.Directory]::GetDirectoryRoot($serverEndpointPath)
        $osVolume = "$($env:SystemDrive)\"
        if ($directoryRoot -eq $osVolume) {
            throw [System.Exception]::new("Cloud tiering cannot be enabled on the system volume")
        }

        # Add cloud tiering settings
        $settings += @{
            CloudTiering = $true
            VolumeFreeSpacePercent = $volumeFreeSpacePercentage
        }
    }
    # Use splatting to set parameters
    New-AzStorageSyncServerEndpoint @settings
}

# Login to Azure
$username = ""
$password = ""
$credential, $acctInfo = Login-Azure $username $password

# Set variables
$resourceGroupName = Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName
$storageAccountName = Get-AzStorageAccount -ResourceGroupName $resourceGroupName | `
    Where-Object StorageAccountName -like strg17may | `
    Select-Object -ExpandProperty StorageAccountName
$fileShareName = "sync"
$storageSyncName = "sync" + $(Get-Random -Maximum 1000)
$syncGroupName = "dev"
$serverEndpointPath = "C:\dev"
$cloudTieringDesired = $true
$volumeFreeSpacePercentage = 50

# Create resources
Login-StorageSync $credential $acctInfo $resourceGroupName
New-StorageSyncService $storageSyncName
$registeredServer = Register-StorageSyncServer $storageSyncName
New-SyncGroup $storageSyncName $syncGroupName 
New-CloudEndpoint $storageSyncName $syncGroupName $resourceGroupName $storageAccountName $fileShareName
New-ServerEndpoint $storageSyncName `
    $syncGroupName `
    $registeredServer `
    $serverEndpointPath `
    $cloudTieringDesired `
    $volumeFreeSpacePercentage