[CmdletBinding()]
param([switch]$AsJson)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Keyboard inventory requires Windows.' }
Import-Module (Join-Path $PSScriptRoot 'Gu603vv.Diagnostics.psm1')

$model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
$devices = @(Get-PnpDevice -PresentOnly)
$result = Get-Gu603vvInventorySummary -Model $model -Devices $devices
if ($AsJson) { $result | ConvertTo-Json } else { $result }
