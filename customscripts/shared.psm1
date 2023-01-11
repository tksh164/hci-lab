function WriteLog
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Context,

        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Verbose', 'Warning', 'Error', 'Debug', 'Otput', 'Host')]
        [string] $Type = 'Verbose'
    )

    $builtMessage = '{0} [{1}] {2}' -f [DateTime]::Now.ToString('yyyy-MM-ddTHH:mm:ss'), $Context, $Message
    switch ($Type) {
        'Warning' { Write-Warning -Message $builtMessage }
        'Error'   { Write-Error -Message $builtMessage }
        'Debug'   { Write-Debug -Message $builtMessage }
        'Otput'   { Write-Output -InputObject $builtMessage }
        'Host'    { Write-Host -Object $builtMessage }
        default   { Write-Verbose -Message $builtMessage }
    }
}

function GetConfigParameters
{
    [CmdletBinding()]
    param ()

    $params = @{
        Method  = 'Get'
        Uri     = 'http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-12-13&format=text'
        Headers = @{
            Metadata = 'true'
        }
        UseBasicParsing = $true
    }
    $encodedUserData = Invoke-RestMethod @params
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedUserData)) | ConvertFrom-Json
}

function GetSecret
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $KeyVaultName,

        [Parameter(Mandatory = $true)]
        [string] $SecretName
    )

    $params = @{
        Method  = 'Get'
        Uri     = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-12-13&resource=https%3A%2F%2Fvault.azure.net'
        Headers = @{
            Metadata = 'true'
        }
    }
    $accessToken = (Invoke-RestMethod @params).access_token

    $params = @{
        Method  = 'Get'
        Uri     = ('https://{0}.vault.azure.net/secrets/{1}?api-version=7.3' -f $KeyVaultName, $SecretName)
        Headers = @{
            Authorization = ('Bearer {0}' -f $accessToken)
        }
    }
    ConvertTo-SecureString -String (Invoke-RestMethod @params).value -AsPlainText -Force
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

function GetUnattendAnswerFileContent
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ComputerName,

        [Parameter(Mandatory = $true)]
        [securestring] $Password,

        [Parameter(Mandatory = $true)]
        [string] $Culture
    )

    $encodedAdminPassword = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))) + 'AdministratorPassword'))

    return @'
    <?xml version="1.0" encoding="utf-8"?>
    <unattend xmlns="urn:schemas-microsoft-com:unattend">
        <servicing></servicing>
        <settings pass="oobeSystem">
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <UserAccounts>
                    <AdministratorPassword>
                        <Value>{0}</Value>
                        <PlainText>false</PlainText>
                    </AdministratorPassword>
                </UserAccounts>
                <OOBE>
                    <SkipMachineOOBE>true</SkipMachineOOBE>
                    <SkipUserOOBE>true</SkipUserOOBE>
                </OOBE>
            </component>
        </settings>
        <settings pass="specialize">
            <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <InputLocale>{1}</InputLocale>
                <SystemLocale>{1}</SystemLocale>
                <UILanguage>{1}</UILanguage>
                <UserLocale>{1}</UserLocale>
            </component>
            <component name="Microsoft-Windows-TerminalServices-LocalSessionManager" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <fDenyTSConnections>false</fDenyTSConnections>
            </component>
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <ComputerName>{2}</ComputerName>
                <TimeZone>UTC</TimeZone>
            </component>
        </settings>
    </unattend>
'@ -f $encodedAdminPassword, $Culture, $ComputerName
}

function InjectUnattendAnswerFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VhdPath,

        [Parameter(Mandatory = $true)]
        [string] $UnattendAnswerFileContent
    )

    $vhdMountPath = 'C:\tempmount'

    'Mouting the VHD...' | WriteLog -Context 'shared'
    New-Item -ItemType Directory -Path $vhdMountPath -Force
    Mount-WindowsImage -Path $vhdMountPath -Index 1 -ImagePath $VhdPath

    'Create the unattend answer file in the VHD...' | WriteLog -Context 'shared'
    $pantherPath = [IO.Path]::Combine($vhdMountPath, 'Windows', 'Panther')
    New-Item -ItemType Directory -Path $pantherPath -Force
    Set-Content -Path ([IO.Path]::Combine($pantherPath, 'unattend.xml')) -Value $UnattendAnswerFileContent -Force

    'Dismouting the VHD...' | WriteLog -Context 'shared'
    Dismount-WindowsImage -Path $vhdMountPath -Save
    Remove-Item $vhdMountPath
}

function WaitingForReadyToVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $false)]
        [int] $CheckInternal = 5
    )

    $params = @{
        VMName      = $VMName
        Credential  = $Credential
        ScriptBlock = { 'ready' }
        ErrorAction = [Management.Automation.ActionPreference]::SilentlyContinue
    }
    while ((Invoke-Command @params) -ne 'ready') {
        Start-Sleep -Seconds $CheckInternal
        'Waiting...' | WriteLog -Context 'shared'
    }    
}

function CreateDomainCredential
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $DomainFqdn,

        [Parameter(Mandatory = $true)]
        [securestring] $Password,

        [Parameter(Mandatory = $false)]
        [string] $UserName = 'Administrator'
    )

    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = @(
            ('{0}\{1}' -f $DomainFqdn, $UserName),
            $Password
        )
    }
    New-Object @params
}

function JoinVMToADDomain
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $LocalAdminCredential,

        [Parameter(Mandatory = $true)]
        [string] $DomainFqdn,

        [Parameter(Mandatory = $true)]
        [PSCredential] $DomainAdminCredential
    )

    Invoke-Command -VMName $VMName -Credential $LocalAdminCredential -ArgumentList $DomainFqdn, $DomainAdminCredential -ScriptBlock {
        $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
        $WarningPreference = [Management.Automation.ActionPreference]::Continue
        $VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    
        $domainFqdn = $args[0]
        $domainAdminCredential = $args[1]

        Add-Computer -DomainName $domainFqdn -Credential $domainAdminCredential
    }
}
