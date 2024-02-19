#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.12.3' }
#Requires -Modules @{ ModuleName = 'Az.Storage'; ModuleVersion = '5.7.0' }

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string] $StorageAccountName
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'

function Get-DestinationWebContainer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,
    
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName
    )

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName

    $storageAccountTypeSymbol = '{0}-{1}' -f $storageAccount.Kind, $storageAccount.Sku.Tier
    if (@('StorageV2-Standard', 'BlockBlobStorage-Premium') -notcontains $storageAccountTypeSymbol) {
        throw ('The storage account "{0}" does not support static website hosting. You need a storage account that has [Kind:StorageV2, Tier:Standard] or [Kind:BlockBlobStorage, Tier:Premium].' -f $StorageAccountName)
    }

    if (-not ($storageAccount.AllowSharedKeyAccess)) {
        throw ('Storage account key based authentication is not permitted on the storage account "{0}". This script requires Storage account key based authentication.' -f $StorageAccountName)
    }

    Enable-AzStorageStaticWebsite -Context $storageAccount.Context

    $webContainer = Get-AzStorageContainer -Context $storageAccount.Context -Name '$web' -MaxCount 1 -ErrorAction SilentlyContinue
    if ($webContainer -eq $null) {
        $webContainer = New-AzStorageContainer -Context $storageAccount.Context -Name '$web' -Permission Off
    }
    return $webContainer
}

function Get-SourceFolderPath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FolderName
    )

    $folderStructureRootPath = [IO.Path]::GetDirectoryName($PSScriptRoot)
    $sourceFolderPath = [IO.Path]::Combine($folderStructureRootPath, $FolderName)
    if (-not (Test-Path -PathType Container -LiteralPath $sourceFolderPath)) {
        throw ('The "{0}" folder does not exists. Your folder structure is different from the expected folder structure.' -f $sourceFolderPath)
    }
    return $sourceFolderPath
}

function Invoke-HciLabArtifactsUpload
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SourceFolderPath,

        [Parameter(Mandatory = $true)]
        [Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageContainer] $DestinationContainer
    )

    $folderStructureRootPath = [IO.Path]::GetDirectoryName($SourceFolderPath)

    Get-ChildItem -LiteralPath $SourceFolderPath -Recurse -File | ForEach-Object -Process {
        $filePath = $_.FullName
        $blobName = $filePath.Replace(($folderStructureRootPath + '\'), '')

        $params = @{
            Context            = $DestinationContainer.Context
            CloudBlobContainer = $DestinationContainer.CloudBlobContainer
            File               = $filePath
            Blob               = $blobName
            BlobType           = 'Block'
            Force              = $true
        }
        Set-AzStorageBlobContent @params
    }
}

function Get-WebEndpoint
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,
    
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName
    )

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
    return $storageAccount.PrimaryEndpoints.Web
}

$sourceFolderNames = @('template', 'uiforms')
$sourceFolderNames | ForEach-Object -Process {
    $params = @{
        SourceFolderPath     = Get-SourceFolderPath -FolderName $_
        DestinationContainer = Get-DestinationWebContainer -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
    }
    Invoke-HciLabArtifactsUpload @params
}

$webEndpoint = Get-WebEndpoint -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName

Write-Host
Write-Host 'Web Primary Endpoint: ' -NoNewline
Write-Host ('{0}' -f $webEndpoint) -ForegroundColor Cyan
$sourceFolderNames | ForEach-Object -Process {
    Write-Host ('The {0} folder URI: ' -f $_) -NoNewline
    Write-Host ('{0}{1}' -f $webEndpoint, $_) -ForegroundColor Cyan
}
Write-Host 'Use the template folder URI as the base URI for artifacts.'
Write-Host
