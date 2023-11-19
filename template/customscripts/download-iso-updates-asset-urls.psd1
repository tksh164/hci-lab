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
# End of service: 2023-11-14
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
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/11/windows10.0-kb5032198-x64_6ce4dd96ade8a19c876d53c85cbe7b3e26b0472b.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/11/windows10.0-kb5031993-x64-ndp48_548eda3e35e6696ade138379b0e2718bbab1132f.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/11/windows10.0-kb5032008-x64-ndp481_abd8ca626edc26bd32c8a944073864af80df7eec.msu'
        )
    }
    'ashci21h2' = @{
        'iso' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/10/windows10.0-kb5031364-x64_03606fb9b116659d52e2b5f5a8914bbbaaab6810.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2023/09/windows10.0-kb5030999-x64-ndp48_b31fe632e1c53a8057febdbe0665acd6fc38adb5.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2023/09/windows10.0-kb5030998-x64-ndp481_83c6d3f2b2c75f40fb7526c9d9e4e783f27902e4.msu',
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
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/11/windows10.0-kb5032198-x64_6ce4dd96ade8a19c876d53c85cbe7b3e26b0472b.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/11/windows10.0-kb5032008-x64-ndp481_abd8ca626edc26bd32c8a944073864af80df7eec.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/11/windows10.0-kb5031993-x64-ndp48_548eda3e35e6696ade138379b0e2718bbab1132f.msu',
            # OS - KB5012170
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/08/windows10.0-kb5012170-x64_a9d0e4a03991230936232ace729f8f9de3bbfa7f.msu'
        )
    }
}
