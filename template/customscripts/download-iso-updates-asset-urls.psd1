# Azure Stack HCI 23H2 - OS build: 25398
#
# OS: https://learn.microsoft.com/azure-stack/hci/release-information-23h2
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
# Windows Server 2025 - OS buidl: 26100 - 24H2
# OS: https://support.microsoft.com/topic/10f58da7-e57b-4a9d-9c16-9f1dcd72d7d7
# .NET: TBD
#
# Windows Server 2022 - OS buidl: 20348 - 21H2
# OS: https://support.microsoft.com/topic/e1caa597-00c5-4ab9-9f3e-8212fe80b2ee
# .NET: https://support.microsoft.com/topic/56635939-4249-4eaa-ac39-394fcaec6a94

@{
    'ashci23h2' = @{
        'iso' = @{
            'en-us' = 'https://azurestackreleases.download.prss.microsoft.com/dbazure/AzureStackHCI/OS-Composition/10.2411.3.3000/AzureLocal23H2.25398.469.LCM.10.2411.3.3000.x64.en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/25398.469.231004-1141.zn_release_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/35c4d02b-0711-4c65-a664-c0894127349d/public/windows11.0-kb5053599-x64_f3821f6320e32b8a4f8115584f78499f519e467c.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/12/windows11.0-kb5049620-x64-ndp481_a34707964a2b5e592a7c057287714c636b2b13d5.msu'
        )
    }
    'ashci22h2' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66750/AzureStackHCI_20349.1607_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2025-03
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/03/windows10.0-kb5053603-x64_38c42a8609e7b977498c65c46ad080aa3c637547.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/12/windows10.0-kb5049617-x64-ndp48_5adfae2ccbb4743d93898ff35010c77daa8f130f.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/12/windows10.0-kb5049625-x64-ndp481_cced48b8de758c3d5407c0fc62f198fca222c5b4.msu'
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
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/4807b0b1-6c5a-4a70-ab45-b378235fb9d6/public/windows11.0-kb5053598-x64_6cb3ffc5c4d652793dc71705248426eecdacdfd0.msu',
            # .NET Framework
            'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/8dbe7535-1d3a-450a-8f67-984c0206fb5b/public/windows11.0-kb5049622-x64-ndp481_afb8c71d1958d98de4082ff732762242e9460fad.msu'
        )
    }
    'ws2022' = @{
        'iso' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_ja-jp.iso'
        }
        'updates' = @(
            # OS
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037782-x64_a28aa2576fc6b120b127acfbb901d3546ba9db82.msu',  # For SSU of 2025-03
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/03/windows10.0-kb5053603-x64_38c42a8609e7b977498c65c46ad080aa3c637547.msu',
            # .NET Framework
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/12/windows10.0-kb5049617-x64-ndp48_5adfae2ccbb4743d93898ff35010c77daa8f130f.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/12/windows10.0-kb5049625-x64-ndp481_cced48b8de758c3d5407c0fc62f198fca222c5b4.msu'
        )
    }
}
