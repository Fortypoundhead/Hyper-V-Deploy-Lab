<#

    .NOTES

    FileName:   Deploy_Servers.ps1
    Version:    1.0
    Author:     Derek Wirch
    Start Date: 2020-07-09

    .SYNOPSIS

    Quickly deploy thin-provisioned VMs from a template

    .DESCRIPTION

    

    .EXAMPLE
    
    
    
#>

# Set some defaults, move to INI after testing

$VSwitch="Private Switch Name"

$SourceVMTemplate="D:\VIrtualMachines\VirtualHardDisks\Win2016Template.vhdx"
$DCLocalUser = "Administrator"
$DCDomainUser = "$DomainNetBios\Administrator"
$ImagePW="ImagePasswordHere"
$DCLocalPWord = ConvertTo-SecureString -String $ImagePW -AsPlainText -Force
$DCLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DCLocalUser, $DCLocalPWord
$DCDomainCredential= New-Object -Typename System.Management.Automation.PSCredential -ArgumentList $DCDomainUser, $DCLocalPWord
$TargetVHDPath="E:\VirtualMachines"

# Get list of servers to build from 

$ServerList=Import-csv -path .\serverlist.csv -verbose
ForEach ($Server in $ServerList)
{
    $ServerName = $Server.Name
    $ServerIPAddress = $Server.IPAddress
    $DG = $Server.DG
    $SM = $Server.SM
    $DNS1 = $Server.DNS1
    $DNS2 = $Server.DNS2
    $Role = $Server.Role
    $Memory = $Server.Memory
    $vCPU = $Server.Processors

    write-host "`nBuilding $ServerName`n" -foregroundcolor yellow
    write-host "    role = $Role"

    New-VM -Name $ServerName -Path $TargetVHDPath -NoVHD -Generation 2 -MemoryStartupBytes $Memory -SwitchName $vSwitch 
    Set-VM -name $ServerName -processorcount $vCPU -staticmemory -AutomaticStartAction Start -AutomaticStopAction Shutdown -AutomaticStartDelay 1 -CheckpointType disabled 
    New-VHD -Path $TargetVHDPath\$ServerName.vhdx -ParentPath $SourceVMTemplate
    Add-VMHardDiskDrive -vmname $ServerName -path $TargetVHDPath\$ServerName.vhdx
    $OsVirtualDrive = Get-VMHardDiskDrive -VMName $ServerName -ControllerNumber 0
    Set-VMFirmware -VMName $ServerName -FirstBootDevice $OSVirtualDrive

    # Power On! and wait for PowerShell Direct to become available
    
    write-host "    starting $ServerName"
    Start-VM $ServerName

    write-host "    Waiting for PowerShell Direct to start on $ServerName"
    while ((icm -VMName $ServerName -Credential $DCLocalCredential {"Test"} -ea SilentlyContinue) -ne "Test") {Sleep -Seconds 1}
    write-host "    PowerShell Direct responding on $ServerName. Moving On"

    # Configure Guest OS

    #  - Configure Network
    #  - rename guest
    #  - reboot

    Invoke-Command -VMName $ServerName -Credential $DCLocalCredential -ScriptBlock {
        param ($ServerName,$ServerIPAddress,$SM,$DG,$DNS1,$DNS2,$DNS3,$DNS4,$DNS5)

            write-host "    Setting network configuation on $ServerName" 

            New-NetIPAddress -IPAddress "$ServerIPAddress" -InterfaceAlias "Ethernet" -PrefixLength "$SM" -defaultgateway "$DG" | out-null
            $FSEffectiveIP = Get-NetIPAddress -InterfaceAlias "Ethernet" | Select-Object IPAddress
            
            Write-host "    Assigned IPv4 and IPv6 IPs for $ServerName are as follows" 
            Write-Host $FSEffectiveIP | Format-List
            
            Write-host "    Setting DNS Source on $ServerName" 
            Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("$DNS1","$DNS2","$DNS3","$DNS4","$DNS5")
            
            Write-host "    Updating Hostname for $ServerName" 
            Rename-Computer -NewName "$ServerName"

        } -ArgumentList $ServerName,$ServerIPAddress,$SM,$DG,$DNS1,$DNS2,$DNS3,$DNS4,$DNS5

    Write-host "    Rebooting $ServerName for hostname change to take effect" 
    Restart-VM -Name $ServerName -force
 
}