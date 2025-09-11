Add-Type -Language CSharp -TypeDefinition @'
using System;

namespace HciLab
{
    public static class OSSku
    {
        // Operating system symbols.
        public const string WindowsServer2022   = "ws2022";
        public const string WindowsServer2025   = "ws2025";
        public const string AzureStackHci20H2   = "ashci20h2";
        public const string AzureStackHci21H2   = "ashci21h2";
        public const string AzureStackHci22H2   = "ashci22h2";
        public const string AzureStackHci23H2   = "ashci23h2";  // Azure Local 23H2 2503
        public const string AzureLocal24H2_2504 = "azloc24h2_2504";
        public const string AzureLocal24H2_2505 = "azloc24h2_2505";
        public const string AzureLocal24H2_2506 = "azloc24h2_2506";
        public const string AzureLocal24H2_2507 = "azloc24h2_2507";
        public const string AzureLocal24H2_2508 = "azloc24h2_2508";

        // Azure Stack HCI's operating system symbols.
        public static string[] AzureStackHciSkus
        {
            get
            {
                return new string[] {
                    AzureStackHci20H2,
                    AzureStackHci21H2,
                    AzureStackHci22H2,
                    AzureStackHci23H2,
                    AzureLocal24H2_2504,
                    AzureLocal24H2_2505,
                    AzureLocal24H2_2506,
                    AzureLocal24H2_2507,
                    AzureLocal24H2_2508
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
        [System.Management.Automation.ErrorRecord] $ErrorRecord,

        [Parameter(Mandatory = $false)]
        [switch] $AsHandled
    )

    $headerText = 'UNHANDLED EXCEPTION'
    $fenceChar = '#'
    $horizontalLineLength = 42

    if ($AsHandled) {
        $headerText = 'Handled Exception'
        $fenceChar = '='
    }

    $ex = $ErrorRecord.Exception
    $builder = New-Object -TypeName 'System.Text.StringBuilder'
    [void] $builder.AppendLine('')
    [void] $builder.AppendLine($fenceChar * $horizontalLineLength)
    [void] $builder.AppendLine($headerText)
    [void] $builder.AppendLine('-' * $horizontalLineLength)
    [void] $builder.AppendLine($ex.Message)
    [void] $builder.AppendLine('')
    [void] $builder.AppendLine('Exception             : ' + $ex.GetType().FullName)
    [void] $builder.AppendLine('FullyQualifiedErrorId : ' + $ErrorRecord.FullyQualifiedErrorId)
    [void] $builder.AppendLine('ErrorDetailsMessage   : ' + $ErrorRecord.ErrorDetails.Message)
    [void] $builder.AppendLine('CategoryInfo          : ' + $ErrorRecord.CategoryInfo.ToString())
    [void] $builder.AppendLine('StackTrace            :')
    [void] $builder.AppendLine($ErrorRecord.ScriptStackTrace)

    [void] $builder.AppendLine('')
    [void] $builder.AppendLine('-------- Exception --------')
    [void] $builder.AppendLine('Exception  : ' + $ex.GetType().FullName)
    [void] $builder.AppendLine('Message    : ' + $ex.Message)
    [void] $builder.AppendLine('Source     : ' + $ex.Source)
    [void] $builder.AppendLine('HResult    : ' + $ex.HResult)
    [void] $builder.AppendLine('StackTrace :')
    [void] $builder.AppendLine($ex.StackTrace)

    $depth = 1
    while ($ex.InnerException) {
        $ex = $ex.InnerException
        [void] $builder.AppendLine('')
        [void] $builder.AppendLine('-------- InnerException {0} --------' -f $depth)
        [void] $builder.AppendLine('Exception  : ' + $ex.GetType().FullName)
        [void] $builder.AppendLine('Message    : ' + $ex.Message)
        [void] $builder.AppendLine('Source     : ' + $ex.Source)
        [void] $builder.AppendLine('HResult    : ' + $ex.HResult)
        [void] $builder.AppendLine('StackTrace :')
        [void] $builder.AppendLine($ex.StackTrace)
        $depth++
    }

    [void] $builder.AppendLine($fenceChar * $horizontalLineLength)
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

    'Get a secret value of the "{0}" from the "{1}".' -f $SecretName, $KeyVaultName | Write-ScriptLog

    $attemptLimit = 10
    for ($attempts = 0; $attempts -lt $attemptLimit; $attempts++) {
        try {
            # Get a token for Key Vault using VM's managed identity via Azure Instance Metadata Service.
            $accessToken = Get-AccessTokenUsingManagedId -Resource 'https%3A%2F%2Fvault.azure.net'

            # Get a secret value from the Key Vault resource.
            $params = @{
                Method  = 'Get'
                Uri     = ('https://{0}.vault.azure.net/secrets/{1}?api-version=7.4' -f $KeyVaultName, $SecretName)
                Headers = @{
                    Authorization = ('Bearer {0}' -f $accessToken)
                }
                #Verbose = $false
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
                #Verbose = $false
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
            'Download the file to "{0}" from "{1}".' -f $destinationFilePath, $SourceUri | Write-ScriptLog
            $params = @{
                FilePath     = 'C:\Windows\System32\curl.exe'
                ArgumentList = '--location --silent --fail --output {0} {1}' -f $destinationFilePath, $SourceUri
                PassThru     = $true
                Wait         = $true
                NoNewWindow  = $true
            }
            $proc = Start-Process @params

            if ($proc.ExitCode -ne 0) {
                throw 'The curl command failed with exit code {0} when downloading the file from {1}.' -f $proc.ExitCode, $SourceUri
            }

            # TODO: Compute file hash and verify
            # Get-FileHash -LiteralPath $destinationFilePath -Algorithm SHA256

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
        'Create a new registry key "{0}" under "{1}"' -f $KeyName, $ParentPath | Write-ScriptLog
        New-Item -ItemType Directory -Path $ParentPath -Name $KeyName | Out-String -Width 200 | Write-ScriptLog
        'Create a new registry key "{0}" under "{1}" completed.' -f $KeyName, $ParentPath | Write-ScriptLog
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

function Wait-VhdDismountCompletion
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $VhdPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $LogFolder,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $ProbeIntervalSeconds = 5
    )

    $logFilePath = [IO.Path]::Combine($LogFolder, (New-LogFileName -FileName ('waitvhddismount-' + [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)))))
    while ((Get-WindowsImage -Mounted -LogPath $logFilePath | Where-Object -Property 'ImagePath' -EQ -Value $VhdPath) -ne $null) {
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

    $logFilePath = [IO.Path]::Combine($LogFolder, (New-LogFileName -FileName ('injectunattend-' + [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)))))
    'LogFilePath: "{0}"' -f $logFilePath | Write-ScriptLog -LogContext $VhdPath
    Mount-WindowsImage -Path $vhdMountPath -Index 1 -ImagePath $VhdPath -ScratchDirectory $scratchDirectory -LogPath $logFilePath | Out-String | Write-ScriptLog -LogContext $VhdPath

    'Create the unattend answer file in the VHD.' | Write-ScriptLog -LogContext $VhdPath
    $pantherPath = [IO.Path]::Combine($vhdMountPath, 'Windows', 'Panther')
    New-Item -ItemType Directory -Path $pantherPath -Force | Out-String | Write-ScriptLog -LogContext $VhdPath
    Set-Content -Path ([IO.Path]::Combine($pantherPath, 'unattend.xml')) -Value $UnattendAnswerFileContent -Force
    'Create the unattend answer file in the VHD completed.' | Write-ScriptLog -LogContext $VhdPath

    'Dismount the VHD.' | Write-ScriptLog -LogContext $VhdPath
    Dismount-WindowsImage -Path $vhdMountPath -Save -ScratchDirectory $scratchDirectory -LogPath $logFilePath | Out-String | Write-ScriptLog -LogContext $VhdPath

    'Wait for the VHD dismount (MountPath: "{0}").' -f $vhdMountPath | Write-ScriptLog -LogContext $VhdPath
    Wait-VhdDismountCompletion -VhdPath $VhdPath -LogFolder $LogFolder
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
        [TimeSpan] $RetryTimeout = (New-TimeSpan -Minutes 30)
    )

    $logFilePath = [IO.Path]::Combine($LogFolder, (New-LogFileName -FileName ('installwinfeature-' + [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetDirectoryName($VhdPath)))))
    'LogFilePath: "{0}"' -f $logFilePath | Write-ScriptLog -LogContext $VhdPath

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetryTimeout)) {
        # NOTE: Effort to prevent collision of concurrent DISM operations.
        $waitHandle = CreateWaitHandleForSerialization -SyncEventName 'Local\hcilab-install-windows-feature-to-vhd'
        'Wait for the turn to doing the Install-WindowsFeature cmdlet''s DISM operations.' | Write-ScriptLog -LogContext $VhdPath
        [void] $waitHandle.WaitOne()
        'Acquired the turn to doing the Install-WindowsFeature cmdlet''s DISM operation.' | Write-ScriptLog -LogContext $VhdPath

        try {
            # NOTE: Install-WindowsFeature cmdlet will fail sometimes due to concurrent operations, etc.
            'Start Windows features installation to the VHD.' | Write-ScriptLog -LogContext $VhdPath
            $params = @{
                Vhd                    = $VhdPath
                Name                   = $FeatureName
                IncludeManagementTools = $IncludeManagementTools
                LogPath                = $logFilePath
                ErrorAction            = [Management.Automation.ActionPreference]::Stop
                #Verbose                = $false
            }
            Install-WindowsFeature @params | Format-List -Property @(
                'Success',
                'RestartNeeded',
                'ExitCode',
                'FeatureResult'
            ) | Out-String -Width 500 | Write-ScriptLog -LogContext $VhdPath

            # NOTE: The DISM mount point is still remain after the Install-WindowsFeature cmdlet completed.
            'Wait for VHD dismount completion by the Install-WindowsFeature cmdlet execution.' | Write-ScriptLog -LogContext $VhdPath
            Wait-VhdDismountCompletion -VhdPath $VhdPath -LogFolder $LogFolder
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
            [void] $waitHandle.Set()
            $waitHandle.Dispose()
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    throw 'The Install-WindowsFeature cmdlet execution for "{0}" was not succeeded in the acceptable time ({1}).' -f $VhdPath, $RetryTimeout.ToString()
}

function Start-VMSurely
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $AttemptDuration = (New-TimeSpan -Minutes 5),

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $AttemptIntervalSeconds = 5
    )

