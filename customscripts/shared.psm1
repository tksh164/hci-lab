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
        [string] $FileNameToSave,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 30,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1000)]
        [int] $MaxRetryCount = 10
    )

    $destinationFilePath = [IO.Path]::Combine($DownloadFolder, $FileNameToSave)

    for ($retryCount = 0; $retryCount -lt $MaxRetryCount; $retryCount++) {
        try {
            'Downloading the file from "{0}" to "{1}".' -f $SourceUri, $destinationFilePath | Write-ScriptLog -Context $env:ComputerName
            Start-BitsTransfer -Source $SourceUri -Destination $destinationFilePath
            Get-Item -LiteralPath $destinationFilePath
            return
        }
        catch {
            'Will retry the download...' +
                '(ExceptionMessage: {0} | Exception: {1} | FullyQualifiedErrorId: {2} | CategoryInfo: {3} | ErrorDetailsMessage: {4})' -f
                $_.Exception.Message, $_.Exception.GetType().FullName, $_.FullyQualifiedErrorId, $_.CategoryInfo.ToString(), $_.ErrorDetails.Message |
                Write-ScriptLog -Context $env:ComputerName

            Remove-Item -LiteralPath $destinationFilePath -Force -ErrorAction Continue
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
    throw 'The download from "{0}" did not succeed in the acceptable retry count ({1}).' -f $SourceUri, $MaxRetryCount
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
        [uint32] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $Culture
    )

    '{0}_{1}_{2}.vhdx' -f $OperatingSystem, $ImageIndex, $Culture
}

function GetHciNodeVMName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Format,

        [Parameter(Mandatory = $true)]
        [int] $Offset,

        [Parameter(Mandatory = $true)]
        [uint32] $Index
    )

    $Format -f ($Offset + $Index)
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

function WaitingForVhdDismount
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $VhdPath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $ProbeIntervalSeconds = 5
    )

    while((Get-WindowsImage -Mounted | Where-Object -Property 'ImagePath' -EQ -Value $VhdPath) -ne $null) {
        'Waiting for VHD dismount completion...' | Write-ScriptLog -Context $VhdPath
        Start-Sleep -Seconds $ProbeIntervalSeconds
    }
    'The VHD dismount completed.' | Write-ScriptLog -Context $VhdPath
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

    'Waiting for VHD dismount completion (MountPath: "{0}")...' -f $vhdMountPath | Write-ScriptLog -Context $VhdPath
    WaitingForVhdDismount -VhdPath $VhdPath

    Remove-Item $vhdMountPath -Force
    Remove-Item $scratchDirectory -Force
}

function Install-WindowsFeatureToVhd
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $VhdPath,

        [Parameter(Mandatory = $true)]
        [string[]] $FeatureName,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $LogFolder,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 5,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 30)
    )

    $logPath = [IO.Path]::Combine($LogFolder, (Get-LogFileName -FileName ('installwinfeature-' + [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)))))
    'logPath: {0}' -f $logPath | Write-ScriptLog -Context $VhdPath

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
        # NOTE: Effort to prevent concurrent DISM operations.
        $mutex = New-Object -TypeName 'System.Threading.Mutex' -ArgumentList $false, 'Local\HciLabMutexInstallWindowsFeature'
        'Requesting the mutex for the Install-WindowsFeature cmdlet''s DISM operation...' | Write-ScriptLog -Context $VhdPath
        $mutex.WaitOne()
        'Acquired the mutex for the Install-WindowsFeature cmdlet''s DISM operation.' | Write-ScriptLog -Context $VhdPath

        try {
            # NOTE: Install-WindowsFeature cmdlet will fail sometimes due to concurrent operations, etc.
            $params = @{
                Vhd                    = $VhdPath
                Name                   = $FeatureName
                IncludeManagementTools = $true
                LogPath                = $logPath
                ErrorAction            = [Management.Automation.ActionPreference]::Stop
            }
            Install-WindowsFeature @params

            # NOTE: The DISM mount point is still remain after the Install-WindowsFeature cmdlet completed.
            'Waiting for VHD dismount completion by the Install-WindowsFeature cmdlet execution...' | Write-ScriptLog -Context $VhdPath
            WaitingForVhdDismount -VhdPath $VhdPath

            'Windows features installation to VHD was completed.' | Write-ScriptLog -Context $VhdPath
            return
        }
        catch {
            'Thrown a exception by Install-WindowsFeature cmdlet execution. Will retry Install-WindowsFeature cmdlet...' +
                '(ExceptionMessage: {0} | Exception: {1} | FullyQualifiedErrorId: {2} | CategoryInfo: {3} | ErrorDetailsMessage: {4})' -f
                $_.Exception.Message, $_.Exception.GetType().FullName, $_.FullyQualifiedErrorId, $_.CategoryInfo.ToString(), $_.ErrorDetails.Message |
                Write-ScriptLog -Context $VhdPath
        }
        finally {
            'Releasing the mutex for the Install-WindowsFeature cmdlet''s DISM operation...' | Write-ScriptLog -Context $VhdPath
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
    throw 'The Install-WindowsFeature cmdlet execution for "{0}" was not succeeded in the acceptable time ({1}).' -f $VhdPath, $RetyTimeout.ToString()
}

function WaitingForStartingVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 5,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 30)
    )

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
        try {
            # NOTE: In sometimes, we need retry to waiting for unmount the VHD.
            $params = @{
                Name        = $VMName
                Passthru    = $true
                ErrorAction = [Management.Automation.ActionPreference]::Stop
            }
            if ((Start-VM @params) -ne $null) {
                'The VM was started.' | Write-ScriptLog -Context $VMName
                return
            }
        }
        catch {
            'Will retry start the VM...' +
                '(ExceptionMessage: {0} | Exception: {1} | FullyQualifiedErrorId: {2} | CategoryInfo: {3} | ErrorDetailsMessage: {4})' -f
                $_.Exception.Message, $_.Exception.GetType().FullName, $_.FullyQualifiedErrorId, $_.CategoryInfo.ToString(), $_.ErrorDetails.Message |
                Write-ScriptLog -Context $VMName
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
    throw 'The VM "{0}" was not start in the acceptable time ({1}).' -f $VMName, $RetyTimeout.ToString()
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
        [int] $RetryIntervalSeconds = 5,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 30)
    )

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
        try {
            $params = @{
                VMName      = $VMName
                Credential  = $Credential
                ScriptBlock = { 'ready' }
                ErrorAction = [Management.Automation.ActionPreference]::Stop
            }
            if ((Invoke-Command @params) -eq 'ready') {
                'The VM is ready.' | Write-ScriptLog -Context $VMName
                return
            }
        }
        catch {
            'Probing the VM ready state... ' +
                '(ExceptionMessage: {0} | Exception: {1} | FullyQualifiedErrorId: {2} | CategoryInfo: {3} | ErrorDetailsMessage: {4})' -f
                $_.Exception.Message, $_.Exception.GetType().FullName, $_.FullyQualifiedErrorId, $_.CategoryInfo.ToString(), $_.ErrorDetails.Message |
                Write-ScriptLog -Context $VMName
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
    throw 'The VM "{0}" was not ready in the acceptable time ({1}).' -f $VMName, $RetyTimeout.ToString()
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
        [ValidateRange(0, 1000)]
        [int] $RetryLimit = 50,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $SleepSeconds = 5
    )

    for ($retryCount = 0; $retryCount -lt $RetryLimit; $retryCount++) {
        try {
            $params = @{
                VMName       = $AddsDcVMName
                Credential   = $Credential
                ArgumentList = $AddsDcComputerName
                ScriptBlock  = {
                    $dcComputerName = $args[0]
                    (Get-ADDomainController -Server $dcComputerName).Enabled
                }
                ErrorAction  = [Management.Automation.ActionPreference]::Stop
            }
            if ((Invoke-Command @params) -eq $true) { return }
        }
        catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
            # FullyQualifiedErrorId: 2100,PSSessionStateBroken
            # The background process reported an error with the following message: "The Hyper-V socket target process has ended.".
            (
                'Restart the AD DS DC VM due to PowerShell Remoting transport exception.' + "`n" +
                'Exception: {0}' + "`n" +
                'FullyQualifiedErrorId: {1}' + "`n" +
                'CategoryInfo: {2}' + "`n" +
                'Message: {3}'
            ) -f @(
                $Error[0].Exception.GetType().FullName
                $Error[0].FullyQualifiedErrorId
                $Error[0].CategoryInfo.ToString()
                $Error[0].ErrorDetails.Message
            ) | Write-ScriptLog -Context $AddsDcVMName

            'Stopping the AD DS DC VM...' | Write-ScriptLog -Context $AddsDcVMName
            Stop-VM -Name $AddsDcVMName

            'Starting the AD DS DC VM...' | Write-ScriptLog -Context $AddsDcVMName
            Start-VM -Name $AddsDcVMName

            Start-Sleep -Seconds $SleepSeconds
        }
        catch {
            'Waiting for ready to AD DS DC VM "{0}"...' -f $AddsDcVMName | Write-ScriptLog -Context $AddsDcVMName
            Start-Sleep -Seconds $SleepSeconds
        }
    }
    throw 'The AD DS DC VM "{0}" was not ready in the acceptable time.' -f $AddsDcVMName
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
        [PSCredential] $DomainAdminCredential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1000)]
        [int] $RetryLimit = 50,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $SleepSeconds = 5
    )

    'Joining the VM "{0}" to the AD domain "{1}"...' -f $VMName, $DomainFqdn | Write-ScriptLog -Context $VMName

    for ($retryCount = 0; $retryCount -lt $RetryLimit; $retryCount++) {
        try {
            $params = @{
                VMName       = $VMName
                Credential   = $LocalAdminCredential
                ArgumentList = $DomainFqdn, $DomainAdminCredential
                ScriptBlock  = {
                    $domainFqdn = $args[0]
                    $domainAdminCredential = $args[1]
                    # NOTE: Domain joining will fail sometimes due to AD DS DC VM state.
                    Add-Computer -DomainName $domainFqdn -Credential $domainAdminCredential
                }
                ErrorAction  = [Management.Automation.ActionPreference]::Stop
            }
            Invoke-Command @params
            return
        }
        catch {
            'Will retry join the VM "{0}" to the AD domain "{1}"...' -f $VMName, $DomainFqdn | Write-ScriptLog -Context $VMName
            Start-Sleep -Seconds $SleepSeconds
        }
    }
    throw 'Failed join the VM "{0}" to the AD domain "{1}".' -f $VMName, $DomainFqdn
}

$exportFunctions = @(
    'Start-ScriptLogging',
    'Stop-ScriptLogging',
    'Write-ScriptLog',
    'Get-LabDeploymentConfig',
    'GetSecret',
    'DownloadFile',
    'GetIsoFileName',
    'GetBaseVhdFileName',
    'GetHciNodeVMName',
    'GetUnattendAnswerFileContent',
    'InjectUnattendAnswerFile',
    'Install-WindowsFeatureToVhd',
    'WaitingForStartingVM',
    'WaitingForReadyToVM',
    'WaitingForReadyToAddsDcVM',
    'CreateDomainCredential',
    'JoinVMToADDomain'
)
Export-ModuleMember -Function $exportFunctions
