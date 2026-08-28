@export()
type osSymbol = osSymbolAzureLocal | osSymbolAzureStackHCI | osSymbolWindowsServer

type osSymbolAzureLocal =
  | 'azloc24h2_2608'  // Azure Local 24H2 2608
  | 'azloc24h2_2607'  // Azure Local 24H2 2607
  | 'azloc24h2_2606'  // Azure Local 24H2 2606
  | 'azloc24h2_2605'  // Azure Local 24H2 2605
  | 'azloc24h2_2604'  // Azure Local 24H2 2604
  | 'azloc24h2_2603'  // Azure Local 24H2 2603
  | 'azloc24h2_2602'  // Azure Local 24H2 2602
  | 'azloc24h2_2601'  // Azure Local 24H2 2601
  | 'azloc24h2_2512'  // Azure Local 24H2 2512
  | 'azloc24h2_2511'  // Azure Local 24H2 2511
  | 'azloc24h2_2510'  // Azure Local 24H2 2510
  | 'azloc24h2_2509'  // Azure Local 24H2 2509
  | 'azloc24h2_2508'  // Azure Local 24H2 2508
  | 'azloc24h2_2507'  // Azure Local 24H2 2507
  | 'azloc24h2_2506'  // Azure Local 24H2 2506
  | 'azloc24h2_2505'  // Azure Local 24H2 2505
  | 'azloc24h2_2504'  // Azure Local 24H2 2504

type osSymbolAzureStackHCI =
  | 'ashci23h2'  // Azure Stack HCI 23H2 / Azure Local 23H2 2503
  | 'ashci22h2'  // Azure Stack HCI 22H2
  | 'ashci21h2'  // Azure Stack HCI 21H2
  | 'ashci20h2'  // Azure Stack HCI 20H2
  | 'ws2025'     // Windows Server 2025
  | 'ws2022'     // Windows Server 2022

type osSymbolWindowsServer =
  | 'ws2025'  // Windows Server 2025
  | 'ws2022'  // Windows Server 2022

@export()
type osImageIndex =
  | 1  // For Azure Stack HCI
  | 4  // For Windows Server Datacenter with Desktop Experience
  //| 3  // For Windows Server Datacenter Server Core

@export()
type supportedOsLanguage =
  | 'en-us'
  | 'ja-jp'

@export()
@minLength(1)
@maxLength(20)
type vmAdminUserName = string

@export()
@minLength(1)
@maxLength(64)
type vmResourceName = string

@export()
type supportedOsDiskType = 'Premium_LRS' | 'StandardSSD_LRS' | 'Standard_LRS'

@export()
type supportedDataDiskType = 'Premium_LRS' | 'StandardSSD_LRS'

@export()
type supportedDataDiskSize = 32 | 64 | 128 | 256 | 512 | 1024

@export()
@minValue(8)
@maxValue(32)
type supportedDataDiskCount = int

@export()
@minValue(2)
@maxValue(8)
type supportedNodeMachineCount = int

// Required VM size capabilities:
// - Generation 2 VM support
// - Premium storage support
// - Accelerated networking support
// - Nested virtualization support
// - 32+ GB RAM
// - No temp storage
@export()
type supportedVmSize =
  | Esv6Series
  | Esv5Series
  | Ebsv5Series
  | Easv6Series
  | Easv5Series
  | Dsv6Series
  | Dsv5Series
  | Dasv6Series
  | Dasv5Series
  | Dlsv6Series
  | Dlsv5Series
  | Dsv4Series
  | Fasv6Series
  | Falsv6Series
  | Fsv2Series
  | FXSeries

// Esv6 series
type Esv6Series =
  | 'Standard_E4s_v6'
  | 'Standard_E8s_v6'
  | 'Standard_E16s_v6'
  | 'Standard_E20s_v6'
  | 'Standard_E32s_v6'
  | 'Standard_E48s_v6'
  | 'Standard_E64s_v6'
  | 'Standard_E96s_v6'
  // | 'Standard_E128s_v6'
  // | 'Standard_E192s_v6'

// Edsv6 series
//type Edsv6Series =
  // | 'Standard_E4ds_v6'
  // | 'Standard_E8ds_v6'
  // | 'Standard_E16ds_v6'
  // | 'Standard_E20ds_v6'
  // | 'Standard_E32ds_v6'
  // | 'Standard_E48ds_v6'
  // | 'Standard_E64ds_v6'
  // | 'Standard_E96ds_v6'
  // | 'Standard_E128ds_v6'
  // | 'Standard_E192ds_v6'

// Esv5 series
type Esv5Series =
  | 'Standard_E4s_v5'
  | 'Standard_E8s_v5'
  | 'Standard_E16s_v5'
  | 'Standard_E20s_v5'
  | 'Standard_E32s_v5'
  | 'Standard_E48s_v5'
  | 'Standard_E64s_v5'
  | 'Standard_E96s_v5'

