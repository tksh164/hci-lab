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
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/00ff26bb-2f67-4f4d-bfc4-287f96873de9/public/windows11.0-kb5044288-x64_0a51cc8ea210a361b808079f2eba093e47b2f709.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/09/windows11.0-kb5044028-x64-ndp481_e38507e196b22537333dca882f124b37e075c99c.msu'
        )
    }
    'ashci22h2' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2024-10
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/10/windows10.0-kb5044281-x64_7bc7e22ddb93ee7e7b0ec36962ef061c2683c345.msu'
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/09/windows10.0-kb5044025-x64-ndp48_076f88ac9074f6626dc5fbce564e01bbfd0ffba1.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/09/windows10.0-kb5044035-x64-ndp481_c6081dbdbc8365ec4426585520f58038decdfb56.msu'
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
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/72f34af9-6ab3-4bb0-9dfe-103e56a305fb/public/windows11.0-kb5044284-x64_d7eb7ceaa4798b92b988fd7dcc7c6bb39476ccf3.msu',
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu',
            # .NET Framework
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/dd0ce468-3a60-411c-bcaf-f5090cb1581c/public/windows11.0-kb5044030-x64-ndp481_b691d9673c75939f6a183a126d6621ec482164f3.msu'
        )
    }
    'ws2022' = @{
        'iso' = @{
            'en-us' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US'
            'ja-jp' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x411&culture=ja-jp&country=JP'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2024-10
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/10/windows10.0-kb5044281-x64_7bc7e22ddb93ee7e7b0ec36962ef061c2683c345.msu'
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/09/windows10.0-kb5044025-x64-ndp48_076f88ac9074f6626dc5fbce564e01bbfd0ffba1.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/09/windows10.0-kb5044035-x64-ndp481_c6081dbdbc8365ec4426585520f58038decdfb56.msu'
        )
    }
}
