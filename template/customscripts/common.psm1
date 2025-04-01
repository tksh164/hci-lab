Add-Type -Language CSharp -TypeDefinition @'
using System;

namespace HciLab
{
    public static class OSSku
    {
        // Operating system symbols.
        public const string WindowsServer2022 = "ws2022";
        public const string WindowsServer2025 = "ws2025";
        public const string AzureStackHci20H2 = "ashci20h2";
        public const string AzureStackHci21H2 = "ashci21h2";
        public const string AzureStackHci22H2 = "ashci22h2";
        public const string AzureStackHci23H2 = "ashci23h2";

        // Azure Stack HCI's operating system symbols.
        public static string[] AzureStackHciSkus
        {
            get
            {
                return new string[] {
                    AzureStackHci20H2,
                    AzureStackHci21H2,
                    AzureStackHci22H2,
                    AzureStackHci23H2
                };
            }
        }
    }

    // Operating system's Windows image index.
    public enum OSImageIndex : int
    {
        AzureStackHci                 = 1,
        WSStandardServerCore          = 1,
        WSStandardDesktopExperience   = 2,
        WSDatacenterServerCore        = 3,
        WSDatacenterDesktopExperience = 4,
    }
}
'@

function New-ExceptionMessage
{
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $ex = $_.Exception
    $builder = New-Object -TypeName 'System.Text.StringBuilder'
    [void] $builder.AppendLine('')
    [void] $builder.AppendLine('******** SCRIPT EXCEPTION ********')
    [void] $builder.AppendLine($ex.Message)
    [void] $builder.AppendLine('')
    [void] $builder.AppendLine('Exception: ' + $ex.GetType().FullName)
    [void] $builder.AppendLine('FullyQualifiedErrorId: ' + $_.FullyQualifiedErrorId)
    [void] $builder.AppendLine('ErrorDetailsMessage: ' + $_.ErrorDetails.Message)
    [void] $builder.AppendLine('CategoryInfo: ' + $_.CategoryInfo.ToString())
    [void] $builder.AppendLine('StackTrace in PowerShell:')
    [void] $builder.AppendLine($_.ScriptStackTrace)

    [void] $builder.AppendLine('')
    [void] $builder.AppendLine('--- Exception ---')
    [void] $builder.AppendLine('Exception: ' + $ex.GetType().FullName)
    [void] $builder.AppendLine('Message: ' + $ex.Message)
    [void] $builder.AppendLine('Source: ' + $ex.Source)
    [void] $builder.AppendLine('HResult: ' + $ex.HResult)
    [void] $builder.AppendLine('StackTrace:')
    [void] $builder.AppendLine($ex.StackTrace)

    $level = 1
    while ($ex.InnerException) {
        $ex = $ex.InnerException
        [void] $builder.AppendLine('--- InnerException {0} ---' -f $level)
        [void] $builder.AppendLine('Exception: ' + $ex.GetType().FullName)
        [void] $builder.AppendLine('Message: ' + $ex.Message)
        [void] $builder.AppendLine('Source: ' + $ex.Source)
        [void] $builder.AppendLine('HResult: ' + $ex.HResult)
        [void] $builder.AppendLine('StackTrace:')
        [void] $builder.AppendLine($ex.StackTrace)
        $level++
    }

    [void] $builder.AppendLine('**********************************')
    return $builder.ToString()
}

function Start-ScriptLogging
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $OutputDirectory,

        # The log file name suffix. The default value is the file name without extension of the caller script.
        [Parameter(Mandatory = $false)]
        [string] $FileName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
    )

    if (-not (Test-Path -PathType Container -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force
    }

    $transcriptFileName = New-LogFileName -FileName $FileName
    $transcriptFilePath = [IO.Path]::Combine($OutputDirectory, $transcriptFileName)
    Start-Transcript -LiteralPath $transcriptFilePath -Append -IncludeInvocationHeader
}

function Stop-ScriptLogging
{
    [CmdletBinding()]
    param ()

    Stop-Transcript
}

function New-LogFileName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string] $FileName
    )

    return '{0:yyyyMMdd-HHmmss}_{1}_{2}.log' -f [DateTime]::Now, $env:ComputerName, $FileName
}

# The script log default context.
$script:scriptLogDefaultConext = ''

function Set-ScriptLogDefaultContext
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $LogContext
    )

    $script:scriptLogDefaultConext = $LogContext
}

