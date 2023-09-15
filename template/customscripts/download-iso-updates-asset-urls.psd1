#
# Update information sources
#
# Azure Stack HCI
# OS: https://learn.microsoft.com/en-us/azure-stack/hci/release-information
#
# Azure Stack HCI 22H2 - OS build: 20349
# OS: https://support.microsoft.com/en-us/help/5018894
# .NET: https://support.microsoft.com/en-us/help/5022726
#
# Azure Stack HCI 21H2 - OS build: 20348
# End of service: 2023-05-09
# OS: https://support.microsoft.com/en-us/help/5004047
# .NET: https://support.microsoft.com/en-us/help/5023809
#
# Azure Stack HCI 20H2 - OS build: 17784
# End of service: 2022-12-13
# OS: https://support.microsoft.com/en-us/help/4595086
# .NET: n/a
#
# Windows Server 2022 - OS buidl: 20348
# OS: https://support.microsoft.com/en-us/help/5005454
# .NET: https://support.microsoft.com/en-us/help/5006918
#

@{
    'ashci22h2' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/09/windows10.0-kb5030216-x64_cbe587155f9818548b75f65d5cd41d341ed2fc61.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/08/windows10.0-kb5029928-x64-ndp48_f6cb85805fa5fe22ad1cc8deb6db20c673dbbf04.msu'
        )
    }
    'ashci21h2' = @{
        'iso' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/08/windows10.0-kb5029250-x64_10f33f68c6bb539c5f2d96a43977f35b51a95177.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/07/windows10.0-kb5028956-x64_81b5156928f938f82ce1f16ba39cb41e2d37c99e.msu',
            # OS - KB5012170
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/08/windows10.0-kb5012170-x64_a9d0e4a03991230936232ace729f8f9de3bbfa7f.msu'
        )
    }
    'ashci20h2' = @{
        'iso' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_ja-jp.iso'
        }
        'updates' = @(
            # Servicing stack update
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/11/windows10.0-kb5020804-x64_e879f9925911b6700f51a276cf2a9f48436b46e9.msu',
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/12/windows10.0-kb5021236-x64_1794df60ae269c4a70627301bdcc9d48f0fe179f.msu',
            # OS - KB5012170
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/08/windows10.0-kb5012170-x64_e861a0d0f2e35bc1de3c8256f3c00479dfad2462.msu'
        )
    }
    'ws2022' = @{
        'iso' = @{
            'en-us' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US'
            'ja-jp' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x411&culture=ja-jp&country=JP'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/08/windows10.0-kb5029250-x64_10f33f68c6bb539c5f2d96a43977f35b51a95177.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/07/windows10.0-kb5028950-x64_cbc5842a87b7599d8b82089f6144dee6d20253f7.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/07/windows10.0-kb5028956-x64_81b5156928f938f82ce1f16ba39cb41e2d37c99e.msu',
            # OS - KB5012170
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/08/windows10.0-kb5012170-x64_a9d0e4a03991230936232ace729f8f9de3bbfa7f.msu'
        )
    }
}
