# When a GU603VV keyboard gets stuck in ITE recovery mode

My ROG Zephyrus G16 GU603VV keyboard stopped working even in BIOS. In Windows, the internal USB device appeared as `048D:89DB` (ITE recovery) instead of the normal ASUS `0B05:19B6` keyboard. Rebuilding the first application bank on its keyboard controller brought it back. It was still working normally a month later.

This is a [repair write-up](docs/repair-notes.md) and a pair of read-only Windows diagnostics. The repair was verified on one laptop. The firmware writer was tied to that laptop's exact starting state and is not included.

## Check what Windows sees

Open PowerShell 7 on Windows in this repository and run:

```powershell
.\scripts\Get-Gu603vvKeyboardState.ps1 -AsJson
```

| Result | What it means |
| --- | --- |
| `NormalTypingInterfacePresent` | The ASUS USB device and its normal keyboard collection are present and report OK. This does not test physical key presses. |
| `RecoveryInterfacePresent` | The ITE USB and recovery HID devices seen in this case are present. This is a clue, not a diagnosis of the flash contents. |
| `Ambiguous` | Both sets of IDs or multiple matches are present. Do not assume which device is internal. |
| `Inconclusive` | Windows did not report a complete, healthy match to either state. |
| `DifferentModel` | The computer's model does not match GU603VV. |

The command queries Windows inventory. It sends no commands to the keyboard and prints no serial numbers, instance IDs, usernames, or physical device paths. A USB ID can be reused by other devices; matching one is not a compatibility check for firmware.

### If you're using an agent to troubleshoot

Point it at this README and tell it whether the built-in keys work in BIOS. For example:

> Use the read-only inventory script in this repo to check my GU603VV keyboard. Tell me whether Windows sees the normal typing interface or the ITE recovery interface, and explain what that result does and doesn't tell us. Don't flash firmware or reset the controller.

## Check an existing capture offline

If you already have a local 256 KiB capture from this controller layout, you can reproduce the boot checksum calculation. The tool doesn't acquire a capture or write one back.

```powershell
.\scripts\Test-Gu603vvCapture.ps1 -RawImage .\captures\raw.bin
.\scripts\Test-Gu603vvCapture.ps1 -RawImage .\captures\raw.bin -CpuView .\captures\cpu-view.bin
```

`-CpuView` is optional. It accepts a 256 KiB view with CPU-read bank bytes at their original offsets. Use a raw capture and CPU view from the same controller state; don't mix pre- and post-repair reads. The layout comes from the raw capture. The report shows stored and calculated sums, whether they match, and the first passing bank in the reconstructed boot order. A passing raw checksum alone did not explain what this controller did at boot.

The checker rejects unrecognized layout metadata. It cannot identify a good repair image, verify a digital signature, or tell you that a flash would be safe. Keep your captures private.

## Run the tests

```powershell
.\tests\Test-Diagnostics.ps1
```

The tests use invented device records and byte arrays. There is no firmware, flash dump, vendor executable, or decompiled vendor code in this repository. The [MIT license](LICENSE) covers the original code and documentation here, not ASUS or ITE software.