    # Start the VM.
    $isVMStarted = $false
    $vmStartTime = Get-Date
    while ((Get-Date) -lt ($vmStartTime + $AttemptDuration)) {
        try {
            'Start the VM "{0}".' -f $VMName | Write-ScriptLog
            $vm = Start-VM -Name $VMName -Passthru -ErrorAction Stop
            if ($vm -ne $null) {
                'The VM "{0}" is started.' -f $VMName | Write-ScriptLog
                $isVMStarted = $true
                break
            }
        }
        catch {
            # NOTE: In sometimes, we need retry to waiting for unmount the VHD.
            New-ExceptionMessage -ErrorRecord $_ -AsHandled | Write-ScriptLog -Level Warning
            Start-Sleep -Seconds $AttemptIntervalSeconds
        }
    }

    if (-not $isVMStarted) {
        $exceptionMessage = 'The VM "{0}" was not start in the acceptable time ({1}).' -f $VMName, $AttemptDuration.ToString('hh\:mm\:ss')
        $exceptionMessage | Write-ScriptLog -Level Error
        throw $exceptionMessage
    }

    # Wait for the VM heartbeat service ready.
    $heartbeatProbingStartTime = Get-Date
    while ((Get-Date) -lt ($heartbeatProbingStartTime + $AttemptDuration)) {
        $heartbeatVmis = Get-VMIntegrationService -VMName $VMName -Name 'Heartbeat'
        if ($heartbeatVmis.PrimaryOperationalStatus -eq 'Ok') {
            'The heartbeat service on the VM "{0}" is ready.' -f $VMName | Write-ScriptLog
            return
        }
        'The heartbeat service on the VM "{0}" is not ready yet.' -f $VMName | Write-ScriptLog
        Start-Sleep -Seconds $AttemptIntervalSeconds
    }

