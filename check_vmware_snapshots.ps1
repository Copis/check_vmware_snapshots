<#
.DESCRIPTION
This script looks for a existing snapshots for all VM that are older than X days
.EXAMPLE
.\check_snapshots.ps1 -server vcenter -u username -p password
#>

# Parameters
Param(
  [string]$server,
  [string]$user,
  [string]$pwd
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

# Looking for the snapshots aged 3 days or over
$now = Get-Date
# Variables to store the information to be reported
$snapsToDelete = ""
$oldest = 0

foreach ($DataCenter in $DataCenters) {
    $VMs = Get-VM -Location $DataCenter -Server $VCenter
    foreach ($vm in $VMs) {
        if ($vm.Name -like "*replica*") { continue }
        $snaps = @()

        $snaps += Get-Snapshot -VM $vm -Server $VCenter | Sort-Object -Property Created -Descending
        foreach ($snap in $snaps) {
            $Days = [int]($now-$snap.Created).TotalDays
            if($Days -lt 3) {
                continue
            }else {
                $snapsToDelete += $vm.Name + ", "# (" + -$snap.Name +"), "
                if($oldest -lt $Days) { $oldest = $Days }
            }
        }
    }
}

# Closing Virtual Center Connection
Disconnect-VIServer -Server $vCenter -Force -Confirm:$false

if ($oldest -lt 3) {
    Write-Host "Ok - No VM snasphots older than 3 day"
    exit $OK
}elseif(($oldest -gt 3) -and ($oldest -lt 7)){
    Write-Host "WARNING - $snapsToDelete ar older than 3 day"
    exit $WARNING
}else {
    Write-Host "CRITICAL - $snapsToDelete ar older than 7 day"
    exit $CRITICAL
}
