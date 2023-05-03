#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.11.2' }

$UserDataGetUriFormatString = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}?api-version=2022-08-01&$expand=userData'
$UserDataPatchUriFormatString = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}?api-version=2022-08-01'

function Get-VMUserData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupNmae,

        [Parameter(Mandatory = $true)]
        [string] $VMName
    )

    $subscriptionId = (Get-AzContext).Subscription.Id

    $params = @{
        Uri    = $UserDataGetUriFormatString -f $subscriptionId, $ResourceGroupNmae, $VMName
        Method = 'GET'
    }
    $restResult = Invoke-AzRestMethod @params

    $vmData = $restResult.Content | ConvertFrom-Json
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($vmData.properties.userData)) | ConvertFrom-Json
}

function Set-VMUserData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupNmae,

        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject] $UserData
    )

    $subscriptionId = (Get-AzContext).Subscription.Id

    $params = @{
        Uri    = $UserDataGetUriFormatString -f $subscriptionId, $ResourceGroupNmae, $VMName
        Method = 'GET'
    }
    $restResult = Invoke-AzRestMethod @params

    $vmData = $restResult.Content | ConvertFrom-Json
    $vmData.properties.userData = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($UserData | ConvertTo-Json -Depth 64)))

    $params = @{
        Uri     = $UserDataPatchUriFormatString -f $subscriptionId, $ResourceGroupNmae, $VMName
        Method  = 'PATCH'
        Payload = $vmData | ConvertTo-Json -Depth 64
    }
    Invoke-AzRestMethod @params
}

Export-ModuleMember -Function @(
    'Get-VMUserData',
    'Set-VMUserData'
)
