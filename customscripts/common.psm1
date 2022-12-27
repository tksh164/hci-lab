function GetConfigParametersFromJsonFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    Get-Content -Raw -Encoding UTF8 -LiteralPath $FilePath | ConvertJsonToCustomObject
}

function ConvertJsonToCustomObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Json
    )

    $Json -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/' | ConvertFrom-Json
}

function DownloadFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SourceUri,

        [Parameter(Mandatory = $true)]
        [string] $DownloadFolder,
    
        [Parameter(Mandatory = $true)]
        [string] $FileNameToSave
    )

    $destinationFilePath = [IO.Path]::Combine($DownloadFolder, $FileNameToSave)
    Start-BitsTransfer -Source $SourceUri -Destination $destinationFilePath
    Get-Item -LiteralPath $destinationFilePath
}