// Edsv5 series
//type Edsv5Series =
  // | 'Standard_E4ds_v5'
  // | 'Standard_E8ds_v5'
  // | 'Standard_E16ds_v5'
  // | 'Standard_E20ds_v5'
  // | 'Standard_E32ds_v5'
  // | 'Standard_E48ds_v5'
  // | 'Standard_E64ds_v5'
  // | 'Standard_E96ds_v5'

// Ebsv5 series
type Ebsv5Series =
  | 'Standard_E4bs_v5'
  | 'Standard_E8bs_v5'
  | 'Standard_E16bs_v5'
  | 'Standard_E32bs_v5'
  | 'Standard_E48bs_v5'
  | 'Standard_E64bs_v5'

// Ebdsv5 series
//type Ebdsv5Series =
  // | 'Standard_E4bds_v5'
  // | 'Standard_E8bds_v5'
  // | 'Standard_E16bds_v5'
  // | 'Standard_E32bds_v5'
  // | 'Standard_E48bds_v5'
  // | 'Standard_E64bds_v5'

// Easv6 series
type Easv6Series =
  | 'Standard_E16as_v6'
  | 'Standard_E20as_v6'
  | 'Standard_E32as_v6'
  | 'Standard_E48as_v6'
  | 'Standard_E64as_v6'
  | 'Standard_E96as_v6'

// Eadsv6 series
//type Eadsv6Series =
  // | 'Standard_E16ads_v6'
  // | 'Standard_E20ads_v6'
  // | 'Standard_E32ads_v6'
  // | 'Standard_E48ads_v6'
  // | 'Standard_E64ads_v6'
  // | 'Standard_E96ads_v6'

// Easv5 series
type Easv5Series =
  | 'Standard_E16as_v5'
  | 'Standard_E20as_v5'
  | 'Standard_E32as_v5'
  | 'Standard_E48as_v5'
  | 'Standard_E64as_v5'
  | 'Standard_E96as_v5'

// Eadsv5 series
//type Eadsv5Series =
  // | 'Standard_E16ads_v5'
  // | 'Standard_E20ads_v5'
  // | 'Standard_E32ads_v5'
  // | 'Standard_E48ads_v5'
  // | 'Standard_E64ads_v5'
  // | 'Standard_E96ads_v5'

// Dsv6 series
type Dsv6Series =
  | 'Standard_D8s_v6'
  | 'Standard_D16s_v6'
  | 'Standard_D32s_v6'
  | 'Standard_D48s_v6'
  | 'Standard_D64s_v6'
  | 'Standard_D96s_v6'

// Ddsv6 series
//type Ddsv6Series =
  // | 'Standard_D8ds_v6'
  // | 'Standard_D16ds_v6'
  // | 'Standard_D32ds_v6'
  // | 'Standard_D48ds_v6'
  // | 'Standard_D64ds_v6'
  // | 'Standard_D96ds_v6'

// Dsv5 series
type Dsv5Series =
  | 'Standard_D8s_v5'
  | 'Standard_D16s_v5'
  | 'Standard_D32s_v5'
  | 'Standard_D48s_v5'
  | 'Standard_D64s_v5'
  | 'Standard_D96s_v5'

// Ddsv5 series
//type Ddsv5Series =
  // | 'Standard_D8ds_v5'
  // | 'Standard_D16ds_v5'
  // | 'Standard_D32ds_v5'
  // | 'Standard_D48ds_v5'
  // | 'Standard_D64ds_v5'
  // | 'Standard_D96ds_v5'

// Dasv6 series
type Dasv6Series =
  | 'Standard_D32as_v6'
  | 'Standard_D48as_v6'
  | 'Standard_D64as_v6'
  | 'Standard_D96as_v6'

// Dadsv6 series
//type Dadsv6Series =
  // | 'Standard_D32ads_v6'
  // | 'Standard_D48ads_v6'
  // | 'Standard_D64ads_v6'
  // | 'Standard_D96ads_v6'

// Dasv5 series
type Dasv5Series =
  | 'Standard_D32as_v5'
  | 'Standard_D48as_v5'
  | 'Standard_D64as_v5'
  | 'Standard_D96as_v5'

// Dadsv5 series
//type Dadsv5Series =
  // | 'Standard_D32ads_v5'
  // | 'Standard_D48ads_v5'
  // | 'Standard_D64ads_v5'
  // | 'Standard_D96ads_v5'

// Dlsv6 series
type Dlsv6Series =
  | 'Standard_D16ls_v6'
  | 'Standard_D32ls_v6'
  | 'Standard_D48ls_v6'
  | 'Standard_D64ls_v6'
  | 'Standard_D96ls_v6'

// Dldsv6 series
//type Dldsv6Series =
  // | 'Standard_D16lds_v6'
  // | 'Standard_D32lds_v6'
  // | 'Standard_D48lds_v6'
  // | 'Standard_D64lds_v6'
  // | 'Standard_D96lds_v6'

