[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $TargetFolderPath
)

$targetFolder = Get-Item -LiteralPath $TargetFolderPath

Get-ChildItem -LiteralPath $targetFolder.FullName |
    Select-Object -ExpandProperty 'FullName' |
    Compress-Archive -DestinationPath (Join-Path -Path $targetFolder.Parent.FullName -ChildPath ($targetFolder.Name + '.zip')) -CompressionLevel Optimal -Force