    $exceptionMessage = 'The heartbeat service on the VM "{0}" was not ready in the acceptable time ({1}).' -f $VMName, $AttemptDuration.ToString('hh\:mm\:ss')
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}

function Stop-VMSurely
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $false)]
        [TimeSpan] $AttemptDuration = (New-TimeSpan -Minutes 5),

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $AttemptIntervalSeconds = 5
    )

    'Stop the VM "{0}".' -f $VMName | Write-ScriptLog
    $isStopVMInitiated = $false
    $isGuestOsRebooted = $false
    $attemptStopVMStartTime = Get-Date
    while ((Get-Date) -lt ($attemptStopVMStartTime + $AttemptDuration)) {
        try {
            Stop-VM -Name $VMName
            'Stop the VM "{0}" was initiated.' -f $VMName | Write-ScriptLog
            $isStopVMInitiated = $true
            break
        }
        catch {
            New-ExceptionMessage -ErrorRecord $_ -AsHandled | Write-ScriptLog -Level Warning

            # A system shutdown has already been scheduled.
            if (($_.Exception -is [Microsoft.HyperV.PowerShell.VirtualizationException]) -and ($_.Exception.Message -like '*0x800704a6*')) {
                'A system shutdown has already been scheduled.' -f $VMName | Write-ScriptLog
                $isGuestOsRebooted = $true
                $isStopVMInitiated = $true
                break
            }
        }
        Start-Sleep -Seconds $AttemptIntervalSeconds

        # catch [Microsoft.HyperV.PowerShell.VirtualizationException] {
        #     # A system shutdown has already been scheduled.
        #     if ($_.Exception.Message -like '*0x800704a6*') {
        #         New-ExceptionMessage -ErrorRecord $_ -AsHandled | Write-ScriptLog -Level Warning
        #         Start-Sleep -Seconds $AttemptIntervalSeconds
        #     }
        #     else {
        #         throw $_
        #     }
        # }
    }

    if (-not $isStopVMInitiated) {
        $exceptionMessage = 'Stop the VM "{0}" could not initiated in the acceptable time ({1}).' -f $VMName, $AttemptDuration.ToString('hh\:mm\:ss')
        $exceptionMessage | Write-ScriptLog -Level Error
        throw $exceptionMessage
    }

    # Wait for the VM to turn off.
    $turnOffProbingStartTime = Get-Date
    while ((Get-Date) -lt ($turnOffProbingStartTime + $AttemptDuration)) {
        # Check the VM was turned off.
        $vm = Get-VM -VMName $VMName
        if ($vm.State -eq 'Off') {
            'The VM "{0}" is stopped.' -f $VMName | Write-ScriptLog
            return
        }

        # Check the VM is rebooted if the guest OS is rebooted instead of turning off.
        if ($isGuestOsRebooted) {
            $heartbeatVmis = Get-VMIntegrationService -VMName $VMName -Name 'Heartbeat'
            if ($heartbeatVmis.PrimaryOperationalStatus -ne 'Ok') {
                'The heartbeat service on the VM "{0}" is not available. It seems rebooted.' -f $VMName | Write-ScriptLog
                return
            }
        }

        'The VM "{0}" is "{1}". Wait for the VM "{0}" to stop.' -f $VMName, $vm.State | Write-ScriptLog
        Start-Sleep -Seconds $AttemptIntervalSeconds
    }

    $exceptionMessage = 'The VM "{0}" was not stopped in the acceptable time ({1}).' -f $VMName, $AttemptDuration.ToString('hh\:mm\:ss')
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
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
        [TimeSpan] $RetryTimeout = (New-TimeSpan -Minutes 30)
    )

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetryTimeout)) {
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
                'Probing PowerShell Direct ready state...',
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    throw 'PowerShell Direct did not ready on the VM "{0}" in the acceptable time ({1}).' -f $VMName, $RetryTimeout.ToString()
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
        [TimeSpan] $RetryTimeout = (New-TimeSpan -Minutes 30)
    )

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetryTimeout)) {
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

    throw 'The AD DS domain controller "{0}" was not ready in the acceptable time ({1}).' -f $AddsDcVMName, $RetryTimeout.ToString()
}

