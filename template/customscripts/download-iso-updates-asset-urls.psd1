# Azure Local 24H2 - OS build: 26100
#
# OS: https://learn.microsoft.com/azure/azure-local/release-information-23h2?view=azloc-2504

# Azure Stack HCI 23H2 - OS build: 25398
#
# OS: https://learn.microsoft.com/azure/azure-local/release-information-23h2?view=azloc-2503
# OS (legacy): https://support.microsoft.com/topic/018b9b10-a75b-4ad7-b9d1-7755f81e5b0b
# .NET: https://support.microsoft.com/topic/789dbbae-ea0f-4a31-9500-dff68e9995d5

# Azure Stack HCI 22H2 - OS build: 20349
#
# OS: https://support.microsoft.com/topic/fea63106-a0a9-4b6c-bb72-a07985c98a56
# .NET: https://support.microsoft.com/topic/63a78b8a-8447-4d16-a1e9-38a63493398b
# Relese info: https://learn.microsoft.com/azure-stack/hci/release-information

# Azure Stack HCI 21H2 - OS build: 20348
# End of service: 2023-11-14
#
# OS: https://support.microsoft.com/topic/5c5e6adf-e006-4a29-be22-f6faeff90173
# .NET: https://support.microsoft.com/topic/78075158-2c2f-4315-ba95-c5ee0e2ee871
#
# Azure Stack HCI 20H2 - OS build: 17784
# End of service: 2022-12-13
#
# OS: https://support.microsoft.com/topic/64c79b7f-d536-015d-b8dd-575f01090efd
# .NET: n/a

# Windows Server release information
# OS: https://learn.microsoft.com/windows/release-health/windows-server-release-info
#
# Windows Server 2025 - OS build: 26100 - 24H2
# OS: https://support.microsoft.com/topic/10f58da7-e57b-4a9d-9c16-9f1dcd72d7d7
# .NET: TBD
#
# Windows Server 2022 - OS build: 20348 - 21H2
# OS: https://support.microsoft.com/topic/e1caa597-00c5-4ab9-9f3e-8212fe80b2ee
# .NET: https://support.microsoft.com/topic/56635939-4249-4eaa-ac39-394fcaec6a94

@{
    'azloc24h2' = @{
        'iso' = @{
            'en-us' = 'https://azurestackreleases.download.prss.microsoft.com/dbazure/AzureStackHCI/OS-Composition/12.2504.0.3142/AzureLocal24H2.26100.1742.LCM.12.2504.0.3142.x64.en-us.iso'
            #'ja-jp' = ''
        }
        'updates' = @(
            # OS
            #'',
            # .NET Framework
            #''
        )
    }
    'ashci23h2' = @{
        'iso' = @{
            'en-us' = 'https://azurestackreleases.download.prss.microsoft.com/dbazure/AzureLocal/WindowsPlatform/10.2503.0.3057/AzureLocal23H2.25398.469.LCM.10.2503.0.3057.x64.en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/25398.469.231004-1141.zn_release_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b712d58a-0f46-423b-ad41-ad8398318230/public/windows11.0-kb5055527-x64_ae74e95f08111d3530de7e81870cc6cd21b29556.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2025/03/windows11.0-kb5054705-x64-ndp481_e21ab281c54a6becc425189425e6099e93dc438b.msu'
        )
    }
    'ashci22h2' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2025-04
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2025/04/windows10.0-kb5055526-x64_70f346aababda91456cf7fb6e8f206f80c5bd310.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2025/03/windows10.0-kb5055169-x64-ndp48_07015721a8fc001c5b1946fc49584bb649a4aa49.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2025/03/windows10.0-kb5054693-x64-ndp481_e81e514fe650aee149be6b260b44d97b134a1b2b.msu'
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
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/11/windows10.0-kb5031993-x64-ndp48_548eda3e35e6696ade138379b0e2718bbab1132f.msu',
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/11/windows10.0-kb5032008-x64-ndp481_abd8ca626edc26bd32c8a944073864af80df7eec.msu',
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
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu',
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/584ce7f1-b0c7-43c8-b2af-256fb291c5e3/public/windows11.0-kb5059087-x64_180d9c16b32cbda1c941e2e1c83f93439d6c004c.msu',
            # .NET Framework
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/02cd9c83-8312-424d-9a06-b042095804a8/public/windows11.0-kb5054979-x64-ndp481_8e2f730bc747de0f90aaee95d4862e4f88751c07.msu'
        )
    }
    'ws2022' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2025-04
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2025/04/windows10.0-kb5059092-x64_71d4ebfa1489defbb9fe209e1f7217b2ae052c8e.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2025/03/windows10.0-kb5055169-x64-ndp48_07015721a8fc001c5b1946fc49584bb649a4aa49.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2025/03/windows10.0-kb5054693-x64-ndp481_e81e514fe650aee149be6b260b44d97b134a1b2b.msu'
        )
    }
}
