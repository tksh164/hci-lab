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

function Get-WebContainerOrCreateIfNotExists
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

function Get-TemplateFolderPath
{
    [CmdletBinding()]
    param ()
    
    $folderStructureRootPath = [IO.Path]::GetDirectoryName($PSScriptRoot)
    $templateFolderName = 'template'
    $templateFolderPath = [IO.Path]::Combine($folderStructureRootPath, $templateFolderName)
    if (-not (Test-Path -PathType Container -LiteralPath $templateFolderPath)) {
        throw ('The "{0}" folder does not exist. Your folder structure is different from the expected folder structure.' -f $templateFolderPath)
    }
    return $templateFolderPath
}

function Invoke-HciLabTemplateUpload
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageContainer] $WebContainer,
    
        [Parameter(Mandatory = $true)]
        [string] $TemplateFolderPath
    )

    $folderStructureRootPath = [IO.Path]::GetDirectoryName($TemplateFolderPath)

    Get-ChildItem -LiteralPath $TemplateFolderPath -Recurse -File | ForEach-Object -Process {
        $filePath = $_.FullName
        $blobName = $filePath.Replace(($folderStructureRootPath + '\'), '')

        $params = @{
            Context            = $WebContainer.Context
            CloudBlobContainer = $WebContainer.CloudBlobContainer
            File               = $filePath
            Blob               = $blobName
            BlobType           = 'Block'
            Force              = $true
        }
        Set-AzStorageBlobContent @params
    }
}

function Write-WebEndpoint
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,
    
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName
    )

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
    Write-Host
    Write-Host ('Web Primary Endpoint: {0}' -f $storageAccount.PrimaryEndpoints.Web) -ForegroundColor Cyan
    Write-Host
}

$params = @{
    WebContainer       = Get-WebContainerOrCreateIfNotExists -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
    TemplateFolderPath = Get-TemplateFolderPath
}
Invoke-HciLabTemplateUpload @params

Write-WebEndpoint -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