function Write-ScriptLog
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string] $Level = 'Info',

        [Parameter(Mandatory = $false)]
        [string] $LogContext
    )

    $timestamp = '{0:yyyy-MM-dd HH:mm:ss}' -f [DateTime]::Now
    $computerName = $env:ComputerName.ToLower()
    $context = if ($PSBoundParameters.ContainsKey('LogContext')) {
        '[{0}][{1}]' -f $computerName, $LogContext
    }
    elseif (-not [string]::IsNullOrEmpty($script:scriptLogDefaultConext)) {
        '[{0}][{1}]' -f $computerName, $script:scriptLogDefaultConext
    }
    else {
        '[{0}]' -f $computerName
    }
    $logRecord = '{0} {1,-7} {2} {3}' -f $timestamp, $Level.ToUpper(), $context, $Message
    Write-Host -Object $logRecord -ForegroundColor Cyan
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
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedUserData)) | ConvertFrom-Json
}

function Get-Secret
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $KeyVaultName,

        [Parameter(Mandatory = $true)]
        [string] $SecretName,

        [Parameter(Mandatory = $false)]
        [switch] $AsPlainText
    )

    'Get a secret value of the {0} from the {1}.' -f $SecretName, $KeyVaultName | Write-ScriptLog

    $attemptLimit = 10
    for ($attempts = 0; $attempts -lt $attemptLimit; $attempts++) {
        try {
            # Get a token for Key Vault using VM's managed identity via Azure Instance Metadata Service.
            $accessToken = Get-AccessTokenUsingManagedId -Resource 'https%3A%2F%2Fvault.azure.net'

            # Get a secret value from the Key Vault resource.
            $params = @{
                Method  = 'Get'
                Uri     = ('https://{0}.vault.azure.net/secrets/{1}?api-version=7.3' -f $KeyVaultName, $SecretName)
                Headers = @{
                    Authorization = ('Bearer {0}' -f $accessToken)
                }
            }
            $secretValue = (Invoke-RestMethod @params).value

            if ($AsPlainText) {
                return $secretValue
            }
            return ConvertTo-SecureString -String $secretValue -AsPlainText -Force
        }
        catch [System.Net.WebException] {
            # Handle the "AKV10046: Unable to resolve the key used for signature validation." exception.
            if ($_.ErrorDetails.Message -like '*AKV10046*') {
                ('Will retry get the secret due to unable to retrieve the value of {0} from {1}: {2}' -f $SecretName, $KeyVaultName, $_.ErrorDetails.Message) | Write-ScriptLog -Level Warning
                Start-Sleep -Seconds 1
            }
            else {
                throw $_
            }
        }
    }

    throw 'Could not get a secret value from the Key Vault.'
}

function Get-AccessTokenUsingManagedId
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Resource
    )

    $retryLimit = 10
    for ($retryCount = 0; $retryCount -lt $retryLimit; $retryCount++) {
        try {
            # Get a token for Key Vault using VM's managed identity via Azure Instance Metadata Service.
            $params = @{
                Method  = 'Get'
                Uri     = ('http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-12-13&resource={0}' -f $Resource)
                Headers = @{
                    Metadata = 'true'
                }
            }
            return (Invoke-RestMethod @params).access_token
        }
        catch {
            # Common error codes when using IMDS to retrieve load balancer information
            # https://learn.microsoft.com/en-us/azure/load-balancer/troubleshoot-load-balancer-imds
            $httpStatusCode = [int]($_.Exception.Response.StatusCode)
            if ($httpStatusCode -eq 429) {
                ('/metadata/identity/oauth2/token: TooManyRequests: {0}' -f $_.ErrorDetails.Message) | Write-ScriptLog -Level Warning
                Start-Sleep -Seconds 1
            }
            else {
                throw $_
            }
        }
    }

    throw 'Could not get an access token from the Azure Instance Metadata Service endpoint.'
}

