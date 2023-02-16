[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$configParams = GetConfigParameters
Start-ScriptTranscript -OutputDirectory $configParams.labHost.folderPath.log -ScriptName $MyInvocation.MyCommand.Name
$configParams | ConvertTo-Json -Depth 16

function DownloadIso
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $true)]
        [string] $DownloadFolderPath
    )

    $isoUris = @{
        'as22h2' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
        }
        'as21h2' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_ja-jp.iso'
        }
        'as20h2' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_ja-jp.iso'
        }
        'ws2022' = @{
            'en-us' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US'
            'ja-jp' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x411&culture=ja-jp&country=JP'
        }
    }

    $params = @{
        SourceUri      = $isoUris[$OperatingSystem][$Culture]
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = (BuildIsoFileName -OperatingSystem $OperatingSystem -Culture $Culture)
    }
    DownloadFile @params
}

function DownloadUpdates
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $DownloadFolderBasePath
    )

    #
    # Azure Stack HCI
    # OS: https://learn.microsoft.com/en-us/azure-stack/hci/release-information
    #
    # Azure Stack HCI 22H2
    # OS: https://support.microsoft.com/en-us/help/5018894
    # .NET: https://support.microsoft.com/en-us/help/5022726
    #
    # Azure Stack HCI 21H2
    # OS: https://support.microsoft.com/en-us/help/5004047
    # .NET: https://support.microsoft.com/en-us/help/5023809
    #
    # Azure Stack HCI 20H2
    # OS: https://support.microsoft.com/en-us/help/4595086
    # .NET: 
    #
    # Windows Server 2022
    # OS: https://support.microsoft.com/en-us/help/5005454
    # .NET: https://support.microsoft.com/en-us/help/5006918
    #

    $updates = @{
        'as22h2' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/02/windows10.0-kb5022842-x64_708d02971c761091c9d978a18588a315c3817343.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/12/windows10.0-kb5022507-x64-ndp48_c738ff11f6b74c8b1e9db4c66676df651b32d8ef.msu'
        )
        'as21h2' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/02/windows10.0-kb5022842-x64_708d02971c761091c9d978a18588a315c3817343.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/01/windows10.0-kb5022501-x64-ndp481_f609707b45c8dd6d6b97c3cec996200d97e95fac.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/12/windows10.0-kb5022507-x64-ndp48_c738ff11f6b74c8b1e9db4c66676df651b32d8ef.msu',
            # OS - KB5012170
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/08/windows10.0-kb5012170-x64_a9d0e4a03991230936232ace729f8f9de3bbfa7f.msu'
        )
        'as20h2' = @(
            # Servicing stack update
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/11/windows10.0-kb5020804-x64_e879f9925911b6700f51a276cf2a9f48436b46e9.msu',
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/12/windows10.0-kb5021236-x64_1794df60ae269c4a70627301bdcc9d48f0fe179f.msu'
        )
        'ws2022' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/02/windows10.0-kb5022842-x64_708d02971c761091c9d978a18588a315c3817343.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/01/windows10.0-kb5022501-x64-ndp481_f609707b45c8dd6d6b97c3cec996200d97e95fac.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/12/windows10.0-kb5022507-x64-ndp48_c738ff11f6b74c8b1e9db4c66676df651b32d8ef.msu',
            # OS - KB5012170
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/08/windows10.0-kb5012170-x64_a9d0e4a03991230936232ace729f8f9de3bbfa7f.msu'
        )
    }

    $downloadFolderPath = [IO.Path]::Combine($DownloadFolderBasePath, $OperatingSystem)
    New-Item -ItemType Directory -Path $downloadFolderPath -Force

    for ($i = 0; $i -lt $updates[$OperatingSystem].Length; $i++) {
        $params = @{
            SourceUri      = $updates[$OperatingSystem][$i]
            DownloadFolder = $downloadFolderPath
            FileNameToSave = '{0}_{1}' -f $i, [IO.Path]::GetFileName([uri]($updates[$OperatingSystem][$i]))  # Prepend the index due to order for applying.
        }
        DownloadFile @params
    }
}

# ISO

'Creating the download folder if it does not exist...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.temp -Force

'Downloading the ISO file...' | WriteLog -Context $env:ComputerName
DownloadIso -OperatingSystem $configParams.hciNode.operatingSystem.sku -Culture $configParams.guestOS.culture -DownloadFolderPath $configParams.labHost.folderPath.temp

# The Windows Server 2022 ISO is always needed for the domain controller VM.
if ($configParams.hciNode.operatingSystem.sku -ne 'ws2022') {
    'Downloading Windows Server 2022 ISO file...' | WriteLog -Context $env:ComputerName
    DownloadIso -OperatingSystem 'ws2022' -Culture $configParams.guestOS.culture -DownloadFolderPath $configParams.labHost.folderPath.temp
}

'The ISO download has been completed.' | WriteLog -Context $env:ComputerName

# Updates

# Download the updates if the flag was true only.
if ($configParams.guestOS.applyUpdates) {
    'Creating the updates folder if it does not exist...' | WriteLog -Context $env:ComputerName
    New-Item -ItemType Directory -Path $configParams.labHost.folderPath.updates -Force
    
    'Downloading updates...' | WriteLog -Context $env:ComputerName
    DownloadUpdates -OperatingSystem $configParams.hciNode.operatingSystem.sku -DownloadFolderBasePath $configParams.labHost.folderPath.updates
    
    if ($configParams.hciNode.operatingSystem.sku -ne 'ws2022') {
        'Downloading Windows Server 2022 updates...' | WriteLog -Context $env:ComputerName
        DownloadUpdates -OperatingSystem 'ws2022' -DownloadFolderBasePath $configParams.labHost.folderPath.updates
    }

    'The updates download has been completed.' | WriteLog -Context $env:ComputerName
}
else {
    'Skipped download of updates due to applyUpdates not set.' | WriteLog -Context $env:ComputerName
}

Stop-ScriptTranscript