// Dlsv5 series
type Dlsv5Series =
  | 'Standard_D16ls_v5'
  | 'Standard_D32ls_v5'
  | 'Standard_D48ls_v5'
  | 'Standard_D64ls_v5'
  | 'Standard_D96ls_v5'

// Dldsv5 series
//type Dldsv5Series =
  // | 'Standard_D16lds_v5'
  // | 'Standard_D32lds_v5'
  // | 'Standard_D48lds_v5'
  // | 'Standard_D64lds_v5'
  // | 'Standard_D96lds_v5'

// Dsv4 series
type Dsv4Series =
  | 'Standard_D8s_v4'
  | 'Standard_D16s_v4'
  | 'Standard_D32s_v4'
  | 'Standard_D48s_v4'
  | 'Standard_D64s_v4'

// Ddsv4 series
//type Ddsv4Series =
  // | 'Standard_D8ds_v4'
  // | 'Standard_D16ds_v4'
  // | 'Standard_D32ds_v4'
  // | 'Standard_D48ds_v4'
  // | 'Standard_D64ds_v4'

// Fasv6 series
type Fasv6Series =
  | 'Standard_F8as_v6'
  | 'Standard_F16as_v6'
  | 'Standard_F32as_v6'
  | 'Standard_F48as_v6'
  | 'Standard_F64as_v6'

// Falsv6 series
type Falsv6Series =
  | 'Standard_F16als_v6'
  | 'Standard_F32als_v6'
  | 'Standard_F48als_v6'
  | 'Standard_F64als_v6'

// Fsv2 series
type Fsv2Series =
  | 'Standard_F16s_v2'
  | 'Standard_F32s_v2'
  | 'Standard_F48s_v2'
  | 'Standard_F64s_v2'
  | 'Standard_F72s_v2'

// FX series
type FXSeries =
  | 'Standard_FX4mds'
  | 'Standard_FX12mds'
  | 'Standard_FX24mds'
  | 'Standard_FX36mds'
  | 'Standard_FX48mds'

@export()
@sealed()
type labConfiguration = {
  labHost: {
    storage: {
      poolName: string
      driveLetter: driveLetter
      volumeLabel: string
    }
    folderPath: {
      log: string
      temp: string
      updates: string
      vhd: string
      vm: string
    }
    vSwitch: {
      nat: {
        name: string
      }
    }
    netNat: {
        name: string
        InternalAddressPrefix: string
        hostInternalIPAddress: string
        hostInternalPrefixLength: ipAddressPrefixLength
    }[]
    toolsToInstall: string
  }
  guestOS: {
    culture: supportedOsLanguage
    timeZone: string
    shouldInstallUpdates: bool
  }
  addsDomain: {
    fqdn: string
  }
  addsDC: {
    vmName: string
    maximumRamBytes: int
    netAdapters: {
      management: {
        name: string
        ipAddress: string
        prefixLength: ipAddressPrefixLength
        defaultGateway: string
        dnsServerAddresses: string[]
      }
    }
    shouldPrepareAddsForAzureLocal: bool
    orgUnitForAzureLocal: string
    lcmUserName: string
  }
  wac: {
    vmName: string
    maximumRamBytes: int
    netAdapters: {
      management: {
        name: string
        ipAddress: string
        prefixLength: ipAddressPrefixLength
        defaultGateway: string
        dnsServerAddresses: string[]
      }
    }
    shouldInstallConfigAppForAzureLocal: bool
  }
  hciNode: {
    vmName: string  // 'name{0:00}', vmNameOffset + ZeroBasedNodeIndex
    vmNameOffset: int
    operatingSystem: {
      sku: osSymbol
      imageIndex: osImageIndex
    }
    nodeCount: supportedNodeMachineCount
    shouldJoinToAddsDomain: bool
    isAzureLocalDeployment: bool
    dataDiskSizeBytes: int
    ipAddressOffset: int
    netAdapters: {
      management: {
        name: string
        ipAddress: string  // 'x.x.x.{0}', ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: ipAddressPrefixLength
        defaultGateway: string
        dnsServerAddresses: string[]
      }
      compute: {
        name: string
        ipAddress: string  // 'x.x.x.{0}', ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: ipAddressPrefixLength
      }
      storage1: {
        name: string
        vlanId: vlanId
        ipAddress: string  // 'x.x.x.{0}', ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: ipAddressPrefixLength
      }
      storage2: {
        name: string
        vlanId: vlanId
        ipAddress: string  // 'x.x.x.{0}', ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: ipAddressPrefixLength
      }
    }
  }
  hciCluster: {
    shouldCreateCluster: bool
    name: string
    ipAddress: string
  }
  keyVault: {
    name: string
    secretName: {
      adminPassword: string
      cloudWitnessStorageAccountName: string
      cloudWitnessStorageAccountKey: string
    }
  }
}

@minLength(1)
@maxLength(1)
type driveLetter = string

@minValue(0)
@maxValue(32)
type ipAddressPrefixLength = int

@minValue(1)
@maxValue(4094)
type vlanId = int