function Get-InstanceMetadata
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateScript({ $_.StartsWith('/') })]
        [string] $FilterPath = '',

        [Parameter(Mandatory = $false)]
        [switch] $LeafNode
    )

    $queryFormat = if ($LeafNode) { 'text' } else { 'json' }

    $retryLimit = 10
    for ($retryCount = 0; $retryCount -lt $retryLimit; $retryCount++) {
        try {
            $params = @{
                Method  = 'Get'
                Uri     = 'http://169.254.169.254/metadata/instance' + $FilterPath + '?api-version=2021-02-01&format=' + $queryFormat
                Headers = @{
                    Metadata = 'true'
                }
                UseBasicParsing = $true
            }
            return Invoke-RestMethod @params
        }
        catch {
            # Common error codes when using IMDS to retrieve load balancer information
            # https://learn.microsoft.com/en-us/azure/load-balancer/troubleshoot-load-balancer-imds
            $httpStatusCode = [int]($_.Exception.Response.StatusCode)
            if ($httpStatusCode -eq 429) {
                ('/metadata/instance: TooManyRequests: {0}' -f $_.ErrorDetails.Message) | Write-ScriptLog -Level Warning
                Start-Sleep -Seconds 1
            }
            else {
                throw $_
            }
        }
    }

    throw 'Could not get an instance medata from the Azure Instance Metadata Service endpoint.'
}

function Invoke-FileDownload
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
            'Donwload the file to "{0}" from "{1}".' -f $destinationFilePath, $SourceUri | Write-ScriptLog
            Start-BitsTransfer -Source $SourceUri -Destination $destinationFilePath
            return Get-Item -LiteralPath $destinationFilePath
        }
        catch {
            '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                'Will retry the download...',
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning

            if (Test-Path -PathType Leaf -LiteralPath $destinationFilePath) {
                Remove-Item -LiteralPath $destinationFilePath -Force -ErrorAction Continue
            }
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
    throw 'The download from "{0}" did not succeed in the acceptable retry count ({1}).' -f $SourceUri, $MaxRetryCount
}

function New-RegistryKey
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ParentPath,

        [Parameter(Mandatory = $true)]
        [string] $KeyName
    )

    $path = [IO.Path]::Combine($ParentPath, $KeyName)
    if ((Get-Item -LiteralPath $path -ErrorAction SilentlyContinue) -eq $null) {
        New-Item -ItemType Directory -Path $ParentPath -Name $KeyName
    }
}

function Format-IsoFileName
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
        return '{0}_{1}_{2}.iso' -f $OperatingSystem, $Culture, $Suffix
    }
    return '{0}_{1}.iso' -f $OperatingSystem, $Culture
}

function Format-BaseVhdFileName
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

    return '{0}_{1}_{2}.vhdx' -f $OperatingSystem, $ImageIndex, $Culture
}

function Format-HciNodeName
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

    return $Format -f ($Offset + $Index)
}

function New-UnattendAnswerFileContent
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ComputerName,

        [Parameter(Mandatory = $true)]
        [securestring] $Password,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $true)]
        [string] $TimeZone
    )

    # Convert an admin password to the unattend file format.
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
            <TimeZone>{2}</TimeZone>
        </component>
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>{3}</InputLocale>
            <SystemLocale>{3}</SystemLocale>
            <UILanguage>{3}</UILanguage>
            <UserLocale>{3}</UserLocale>
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
'@ -f $encodedAdminPassword, $ComputerName, $TimeZone, $Culture
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

    while ((Get-WindowsImage -Mounted | Where-Object -Property 'ImagePath' -EQ -Value $VhdPath) -ne $null) {
        'Wait for the VHD dismount completion...' | Write-ScriptLog -LogContext $VhdPath
        Start-Sleep -Seconds $ProbeIntervalSeconds
    }
}

