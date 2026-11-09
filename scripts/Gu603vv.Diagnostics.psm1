Set-StrictMode -Version Latest

function Get-Gu603vvInventorySummary {
    param([string]$Model, [object[]]$Devices)

    $matchesModel = $Model -match '(?:^|[\s_])GU603VV(?:$|[\s_])'
    $normalUsb = @($Devices | Where-Object InstanceId -match '^USB\\VID_0B05&PID_19B6\\')
    $recoveryUsb = @($Devices | Where-Object InstanceId -match '^USB\\VID_048D&PID_89DB\\')
    $typing = @($Devices | Where-Object {
        $_.InstanceId -match '^HID\\VID_0B05&PID_19B6&COL02\\' -and $_.Class -eq 'Keyboard'
    })
    $recoveryHid = @($Devices | Where-Object {
        $_.InstanceId -match '^HID\\VID_048D&PID_89DB\\' -and $_.Class -eq 'HIDClass'
    })

    $state = 'Inconclusive'
    if (!$matchesModel) {
        $state = 'DifferentModel'
    } elseif (($normalUsb.Count -gt 0 -or $typing.Count -gt 0) -and
              ($recoveryUsb.Count -gt 0 -or $recoveryHid.Count -gt 0)) {
        $state = 'Ambiguous'
    } elseif ($normalUsb.Count -gt 1 -or $recoveryUsb.Count -gt 1 -or
              $typing.Count -gt 1 -or $recoveryHid.Count -gt 1) {
        $state = 'Ambiguous'
    } elseif ($normalUsb.Count -eq 1 -and $typing.Count -eq 1 -and
              $normalUsb[0].Status -eq 'OK' -and $typing[0].Status -eq 'OK') {
        $state = 'NormalTypingInterfacePresent'
    } elseif ($recoveryUsb.Count -eq 1 -and $recoveryHid.Count -eq 1 -and
              $recoveryUsb[0].Status -eq 'OK' -and $recoveryHid[0].Status -eq 'OK') {
        $state = 'RecoveryInterfacePresent'
    }

    [pscustomobject]@{
        MatchesGu603vvModel = $matchesModel
        State = $state
        NormalUsbMatches = $normalUsb.Count
        TypingInterfaceMatches = $typing.Count
        RecoveryUsbMatches = $recoveryUsb.Count
        RecoveryHidMatches = $recoveryHid.Count
    }
}

function Get-Gu603vvBankChecks {
    param(
        [Parameter(Mandatory)][byte[]]$Image,
        [Parameter(Mandatory)][byte[]]$LayoutImage
    )

    if ($Image.Length -ne 0x40000 -or $LayoutImage.Length -ne 0x40000) {
        throw 'Expected a 256 KiB image in the observed GU603VV layout.'
    }
    if (![BitConverter]::IsLittleEndian) { throw 'This checker requires a little-endian host.' }
    if ($LayoutImage[0x3c418] -ne 1 -or $LayoutImage[0x3c41a] -ne 0x52 -or $LayoutImage[0x3c41b] -ne 0x82) {
        throw 'Unrecognized selector or chip metadata for this case profile.'
    }

    $results = @(
        for ($bank = 0; $bank -lt 2; $bank++) {
            $entry = 0x3c400 + 12 * $bank
            $pointer = @(0x2000, 0x20000)[$bank]
            $end = @(0x1dfff, 0x3bfff)[$bank]
            $start = $pointer + 2
            if ([BitConverter]::ToUInt32($LayoutImage, $entry) -ne $start -or
                [BitConverter]::ToUInt32($LayoutImage, $entry + 4) -ne $end -or
                [BitConverter]::ToUInt32($LayoutImage, $entry + 8) -ne $pointer) {
                throw 'Unrecognized bank table for this case profile.'
            }
            $sum = 0
            for ($address = $start; $address -le $end; $address++) {
                $sum += $Image[$address]
            }
            $stored = 256 * [int]$Image[$pointer] + [int]$Image[$pointer + 1]
            $computed = (-$sum) -band 0xffff
            [pscustomobject]@{
                Bank = $bank + 1
                Stored = '0x{0:X4}' -f $stored
                Computed = '0x{0:X4}' -f $computed
                Matches = $stored -eq $computed
            }
        }
    )
    $firstMatch = $null
    foreach ($bank in @(2, 1)) {
        if ($results[$bank - 1].Matches) { $firstMatch = $bank; break }
    }
    [pscustomobject]@{
        Checks = $results
        FirstPassingBankInStaticModel = $firstMatch
    }
}

Export-ModuleMember -Function Get-Gu603vvInventorySummary, Get-Gu603vvBankChecks
