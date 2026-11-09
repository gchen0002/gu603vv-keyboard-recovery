$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Gu603vv.Diagnostics.psm1')

function Assert-That($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $true }
    Assert-That $rejected $Message
}

$normal = @(
    [pscustomobject]@{InstanceId='USB\VID_0B05&PID_19B6\SYNTHETIC'; Class='HIDClass'; Status='OK'}
    [pscustomobject]@{InstanceId='HID\VID_0B05&PID_19B6&COL02\SYNTHETIC'; Class='Keyboard'; Status='OK'}
)
$recovery = @(
    [pscustomobject]@{InstanceId='USB\VID_048D&PID_89DB\SYNTHETIC'; Class='HIDClass'; Status='OK'}
    [pscustomobject]@{InstanceId='HID\VID_048D&PID_89DB\SYNTHETIC'; Class='HIDClass'; Status='OK'}
)
Assert-That ((Get-Gu603vvInventorySummary 'GU603VV' $normal).State -eq 'NormalTypingInterfacePresent') 'Normal interface not recognized.'
$summary = Get-Gu603vvInventorySummary 'ROG Zephyrus G16 GU603VV_GU603VV' $recovery
Assert-That ($summary.State -eq 'RecoveryInterfacePresent') 'Recovery interface not recognized.'
Assert-That (($summary | ConvertTo-Json) -notmatch 'SYNTHETIC|InstanceId') 'Instance identifiers leaked.'
Assert-That ((Get-Gu603vvInventorySummary 'GU603VI' $recovery).State -eq 'DifferentModel') 'Wrong model accepted.'
Assert-That ((Get-Gu603vvInventorySummary 'GU603VV' ($normal + $recovery)).State -eq 'Ambiguous') 'Mixed modes accepted.'
Assert-That ((Get-Gu603vvInventorySummary 'GU603VV' ($normal + $normal)).State -eq 'Ambiguous') 'Duplicate devices accepted.'
Assert-That ((Get-Gu603vvInventorySummary 'GU603VV' @($normal[0])).State -eq 'Inconclusive') 'USB parent mistaken for keyboard.'
Assert-That ((Get-Gu603vvInventorySummary 'GU603VV' @()).State -eq 'Inconclusive') 'Absent device mistaken for keyboard.'

# Synthetic bytes only. The two bank sums are 0x0102 and 0x0003.
$image = [byte[]]::new(0x40000)
$geometry = @(0x2002, 0x1dfff, 0x2000, 0x20002, 0x3bfff, 0x20000)
for ($i = 0; $i -lt $geometry.Count; $i++) {
    [Array]::Copy([BitConverter]::GetBytes([uint32]$geometry[$i]), 0, $image, (0x3c400 + 4 * $i), 4)
}
$image[0x3c418] = 1
$image[0x3c41a] = 0x52
$image[0x3c41b] = 0x82
$image[0x2000] = 0xfe
$image[0x2001] = 0xfe
$image[0x2002] = 0xff
$image[0x1dfff] = 3
$image[0x20000] = 0xff
$image[0x20001] = 0xfd
$image[0x20002] = 3
$checks = Get-Gu603vvBankChecks $image $image
Assert-That ($checks.Checks[0].Matches -and $checks.Checks[1].Matches) 'Synthetic sums differ.'
Assert-That ($checks.FirstPassingBankInStaticModel -eq 2) 'Preferred bank changed.'
$cpu = [byte[]]$image.Clone()
$cpu[0x3bfff] = 8
Assert-That ((Get-Gu603vvBankChecks $cpu $image).FirstPassingBankInStaticModel -eq 1) 'Fallback check failed.'
$cpu[0x1dfff] = 4
Assert-That ($null -eq (Get-Gu603vvBankChecks $cpu $image).FirstPassingBankInStaticModel) 'Two invalid banks produced a match.'
$badLayout = [byte[]]$image.Clone()
$badLayout[0x3c400] = 0
Assert-Rejected { Get-Gu603vvBankChecks $image $badLayout } 'Wrong geometry accepted.'
$badLayout = [byte[]]$image.Clone()
$badLayout[0x3c418] = 0
Assert-Rejected { Get-Gu603vvBankChecks $image $badLayout } 'Wrong selector accepted.'
Assert-Rejected { Get-Gu603vvBankChecks ([byte[]]::new(16)) $image } 'Wrong file size accepted.'
'Synthetic inventory, privacy, checksum, fallback and rejection checks passed.'
