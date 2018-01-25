<#
.DESCRIPTION
This script looks for a existing snapshots or consolidation problems for all VM that are older than X days
.EXAMPLE
.\check_snapshots.ps1 -server vcenter -user username -pwd password -exclude_vm vm1,vm2,...,vmX -days_warning days (default 3) -days_critical days (default 7)
#>

# Parameters
Param(
  [string]$server,
  [string]$user,
  [string]$pwd,
  [Array]$exclude_vm,
  [int]$days_warning = 3,
  [int]$days_critical = 7
)

# States
$OK = 0
$WARNING = 1
$CRITICAL = 2
$UNKNOWN = 3

# Credential for vcenter
$Password = $pwd | ConvertTo-SecureString -asPlainText -Force
$Cred = New-Object System.Management.Automation.PSCredential($user,$Password)

# Adding required SnapIn
if((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null) {
	Add-PsSnapin VMware.VimAutomation.Core
}

# Connect to vCenter server
$VCenter=Connect-VIServer -Server $server -Credential $Cred -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
if ($VCenter -eq $null) {
    Write-Host "UNKNOWN - Failed to connect to virtual center server"
    exit $UNKNOWN
    }

# Get all existing Datacenters into vCenter. // Future check only datacenter that fit a pattern
$DataCenters = Get-Datacenter -Server $VCenter | Sort-Object

# Looking for the snapshots aged $days_warning days or over
$now = Get-Date
# Variables to store the information to be reported
$snapsToDelete = ""
$oldest = 0

foreach ($DataCenter in $DataCenters) {
    $VMs = Get-VM -Location $DataCenter -Server $VCenter
    foreach ($vm in $VMs) {
        if ($vm.Name -like "*replica*" -or $vm.Name -in $exclude_vm) { continue }
        $snaps = @()

        $snaps += Get-Snapshot -VM $vm -Server $VCenter | Sort-Object -Property Created -Descending
        foreach ($snap in $snaps) {
            $Days = [int]($now-$snap.Created).TotalDays
            if($Days -lt $days_warning) {
                continue
            }else {
                $snapsToDelete += $vm.Name + ", "# (" + -$snap.Name +"), "
                if($oldest -lt $Days) { $oldest = $Days }
            }
        }
	# Looking for consolidation 
	if ($vm.ExtensionData.Runtime.ConsolidationNeeded) {
            $consolidationNeeded += $vm.Name +", "
        }
    }
}

# Closing Virtual Center Connection
Disconnect-VIServer -Server $vCenter -Force -Confirm:$false

# Print results
if ($oldest -lt $days_warning -and $consolidationNeeded -eq $null) {
    Write-Host "Ok - No VM snasphots older than $days_warning days"
    exit $OK
}elseif(($oldest -ge $days_warning) -and ($oldest -lt $days_critical) -and $consolidationNeeded -eq $null) {
    Write-Host "WARNING - $snapsToDelete ar older than $days_warning days"
    exit $WARNING
}else {
    if($oldest -ge $days_critical -and $consolidationNeeded){
        Write-Host "CRITICAL - $snapsToDelete snapshots ar older than $days_critical days, $consolidationNeeded needs consolidation."
        exit $CRITICAL
    }
    elseif($consolidationNeeded){
        Write-Host "CRITICAL - $consolidationNeeded needs consolidation."
        exit $CRITICAL
    }
    else{
        Write-Host "CRITICAL - $snapsToDelete ar older than $days_critical days"
        exit $CRITICAL
    }
}