function Set-UnattendAnswerFileToVhd
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

    'Mount the VHD.' | Write-ScriptLog -LogContext $VhdPath

    $vhdMountPath = [IO.Path]::Combine('C:\', $baseFolderName + '-mount')
    'vhdMountPath: "{0}"' -f $vhdMountPath | Write-ScriptLog -LogContext $VhdPath
    New-Item -ItemType Directory -Path $vhdMountPath -Force | Out-String | Write-ScriptLog -LogContext $VhdPath

    $scratchDirectory = [IO.Path]::Combine('C:\', $baseFolderName + '-scratch')
    'scratchDirectory: "{0}"' -f $scratchDirectory | Write-ScriptLog -LogContext $VhdPath
    New-Item -ItemType Directory -Path $scratchDirectory -Force | Out-String | Write-ScriptLog -LogContext $VhdPath

    $logPath = [IO.Path]::Combine($LogFolder, (New-LogFileName -FileName ('injectunattend-' + [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)))))
    'logPath: "{0}"' -f $logPath | Write-ScriptLog -LogContext $VhdPath
    Mount-WindowsImage -Path $vhdMountPath -Index 1 -ImagePath $VhdPath -ScratchDirectory $scratchDirectory -LogPath $logPath | Out-String | Write-ScriptLog -LogContext $VhdPath

    'Create the unattend answer file in the VHD.' | Write-ScriptLog -LogContext $VhdPath
    $pantherPath = [IO.Path]::Combine($vhdMountPath, 'Windows', 'Panther')
    New-Item -ItemType Directory -Path $pantherPath -Force | Out-String | Write-ScriptLog -LogContext $VhdPath
    Set-Content -Path ([IO.Path]::Combine($pantherPath, 'unattend.xml')) -Value $UnattendAnswerFileContent -Force
    'Create the unattend answer file in the VHD completed.' | Write-ScriptLog -LogContext $VhdPath

    'Dismount the VHD.' | Write-ScriptLog -LogContext $VhdPath
    Dismount-WindowsImage -Path $vhdMountPath -Save -ScratchDirectory $scratchDirectory -LogPath $logPath | Out-String | Write-ScriptLog -LogContext $VhdPath

    'Wait for the VHD dismount (MountPath: "{0}").' -f $vhdMountPath | Write-ScriptLog -LogContext $VhdPath
    WaitingForVhdDismount -VhdPath $VhdPath
    'The VHD dismount completed.' | Write-ScriptLog -LogContext $VhdPath

    'Remove the VHD mount path.' | Write-ScriptLog -LogContext $VhdPath
    Remove-Item $vhdMountPath -Force

    'Remove the scratch directory.' | Write-ScriptLog -LogContext $VhdPath
    Remove-Item $scratchDirectory -Force
}

function CreateWaitHandleForSerialization
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SyncEventName
    )

    $params = @{
        TypeName     = 'System.Threading.EventWaitHandle'
        ArgumentList = @(
            $true,
            [System.Threading.EventResetMode]::AutoReset,
            $SyncEventName
        )
    }
    return New-Object @params
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

        [Parameter(Mandatory = $false)]
        [switch] $IncludeManagementTools,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $LogFolder,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 15,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 30)
    )

    $logPath = [IO.Path]::Combine($LogFolder, (New-LogFileName -FileName ('installwinfeature-' + [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)))))
    'logPath: "{0}"' -f $logPath | Write-ScriptLog -LogContext $VhdPath

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
        # NOTE: Effort to prevent collision of concurrent DISM operations.
        $waitHandle = CreateWaitHandleForSerialization -SyncEventName 'Local\hcilab-install-windows-feature-to-vhd'
        'Wait for the turn to doing the Install-WindowsFeature cmdlet''s DISM operations.' | Write-ScriptLog -LogContext $VhdPath
        $waitHandle.WaitOne()
        'Acquired the turn to doing the Install-WindowsFeature cmdlet''s DISM operation.' | Write-ScriptLog -LogContext $VhdPath

        try {
            # NOTE: Install-WindowsFeature cmdlet will fail sometimes due to concurrent operations, etc.
            'Start Windows features installation to VHD.' | Write-ScriptLog -LogContext $VhdPath
            $params = @{
                Vhd                    = $VhdPath
                Name                   = $FeatureName
                IncludeManagementTools = $IncludeManagementTools
                LogPath                = $logPath
                ErrorAction            = [Management.Automation.ActionPreference]::Stop
            }
            Install-WindowsFeature @params | Out-String | Write-ScriptLog -LogContext $VhdPath

            # NOTE: The DISM mount point is still remain after the Install-WindowsFeature cmdlet completed.
            'Wait for VHD dismount completion by the Install-WindowsFeature cmdlet execution.' | Write-ScriptLog -LogContext $VhdPath
            WaitingForVhdDismount -VhdPath $VhdPath
            'The VHD dismount completed.' | Write-ScriptLog -LogContext $VhdPath

            'Windows features installation to VHD completed.' | Write-ScriptLog -LogContext $VhdPath
            return
        }
        catch {
            '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                'Thrown a exception by Install-WindowsFeature cmdlet execution. Will retry Install-WindowsFeature cmdlet...',
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning -LogContext $VhdPath
        }
        finally {
            'Releasing the turn to doing the Install-WindowsFeature cmdlet''s DISM operation.' | Write-ScriptLog -LogContext $VhdPath
            $waitHandle.Set()
            $waitHandle.Dispose()
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    throw 'The Install-WindowsFeature cmdlet execution for "{0}" was not succeeded in the acceptable time ({1}).' -f $VhdPath, $RetyTimeout.ToString()
}

