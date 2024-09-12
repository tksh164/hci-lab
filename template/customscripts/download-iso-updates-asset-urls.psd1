#
# Update information sources
#
# Azure Stack HCI
# OS: https://learn.microsoft.com/en-us/azure-stack/hci/release-information
#
# Azure Stack HCI 23H2 - OS build: 25398
# OS: https://learn.microsoft.com/en-us/azure-stack/hci/release-information-23h2
# OS (legacy): https://support.microsoft.com/en-us/topic/018b9b10-a75b-4ad7-b9d1-7755f81e5b0b
# .NET: https://support.microsoft.com/en-us/topic/e3c9b0d9-ec46-4e8e-ba87-6c831bc11ef3
#
# Azure Stack HCI 22H2 - OS build: 20349
# OS: https://support.microsoft.com/en-us/topic/fea63106-a0a9-4b6c-bb72-a07985c98a56
# .NET: https://support.microsoft.com/en-us/topic/bbf02b18-7147-42c2-9d1b-d8d5d5195bc6
#
# Azure Stack HCI 21H2 - OS build: 20348
# End of service: 2023-11-14
# OS: https://support.microsoft.com/en-us/topic/5c5e6adf-e006-4a29-be22-f6faeff90173
# .NET: https://support.microsoft.com/en-us/topic/78075158-2c2f-4315-ba95-c5ee0e2ee871
#
# Azure Stack HCI 20H2 - OS build: 17784
# End of service: 2022-12-13
# OS: https://support.microsoft.com/en-us/topic/64c79b7f-d536-015d-b8dd-575f01090efd
# .NET: n/a
#
# Windows Server 2022 - OS buidl: 20348
# OS: https://support.microsoft.com/en-us/topic/e1caa597-00c5-4ab9-9f3e-8212fe80b2ee
# .NET: https://support.microsoft.com/en-us/topic/4fbab26b-493a-4ee5-9766-d6448e73bfb1
#

@{
    'ashci23h2' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/25398.469.231004-1141.zn_release_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/25398.469.231004-1141.zn_release_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/33c7f34f-3dfd-4da4-a24f-57c91da10a0b/public/windows11.0-kb5043055-x64_717e61e23aa481e928233de194b28e1e479f1d87.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2024/07/windows11.0-kb5041969-x64-ndp481_63d33f9b4ad747a507e8c81dc1d04e0d7c2db5e7.msu'
        )
    }
    'ashci22h2' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2024-09
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/09/windows10.0-kb5042881-x64_f000f2a81f3b019ee1a6c627b56b54062d49b1d7.msu'
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2024/07/windows10.0-kb5041948-x64-ndp48_527a7c3a58fc633435eaba0ef450ebd57750fb66.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2024/07/windows10.0-kb5041964-x64-ndp481_3873cce49bce0a36d85ceb34513073cd22b88d46.msu'
        )
    }
    'ashci21h2' = @{
        'iso' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_ja-jp.iso'
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
    'ws2025' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1.240331-1435.ge_release_SERVER_EVAL_x64FRE_en-us.iso?culture=en-us&country=US'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1.240331-1435.ge_release_SERVER_EVAL_x64FRE_ja-jp.iso?culture=ja-jp&country=JP'
        }
        'updates' = @(
            # OS
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/be8c1ad5-56ac-422b-9351-86b586bcc2de/public/windows11.0-kb5041571-x64_adcfbf9f2bf5f01a98b91dbd8ebbe65402f896c8.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2024/07/windows11.0-kb5042098-x64-ndp481_75fb29d8a82fde2199171290b83253841d9e16f2.msu'
        )
    }
    'ws2022' = @{
        'iso' = @{
            'en-us' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US'
            'ja-jp' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x411&culture=ja-jp&country=JP'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2024-08
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/08/windows10.0-kb5041160-x64_f8dc7d5afa74f5b403c918ea78dd82a60626bcfd.msu'
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2024/07/windows10.0-kb5041948-x64-ndp48_527a7c3a58fc633435eaba0ef450ebd57750fb66.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2024/07/windows10.0-kb5041964-x64-ndp481_3873cce49bce0a36d85ceb34513073cd22b88d46.msu'
        )
    }
}
