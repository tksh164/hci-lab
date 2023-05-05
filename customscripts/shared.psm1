function Start-ScriptLogging
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $OutputDirectory,

        # The log file name suffix. The default value is the file name without extension of the caller script.
        [Parameter(Mandatory = $false)]
        [string] $FileName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
    )

    $transcriptFileName = Get-LogFileName -FileName $FileName
    $transcriptFilePath = [IO.Path]::Combine($OutputDirectory, $transcriptFileName)
    Start-Transcript -LiteralPath $transcriptFilePath -Append -IncludeInvocationHeader
}

function Stop-ScriptLogging
{
    [CmdletBinding()]
    param ()
    Stop-Transcript
}

function Get-LogFileName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string] $FileName
    )

    '{0:yyyyMMdd-HHmmss}_{1}_{2}.txt' -f [DateTime]::Now, $env:ComputerName, $FileName
}

function Write-ScriptLog
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Context,

        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Verbose', 'Warning', 'Error', 'Debug', 'Otput', 'Host')]
        [string] $Type = 'Verbose',

        [Parameter(Mandatory = $false)]
        [switch] $UseInScriptBlock
    )

    $builtMessage = '[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}' -f [DateTime]::Now, $Context, $Message
    switch ($Type) {
        'Warning' { Write-Warning -Message $builtMessage }
        'Error'   { Write-Error -Message $builtMessage }
        'Debug'   { Write-Debug -Message $builtMessage }
        'Otput'   { Write-Output -InputObject $builtMessage }
        'Host'    { Write-Host -Object $builtMessage }
        default   {
            if ($UseInScriptBlock) {
                # NOTE: Redirecting a verbose message because verbose messages are not showing it come from script blocks.
                Write-Verbose -Message ('VERBOSE: ' + $builtMessage) 4>&1
            }
            else {
                Write-Verbose -Message $builtMessage
            }
        }
    }
}

function Get-LabDeploymentConfig
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
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolder,
    
        [Parameter(Mandatory = $true)]
        [string] $FileNameToSave
    )

    $destinationFilePath = [IO.Path]::Combine($DownloadFolder, $FileNameToSave)
    Start-BitsTransfer -Source $SourceUri -Destination $destinationFilePath
    Get-Item -LiteralPath $destinationFilePath
}

function GetIsoFileName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $false)]
        [string] $Suffix
    )

    if ($PSBoundParameters.Keys.Contains('Suffix')) {
        '{0}_{1}_{2}.iso' -f $OperatingSystem, $Culture, $Suffix
    }
    else {
        '{0}_{1}.iso' -f $OperatingSystem, $Culture
    }
}

function GetBaseVhdFileName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 4)]
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $Culture
    )

    '{0}_{1}_{2}.vhdx' -f $OperatingSystem, $ImageIndex, $Culture
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
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>{1}</ComputerName>
            <TimeZone>UTC</TimeZone>
        </component>
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>{2}</InputLocale>
            <SystemLocale>{2}</SystemLocale>
            <UILanguage>{2}</UILanguage>
            <UserLocale>{2}</UserLocale>
        </component>
        <component name="Microsoft-Windows-TerminalServices-LocalSessionManager" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <fDenyTSConnections>false</fDenyTSConnections>
        </component>
        <component name="Networking-MPSSVC-Svc" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <FirewallGroups>
                <FirewallGroup wcm:action="add" wcm:keyValue="RemoteDesktop">
                    <Active>true</Active>
                    <Group>@FirewallAPI.dll,-28752</Group>
                    <Profile>domain</Profile>
                </FirewallGroup>
            </FirewallGroups>
        </component>
    </settings>
</unattend>
'@ -f $encodedAdminPassword, $ComputerName, $Culture
}

function InjectUnattendAnswerFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $VhdPath,

        [Parameter(Mandatory = $true)]
        [string] $UnattendAnswerFileContent,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $LogFolder
    )

    $baseFolderName = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)) + '-' + (New-Guid).Guid.Substring(0, 4)

    'Mouting the VHD...' | Write-ScriptLog -Context $VhdPath

    $vhdMountPath = [IO.Path]::Combine('C:\', $baseFolderName + '-mount')
    'vhdMountPath: {0}' -f $vhdMountPath | Write-ScriptLog -Context $VhdPath
    New-Item -ItemType Directory -Path $vhdMountPath -Force

    $scratchDirectory = [IO.Path]::Combine('C:\', $baseFolderName + '-scratch')
    'scratchDirectory: {0}' -f $scratchDirectory | Write-ScriptLog -Context $VhdPath
    New-Item -ItemType Directory -Path $scratchDirectory -Force

    $logPath = [IO.Path]::Combine($LogFolder, (Get-LogFileName -FileName ('injectunattend-' + [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)))))
    'logPath: {0}' -f $logPath | Write-ScriptLog -Context $VhdPath
    Mount-WindowsImage -Path $vhdMountPath -Index 1 -ImagePath $VhdPath -ScratchDirectory $scratchDirectory -LogPath $logPath

    'Create the unattend answer file in the VHD...' | Write-ScriptLog -Context $VhdPath
    $pantherPath = [IO.Path]::Combine($vhdMountPath, 'Windows', 'Panther')
    New-Item -ItemType Directory -Path $pantherPath -Force
    Set-Content -Path ([IO.Path]::Combine($pantherPath, 'unattend.xml')) -Value $UnattendAnswerFileContent -Force

    'Dismouting the VHD...' | Write-ScriptLog -Context $VhdPath
    Dismount-WindowsImage -Path $vhdMountPath -Save -ScratchDirectory $scratchDirectory -LogPath $logPath

    Remove-Item $vhdMountPath -Force
    Remove-Item $scratchDirectory -Force
}
}

function WaitingForStartingVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $CheckInterval = 5
    )

    while ((Start-VM -Name $VMName -Passthru -ErrorAction SilentlyContinue) -eq $null) {
        'Will retry start the VM. Waiting for unmount the VHD...' | Write-ScriptLog -Context $VMName
        Start-Sleep -Seconds $CheckInterval
    }
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
        [ValidateRange(0, 3600)]
        [int] $CheckInterval = 5
    )

    $params = @{
        VMName      = $VMName
        Credential  = $Credential
        ScriptBlock = { 'ready' }
        ErrorAction = [Management.Automation.ActionPreference]::SilentlyContinue
    }
    while ((Invoke-Command @params) -ne 'ready') {
        Start-Sleep -Seconds $CheckInterval
        'Waiting for ready to VM "{0}"...' -f $VMName | Write-ScriptLog -Context $VMName
    }    
}

function WaitingForReadyToAddsDcVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $AddsDcVMName,

        [Parameter(Mandatory = $true)]
        [string] $AddsDcComputerName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $CheckInterval = 5
    )

    $params = @{
        VMName       = $AddsDcVMName
        Credential   = $Credential
        ArgumentList = $AddsDcComputerName
        ScriptBlock  = {
            $dcComputerName = $args[0]
            (Get-ADDomainController -Server $dcComputerName).Enabled
        }
        ErrorAction  = [Management.Automation.ActionPreference]::SilentlyContinue
    }
    while ((Invoke-Command @params) -ne $true) {
        Start-Sleep -Seconds $CheckInterval
        'Waiting for ready to AD DS DC VM "{0}"...' -f $AddsDcVMName | Write-ScriptLog -Context $AddsDcVMName
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

    $retryLimit = 10
    for ($retryCount = 0; $retryCount -lt $retryLimit; $retryCount++) {
        try {
            # NOTE: Domain joining will fail sometimes.
            $params = @{
                VMName      = $VMName
                Credential  = $LocalAdminCredential
                InputObject = [PSCustomObject] @{
                    DomainFqdn            = $DomainFqdn
                    DomainAdminCredential = $DomainAdminCredential
                }
            }
            Invoke-Command @params -ScriptBlock {
                param (
                    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                    [string] $DomainFqdn,
            
                    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                    [PSCredential] $DomainAdminCredential
                )
        
                $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
                $WarningPreference = [Management.Automation.ActionPreference]::Continue
                $VerbosePreference = [Management.Automation.ActionPreference]::Continue
                $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
            
                Add-Computer -DomainName $DomainFqdn -Credential $DomainAdminCredential
            }
            break
        }
        catch {
            'Will retry join to domain "{0}"...' -f $DomainFqdn | Write-ScriptLog -Context $VMName
        }
    }
    if ($retryCount -ge $retryLimit) {
        throw 'Failed join to domain "{0}"' -f $DomainFqdn
    }
}