function New-LogonCredential
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $DomainFqdn,

        [Parameter(Mandatory = $true)]
        [securestring] $Password,

        [Parameter(Mandatory = $false)]
        [string] $UserName = 'Administrator'
    )

    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = @(
            if ($DomainFqdn -eq '') { $UserName } else { '{0}\{1}' -f $DomainFqdn, $UserName },
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
        [TimeSpan] $RetryTimeout = (New-TimeSpan -Minutes 30)
    )

    'Join the "{0}" VM to the AD domain "{1}".' -f $VMName, $DomainFqdn | Write-ScriptLog

    $startTime = Get-Date
    while ((Get-Date) -lt ($startTime + $RetryTimeout)) {
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

    throw 'Domain join the "{0}" VM to the AD domain "{1}" was not complete in the acceptable time ({2}).' -f $VMName, $DomainFqdn, $RetryTimeout.ToString()
}

function New-PSDirectSession
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential
    )

    $attemptLimit = 5
    for ($attempts = 0; $attempts -lt $attemptLimit; $attempts++) {
        try {
            'Create a new PowerShell Direct session to "{0}" with "{1}".' -f $VMName, $Credential.UserName | Write-ScriptLog
            $pss = New-PSSession -VMName $VMName -Credential $Credential -Name ('"{0}" with "{1}"' -f $VMName, $Credential.UserName)
            'Create a new PowerShell Direct session to "{0}" with "{1}" succeeded.' -f $VMName, $Credential.UserName | Write-ScriptLog
            return $pss
        }
        catch {
            'Create a new PowerShell Direct session to "{0}" with "{1}" failed. It will retry.' -f $VMName, $Credential.UserName | Write-ScriptLog -Level Warning
            New-ExceptionMessage -ErrorRecord $_ -AsHandled | Write-ScriptLog -Level Warning
            Start-Sleep -Seconds 5
        }
    }

    $exceptionMessage = 'Create a new PowerShell Direct session to "{0}" with "{1}" failed {2} times.' -f $VMName, $Credential.UserName, $attemptLimit
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}

