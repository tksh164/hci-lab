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
        throw 'The storage account "{0}" does not support static website hosting. You need a storage account that has [Kind:StorageV2, Tier:Standard] or [Kind:BlockBlobStorage, Tier:Premium].' -f $StorageAccountName
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
        throw 'The "{0}" folder does not exists. Your folder structure is different from the expected folder structure.' -f $sourceFolderPath
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

        try
        {
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
        catch
        {
            throw 'Failed to upload the artifact "{0}" to the storage account. You may lack the "Storage Blob Data Contributor" access to the storage account if you get a not authorized error (403). Error: {1}' -f $blobName, $_.Exception.Message
        }
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

#
# Upload artifacts to the storage account.
#

$sourceFolderName = @{
    Template = 'template'
    UIForms  = 'uiforms'
}

$sourceFolderName.Keys | ForEach-Object -Process {
    $params = @{
        SourceFolderPath     = Get-SourceFolderPath -FolderName $_
        DestinationContainer = Get-DestinationWebContainer -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
    }
    Invoke-HciLabArtifactsUpload @params
} | Select-Object -Property Name, Length, LastModified | Format-Table -AutoSize

#
# Display URI information.
#

$webEndpoint = Get-WebEndpoint -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName

$templateFileName = 'template.json'
$escapedTemplateUri = [uri]::EscapeDataString($webEndpoint + $sourceFolderName.Template + '/' + $templateFileName)

$uiFormFileNames = @(
    'uiform.json',
    'uiform-jajp.json'
)

$uiFormFileNames | ForEach-Object -Process {
    $uiFormFileName = $_
    Write-Host
    Write-Host ('[{0}]' -f $uiFormFileName) -ForegroundColor Cyan

    Write-Host 'Web primary endpoint  : ' -NoNewline -ForegroundColor Green
    Write-Host $webEndpoint

    $artifactsBaseUri = $webEndpoint + $sourceFolderName.Template + '/'
    Write-Host 'Base URI for artifacts: ' -NoNewline -ForegroundColor Green
    Write-Host $artifactsBaseUri

    $escapedUiFormUri = [uri]::EscapeDataString($webEndpoint + $sourceFolderName.UIForms + '/' + $uiFormFileName)
    $customDeployUri = 'https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/{0}/uiFormDefinitionUri/{1}' -f $escapedTemplateUri, $escapedUiFormUri
    Write-Host ('Custom deploy URI     : ' -f $uiFormFileName) -NoNewline -ForegroundColor Green
    Write-Host $customDeployUri
}