function Start-VMWithRetry
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 15,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 30)
    )

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
        try {
            $params = @{
                Name        = $VMName
                Passthru    = $true
                ErrorAction = [Management.Automation.ActionPreference]::Stop
            }
            if ((Start-VM @params) -ne $null) {
                'The VM was started.' | Write-ScriptLog
                return
            }
        }
        catch {
            # NOTE: In sometimes, we need retry to waiting for unmount the VHD.
            '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                'Will retry start the VM...',
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    throw 'The VM "{0}" was not start in the acceptable time ({1}).' -f $VMName, $RetyTimeout.ToString()
}

function Wait-PowerShellDirectReady
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 15,

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
                'PowerShell Direct is ready on the VM.' | Write-ScriptLog
                return
            }
        }
        catch {
            '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                'Probing the VM ready state...',
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    throw 'The VM "{0}" was not ready in the acceptable time ({1}).' -f $VMName, $RetyTimeout.ToString()
}

# A sync event name for blocking the AD DS operations.
$script:addsDcDeploymentCompletionSyncEventName = 'Local\hcilab-adds-dc-deployment-completion'
$script:addsDcDeploymentCompletionWaitHandle = $null

function Block-AddsDomainOperation
{
    [CmdletBinding()]
    param ()

    'Block the AD DS domain operations until the AD DS domain controller VM deployment is completed.' | Write-ScriptLog
    $params = @{
        TypeName     = 'System.Threading.EventWaitHandle'
        ArgumentList = @(
            $false,
            [System.Threading.EventResetMode]::ManualReset,
            $script:addsDcDeploymentCompletionSyncEventName
        )
    }
    $script:addsDcDeploymentCompletionWaitHandle = New-Object @params
}

function Unblock-AddsDomainOperation
{
    [CmdletBinding()]
    param ()

    try {
        if ($script:addsDcDeploymentCompletionWaitHandle -eq $null) {
            throw 'The wait event handle for AD DS VM ready is not initialized.'
        }
        $script:addsDcDeploymentCompletionWaitHandle.Set()
        'Unblocked the AD DS domain operations. The AD DS domain controller VM has been deployed.' | Write-ScriptLog
    }
    finally {
        $script:addsDcDeploymentCompletionWaitHandle.Dispose()
    }
}

function Wait-AddsDcDeploymentCompletion
{
    [CmdletBinding()]
    param ()

    $waitHandle = $null
    if ([System.Threading.EventWaitHandle]::TryOpenExisting($script:addsDcDeploymentCompletionSyncEventName, [ref] $waitHandle)) {
        try {
            'Wait for the AD DS domain controller deployment completion.' | Write-ScriptLog
            $waitHandle.WaitOne()
            'The AD DS domain controller has been deployed.' | Write-ScriptLog
        }
        finally {
            $waitHandle.Dispose()
        }
    }
    else {
        'The AD DS domain controller is already deployed. (The wait handle did not exist)' | Write-ScriptLog
    }
}

