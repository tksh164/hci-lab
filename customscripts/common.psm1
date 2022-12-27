function GetConfigParameters
{
    [CmdletBinding()]
    param ()

    $encodedUserData = Invoke-RestMethod -UseBasicParsing -Method Get -Headers @{ Metadata = 'true' } -Uri 'http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-12-13&format=text'
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedUserData)) | ConvertFrom-Json
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