function Remove-PSDirectSession
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session
    )

    'Delete a PowerShell Direct session to {0}.' -f $Session.Name | Write-ScriptLog
    Remove-PSSession -Session $Session
    'Delete a PowerShell Direct session to {0} succeeded.' -f $Session.Name | Write-ScriptLog
}

function Invoke-PSDirectSessionGroundwork
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $false)]
        [string[]] $ImportModuleInVM = @()
    )

    $params = @{
        Session      = $Session
        ArgumentList = $ImportModuleInVM
    }
    Invoke-Command @params -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string[]] $ImportModuleInVM
        )
    
        $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
        $WarningPreference = [Management.Automation.ActionPreference]::Continue
        $VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $DebugPreference = [Management.Automation.ActionPreference]::SilentlyContinue
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

        # Import the modules.
        if ($ImportModuleInVM.Length -ne 0) {
            Import-Module -Name $ImportModuleInVM -Force
        }
    }
}

function Copy-FileIntoVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $true)]
        [string[]] $SourceFilePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPathInVM
    )

    try {
        $pss = New-PSDirectSession -VMName $VMName -Credential $Credential

        # Copy files into the VM one by one to traceability when raise exception.
        $filePathsInVM = @()
        $filePathsInVM += foreach ($filePath in $SourceFilePath) {
            $filePathInVM = [IO.Path]::Combine($DestinationPathInVM, [IO.Path]::GetFileName($filePath))
            'Copy from the "{0}" on the lab host to the "{1}" in the VM "{2}".' -f $filePath, $filePathInVM, $pss.VMName | Write-ScriptLog
            # The destination file will be overwritten if it already exists.
            Copy-Item -ToSession $pss -LiteralPath $filePath -Destination $filePathInVM
            'Copy from the "{0}" on the lab host to the "{1}" in the VM "{2}" succeeded.' -f $filePath, $filePathInVM, $pss.VMName | Write-ScriptLog
            $filePathInVM  # Return the file path in the VM.
        }

        return $filePathsInVM
    }
    finally {
        if ($pss) {
            Remove-PSDirectSession -Session $pss
        }
    }
}