function Wait-DomainControllerServiceReady
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
        [int] $RetryIntervalSeconds = 15,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 30)
    )

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
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
            if ((Invoke-Command @params) -eq $true) {
                'The AD DS domain controller is ready.' | Write-ScriptLog
                return
            }
        }
        catch {
            if ($_.FullyQualifiedErrorId -eq '2100,PSSessionStateBroken') {
                # NOTE: When this exception continued to happen, PowerShell Direct capability was never recovered until reboot the AD DS domain controller VM.
                # Exception: System.Management.Automation.Remoting.PSRemotingTransportException
                # FullyQualifiedErrorId: 2100,PSSessionStateBroken
                # The background process reported an error with the following message: "The Hyper-V socket target process has ended.".
                '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                    'Restart the AD DS domain controller VM due to PowerShell Remoting transport exception.',
                    $_.Exception.Message,
                    $_.Exception.GetType().FullName,
                    $_.FullyQualifiedErrorId,
                    $_.CategoryInfo.ToString(),
                    $_.ErrorDetails.Message
                ) | Write-ScriptLog -Level Warning

                $waitHandle = CreateWaitHandleForSerialization -SyncEventName 'Local\hcilab-adds-dc-vm-reboot'
                'Wait for the turn to doing the AD DS domain controller VM reboot.' | Write-ScriptLog
                $waitHandle.WaitOne()
                'Acquired the turn to doing the AD DS domain controller VM reboot.' | Write-ScriptLog
    
                try {
                    $uptimeThresholdMinutes = 15
                    $addsDcVM = Get-VM -Name $AddsDcVMName
                    # NOTE: Skip rebooting if the VM is young because it means the VM already rebooted recently by other jobs.
                    if ($addsDcVM.UpTime -gt (New-TimeSpan -Minutes $uptimeThresholdMinutes)) {
                        'Stop the AD DS domain controller VM due to PowerShell Direct exception.' | Write-ScriptLog
                        Stop-VM -Name $AddsDcVMName -ErrorAction Continue
            
                        'Start the AD DS domain controller VM due to PowerShell Direct exception.' | Write-ScriptLog
                        Start-VM -Name $AddsDcVMName -ErrorAction Continue
                    }
                    else {
                        'Skip the AD DS domain controller VM rebooting because the VM''s uptime is too short (less than {0} minutes).' -f $uptimeThresholdMinutes | Write-ScriptLog
                    }
                }
                finally {
                    'Release the turn to doing the AD DS domain controller VM reboot.' | Write-ScriptLog
                    $waitHandle.Set()
                    $waitHandle.Dispose()
                }
            }
            else {
                '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                    'Probing AD DS domain controller ready state...',
                    $_.Exception.Message,
                    $_.Exception.GetType().FullName,
                    $_.FullyQualifiedErrorId,
                    $_.CategoryInfo.ToString(),
                    $_.ErrorDetails.Message
                ) | Write-ScriptLog -Level Warning
            }
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    throw 'The AD DS domain controller "{0}" was not ready in the acceptable time ({1}).' -f $AddsDcVMName, $RetyTimeout.ToString()
}

function New-LogonCredential
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
    return New-Object @params
}

function Add-VMToADDomain
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
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 15,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 30)
    )

    'Join the "{0}" VM to the AD domain "{1}".' -f $VMName, $DomainFqdn | Write-ScriptLog

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
        try {
            # NOTE: Domain joining will fail sometimes due to AD DS domain controller VM state.
            $params = @{
                VMName       = $VMName
                Credential   = $LocalAdminCredential
                ArgumentList = $DomainFqdn, $DomainAdminCredential
                ScriptBlock  = {
                    $domainFqdn = $args[0]
                    $domainAdminCredential = $args[1]
                    Add-Computer -DomainName $domainFqdn -Credential $domainAdminCredential
                }
                ErrorAction  = [Management.Automation.ActionPreference]::Stop
            }
            Invoke-Command @params
            'Join the "{0}" VM to the AD domain "{1}" completed.' -f $VMName, $DomainFqdn | Write-ScriptLog
            return
        }
        catch {
            '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                ('Will retry join the VM "{0}" to the AD domain "{1}"... ' -f $VMName, $DomainFqdn),
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    throw 'Domain join the "{0}" VM to the AD domain "{1}" was not complete in the acceptable time ({2}).' -f $VMName, $DomainFqdn, $RetyTimeout.ToString()
}

function Copy-PSModuleIntoVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [string] $ModuleFilePathToCopy
    )

    'Copy the PowerShell module from "{0}" on the lab host into the VM "{1}".' -f $ModuleFilePathToCopy, $Session.VMName | Write-ScriptLog
    $commonModuleFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($ModuleFilePathToCopy))
    Copy-Item -ToSession $Session -Path $ModuleFilePathToCopy -Destination $commonModuleFilePathInVM
    'Copy the PowerShell module from "{0}" on the lab host to "{1}" on the VM "{2}" completed.' -f $ModuleFilePathToCopy, $commonModuleFilePathInVM, $Session.VMName | Write-ScriptLog
    return $commonModuleFilePathInVM
}

function Invoke-PSDirectSessionSetup
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession[]] $Session,

        [Parameter(Mandatory = $true)]
        [string] $CommonModuleFilePathInVM
    )

    $params = @{
        InputObject = [PSCustomObject] @{
            CommonModuleFilePath = $CommonModuleFilePathInVM
        }
    }
    Invoke-Command @params -Session $Session -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $CommonModuleFilePath
        )
    
        $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
        $WarningPreference = [Management.Automation.ActionPreference]::Continue
        $VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
        Import-Module -Name $CommonModuleFilePath -Force
    }
}

