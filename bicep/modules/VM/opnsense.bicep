param untrustedSubnetId string
param trustedSubnetId string = ''
param publicIPId string = ''
param virtualMachineName string
param TempUsername string
param TempPassword string
param virtualMachineSize string
param OPNScriptURI string
param ShellScriptName string
//param ShellScriptParameters string = ''
param nsgId string = ''
param ExternalLoadBalancerBackendAddressPoolId string = ''
param InternalLoadBalancerBackendAddressPoolId string = ''
param ExternalloadBalancerInboundNatRulesId string = ''
param ShellScriptObj object = {}
param multiNicSupport bool
param Location string = resourceGroup().location

var untrustedNicName = '${virtualMachineName}-Untrusted-NIC'
var trustedNicName = '${virtualMachineName}-Trusted-NIC'

resource trustedSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = if (!empty(ShellScriptObj.TrustedSubnetName)){
  name: ShellScriptObj.TrustedSubnetName
}

resource windowsvmsubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = if (!empty(ShellScriptObj.WindowsSubnetName)) {
  name: ShellScriptObj.WindowsSubnetName
}

module untrustedNic '../vnet/nic.bicep' = {
  name: untrustedNicName
  params:{
    Location: Location
    nicName: untrustedNicName
    subnetId: untrustedSubnetId
    publicIPId: publicIPId
    enableIPForwarding: false
    nsgId: nsgId
    loadBalancerBackendAddressPoolId: ExternalLoadBalancerBackendAddressPoolId
    loadBalancerInboundNatRules: ExternalloadBalancerInboundNatRulesId
  }
}

module trustedNic '../vnet/nic.bicep' = if(multiNicSupport){
  name: trustedNicName
  params:{
    Location: Location
    nicName: trustedNicName
    subnetId: trustedSubnetId
    enableIPForwarding: false
    nsgId: nsgId
    loadBalancerBackendAddressPoolId: InternalLoadBalancerBackendAddressPoolId
  }
}

resource OPNsense 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: virtualMachineName
  location: Location
  properties: {
    osProfile: {
      computerName: virtualMachineName
      adminUsername: TempUsername
      adminPassword: TempPassword
    }
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
      }
      imageReference: {
        publisher: 'thefreebsdfoundation'
        offer: 'freebsd-13_0'
        sku: '13_0-release'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: multiNicSupport == true ?[
        {
          id: untrustedNic.outputs.nicId
          properties:{
            primary: true
          }
        }
        {
          id: trustedNic.outputs.nicId
          properties:{
            primary: false
          }
        }
      ]:[
        {
          id: untrustedNic.outputs.nicId
          properties:{
            primary: true
          }
        }
      ]
    }
  }
  plan: {
    name: '13_0-release'
    publisher: 'thefreebsdfoundation'
    product: 'freebsd-13_0'
  }
}

resource vmext 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = {
  name: '${OPNsense.name}/CustomScript'
  location: Location
  properties: {
    publisher: 'Microsoft.OSTCExtensions'
    type: 'CustomScriptForLinux'
    typeHandlerVersion: '1.5'
    autoUpgradeMinorVersion: false
    settings:{
      fileUris: [
        '${OPNScriptURI}${ShellScriptName}'
      ]
      commandToExecute: 'sh ${ShellScriptName} ${ShellScriptObj.OpnScriptURI} ${ShellScriptObj.OpnType} ${!empty(ShellScriptObj.TrustedSubnetName) ? trustedSubnet.properties.addressPrefix : ''} ${!empty(ShellScriptObj.WindowsSubnetName) ? windowsvmsubnet.properties.addressPrefix : '1.1.1.1/32'} ${ShellScriptObj.publicIPAddress} ${ShellScriptObj.opnSenseSecondarytrustedNicIP}'
    }
  }
}

output untrustedNicIP string = untrustedNic.outputs.nicIP
output trustedNicIP string = multiNicSupport == true ? trustedNic.outputs.nicIP : ''
output untrustedNicProfileId string = untrustedNic.outputs.nicIpConfigurationId