function Remove-FileWithinVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $true)]
        [string[]] $FilePathToRemoveInVM,

        [Parameter(Mandatory = $false)]
        [string[]] $ImportModuleInVM = @()
    )

    $attemptLimit = 5
    for ($attempts = 0; $attempts -lt $attemptLimit; $attempts++) {
        try {
            $pss = New-PSDirectSession -VMName $VMName -Credential $Credential
            Invoke-PSDirectSessionGroundwork -Session $pss -ImportModuleInVM $ImportModuleInVM

            # Remove the files within the VM.
            $params = @{
                Session      = $pss
                ArgumentList = $FilePathToRemoveInVM
            }
            Invoke-Command @params -ScriptBlock {
                param (
                    [Parameter(Mandatory = $true)]
                    [string[]] $FilePathToRemove
                )

                # Delete files one by one for traceability when raise exception.
                foreach ($filePath in $FilePathToRemove) {
                    if (Test-Path -LiteralPath $filePath) {
                        'Delete the "{0}" within the VM "{1}".' -f $filePath, $env:ComputerName | Write-ScriptLog
                        Remove-Item -LiteralPath $filePath -Force
                        'Delete the "{0}" within the VM "{1}" succeeded.' -f $filePath, $env:ComputerName | Write-ScriptLog
                    }
                    else {
                        'The "{0}" within the VM "{1}" does not exist.' -f $filePath, $env:ComputerName | Write-ScriptLog
                    }
                }
            }
            return
        }
        catch {
            'Delete files within the VM failed.' | Write-ScriptLog -Level Warning
            New-ExceptionMessage -ErrorRecord $_ -AsHandled | Write-ScriptLog -Level Warning
            Start-Sleep -Seconds 5
        }
        finally {
            if ($pss) {
                Remove-PSDirectSession -Session $pss
            }
        }
    }

    $exceptionMessage = 'The file delete operation within the VM "{0}" with "{1}" failed {2} times.' -f $VMName, $Credential.UserName, $attemptLimit
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}

function Invoke-CommandWithinVM
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $true)]
        [ScriptBlock] $ScriptBlock,

        [Parameter(Mandatory = $false)]
        [Object[]] $ScriptBlockParamList,

        [Parameter(Mandatory = $false)]
        [switch] $WithRetry,

        [Parameter(Mandatory = $false)]
        [string[]] $ImportModuleInVM = @()
    )

    $attemptLimit = if ($WithRetry) { 5 } else { 1 }
    for ($attempts = 0; $attempts -lt $attemptLimit; $attempts++) {
        try {
            $pss = New-PSDirectSession -VMName $VMName -Credential $Credential
            Invoke-PSDirectSessionGroundwork -Session $pss -ImportModuleInVM $ImportModuleInVM

            # Invoke the script block within the VM.
            $params = @{
                Session     = $pss
                ScriptBlock = $ScriptBlock
            }
            if ($PSBoundParameters.ContainsKey('ScriptBlockParamList')) {
                $params.ArgumentList = $ScriptBlockParamList
            }
            Invoke-Command @params
            return
        }
        catch {
            'The script block invocation within the VM "{0}" with "{1}" failed.' -f $VMName, $Credential.UserName | Write-ScriptLog -Level Warning
            New-ExceptionMessage -ErrorRecord $_ -AsHandled | Write-ScriptLog -Level Warning
            Start-Sleep -Seconds 5
        }
        finally {
            if ($pss) {
                Remove-PSDirectSession -Session $pss
            }
        }
    }

    $exceptionMessage = 'The script block invocation within the VM "{0}" with "{1}" failed {2} times.' -f $VMName, $Credential.UserName, $attemptLimit
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
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

    'Create a shortcut file "{0}".' -f $ShortcutFilePath | Write-ScriptLog
    $wshShell = New-Object -ComObject 'WScript.Shell'
    $shortcut = $wshShell.CreateShortcut($ShortcutFilePath)
    $shortcut.TargetPath = $TargetPath
    if ($PSBoundParameters.ContainsKey('Arguments')) { $shortcut.Arguments = $Arguments }
    if ($PSBoundParameters.ContainsKey('Description')) { $shortcut.Description = $Description }
    if ($PSBoundParameters.ContainsKey('IconLocation')) { $shortcut.IconLocation = $IconLocation }
    $shortcut.Save()
    'Create a shortcut file "{0}" completed.' -f $ShortcutFilePath | Write-ScriptLog
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
    'Start-VMSurely',
    'Stop-VMSurely',
    'Wait-PowerShellDirectReady',
    'Block-AddsDomainOperation',
    'Unblock-AddsDomainOperation',
    'Wait-AddsDcDeploymentCompletion',
    'Wait-DomainControllerServiceReady',
    'New-LogonCredential',
    'Add-VMToADDomain',
    'Copy-FileIntoVM',
    'Remove-FileWithinVM',
    'Invoke-CommandWithinVM'
    'New-ShortcutFile',
    'New-WacConnectionFileEntry',
    'New-WacConnectionFileContent'
)
Export-ModuleMember -Function $exportFunctions