function Invoke-PSDirectSessionCleanup
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession[]] $Session,

        [Parameter(Mandatory = $true)]
        [string] $CommonModuleFilePathInVM
    )

    $params = @{
        InputObject = [PSCustomObject] @{
            CommonModuleFilePath = $CommonModuleFilePathInVM
        }
    }
    Invoke-Command @params -Session $Session -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $CommonModuleFilePath
        )
    
        'Delete the common module file "{0}" on the VM "{1}".' -f $CommonModuleFilePath, $env:ComputerName | Write-ScriptLog
        Remove-Item -LiteralPath $CommonModuleFilePath -Force
        'Delete the common module file "{0}" on the VM "{1}" completed.' -f $CommonModuleFilePath, $env:ComputerName | Write-ScriptLog
    } | Out-String | Write-ScriptLog
        
    'Delete PowerShell Direct sessions.' | Write-ScriptLog
    $Session | Remove-PSSession
    'Delete PowerShell Direct sessions completed.' | Write-ScriptLog
}

function New-ShortcutFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ShortcutFilePath,

        [Parameter(Mandatory = $true)]
        [string] $TargetPath,

        [Parameter(Mandatory = $false)]
        [string] $Arguments,

        [Parameter(Mandatory = $false)]
        [string] $Description,

        [Parameter(Mandatory = $false)]
        [string] $IconLocation
    )

    $wshShell = New-Object -ComObject 'WScript.Shell' -Property $properties
    $shortcut = $wshShell.CreateShortcut($ShortcutFilePath)
    $shortcut.TargetPath = $TargetPath
    if ($PSBoundParameters.ContainsKey('Arguments')) { $shortcut.Arguments = $Arguments }
    if ($PSBoundParameters.ContainsKey('Description')) { $shortcut.Description = $Description }
    if ($PSBoundParameters.ContainsKey('IconLocation')) { $shortcut.IconLocation = $IconLocation }
    $shortcut.Save()
}

function New-WacConnectionFileEntry
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('msft.sme.connection-type.server', 'msft.sme.connection-type.cluster')]
        [string] $Type,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Tag = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $GroupId = ''
    )

    $entry = @{
        Name = $Name
        Type = $Type
        Tags = $Tag -join '|'
        GroupId = $GroupId
    }
    return [PSCustomObject] $entry
}

function New-WacConnectionFileContent
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $ConnectionEntry
    )

    $builder = New-Object -TypeName 'System.Text.StringBuilder'
    [void] $builder.AppendLine('"name","type","tags","groupId"')
    foreach ($entry in $ConnectionEntry) {
        $values = @(
            ('"' + $entry.Name + '"'),
            ('"' + $entry.Type + '"'),
            ('"' + $entry.Tags + '"'),
            ('"' + $entry.GroupId + '"')
        )
        [void] $builder.AppendLine($values -join ',')
    }
    return $builder.ToString()
}

$exportFunctions = @(
    'New-ExceptionMessage',
    'Start-ScriptLogging',
    'Stop-ScriptLogging',
    'Set-ScriptLogDefaultContext',
    'Write-ScriptLog',
    'Get-LabDeploymentConfig',
    'Get-Secret',
    'Get-InstanceMetadata',
    'Invoke-FileDownload',
    'New-RegistryKey',
    'Format-IsoFileName',
    'Format-BaseVhdFileName',
    'Format-HciNodeName',
    'New-UnattendAnswerFileContent',
    'Set-UnattendAnswerFileToVhd',
    'Install-WindowsFeatureToVhd',
    'Start-VMWithRetry',
    'Wait-PowerShellDirectReady',
    'Block-AddsDomainOperation',
    'Unblock-AddsDomainOperation',
    'Wait-AddsDcDeploymentCompletion',
    'Wait-DomainControllerServiceReady',
    'New-LogonCredential',
    'Add-VMToADDomain',
    'Copy-PSModuleIntoVM',
    'Invoke-PSDirectSessionSetup',
    'Invoke-PSDirectSessionCleanup',
    'New-ShortcutFile',
    'New-WacConnectionFileEntry',
    'New-WacConnectionFileContent'
)
Export-ModuleMember -Function $exportFunctions
