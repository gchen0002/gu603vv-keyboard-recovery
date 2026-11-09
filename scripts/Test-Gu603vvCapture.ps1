[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RawImage,
    [string]$CpuView
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Gu603vv.Diagnostics.psm1')

function Read-LocalCapture([string]$Path) {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ($resolved.StartsWith('\\') -or $resolved.StartsWith('//')) {
        throw 'Use a local file, not a UNC path.'
    }
    $file = Get-Item -LiteralPath $Path
    if ($file -isnot [IO.FileInfo] -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Expected a regular capture file.'
    }
    $stream = [IO.File]::Open($file.FullName, 'Open', 'Read', 'Read')
    try {
        if ($stream.Length -ne 0x40000) { throw 'Expected exactly 256 KiB.' }
        $buffer = [byte[]]::new(0x40000)
        $read = 0
        while ($read -lt $buffer.Length) {
            $count = $stream.Read($buffer, $read, $buffer.Length - $read)
            if ($count -le 0) { throw 'Capture ended early.' }
            $read += $count
        }
        return ,$buffer
    } finally { $stream.Dispose() }
}

$raw = Read-LocalCapture $RawImage
$cpuChecks = $null
if ($PSBoundParameters.ContainsKey('CpuView')) {
    $cpu = Read-LocalCapture $CpuView
    $cpuChecks = Get-Gu603vvBankChecks -Image $cpu -LayoutImage $raw
}
[pscustomobject]@{
    Raw = Get-Gu603vvBankChecks -Image $raw -LayoutImage $raw
    Cpu = $cpuChecks
    Note = 'Offline sums and modeled selection only. A raw pass does not prove that the controller can boot.'
} | ConvertTo-Json -Depth 6
