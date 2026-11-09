# How I recovered the built-in keyboard

## The clue I wish I'd checked first

The built-in keyboard would sometimes come back after I closed the lid and waited about 20 minutes. Then it stopped coming back. I had been using G-Helper and had run a Windows debloat tool, so I wondered if I had removed something the keyboard needed. Changing USB selective suspend and trying different sleep and ASUS service configurations didn't give me a repeatable fix.

The useful test was outside Windows. The built-in keys didn't respond in BIOS either. Windows still saw an internal USB device, but it was the controller's recovery interface, with vendor ID `048D` and product ID `89DB`. A working controller on this laptop shows up as `0B05:19B6` and exposes a keyboard collection called `COL02`. The recovery interface doesn't provide that typing collection.

That explained why a device could show up in Device Manager while the keys did nothing. It also made a Windows reinstall a poor next experiment. It didn't explain why the controller had gone into recovery in the first place.

## Why two reads mattered

The laptop was a GU603VV with BIOS 317 and an ITE keyboard controller that reported chip ID `8252`. The recovery descriptor matched the GU603VV .419 firmware family. Those observations describe this machine; they aren't a compatibility list.

Several complete raw reads of its 256 KiB controller flash agreed byte for byte. The flash held boot code, two application banks, recovery code, and factory data. The boot code checked a 16-bit sum before selecting an application bank. The stored value is big-endian. The calculation is the negative of the sum of the bank's data bytes, reduced to 16 bits. On this controller the recorded selector meant it would try the second bank first, then the first bank as a fallback.

At first the raw reads didn't add up to an explanation. The first bank failed, but the second passed. If the controller saw those same bytes when it checked the banks, the second bank should have been usable.

| Application bank | Stored | Calculated from raw read | Calculated from CPU read |
| --- | --- | --- | --- |
| First (fallback) | `0x490B` | `0x7471` (fail) | `0x7451` (fail) |
| Second (preferred) | `0x3E6E` | `0x3E6E` (pass) | `0x3E66` (fail) |

The two views disagreed at exactly two bytes across the application banks, one in each bank. The difference in the second bank was only one bit, but that was enough to change a passing sum into a failing one. Repeated reads reproduced that difference. The CPU-side read uses an access path closer to what the boot code uses. It is still a diagnostic read, not a trace of a real boot. With that caveat, two failed checks explained why the controller could land in recovery even though one raw checksum looked good.

We also dropped an early assumption about an access handshake. A reply echoing a manufacturer string looked like an acknowledgement. Inspection showed that an unhandled request could leave its bytes in the reply buffer. The echo proved nothing about an access gate. The final read checks didn't use that handshake.

## Where the replacement bytes came from

The ASUS driver already installed on this machine contained a GU603VV single-zone RGB .419 keyboard payload. We verified that payload against its signed driver catalog before using it. The package was in Microsoft's Component Firmware Update (CFU) format. It was not a raw flash image.

After decoding it offline, we compared its layout with the controller's existing contents. The decoded recovery and second-bank regions matched exactly at the inferred offsets. The reconstructed first bank passed the boot checksum calculation. It differed from the old first bank in 59 blocks of 1 KiB. That gave us a narrow target: write only those differing blocks. Leave boot, recovery, the second bank, factory data, and the bank selector as they were.

The matching regions and checksums gave us evidence for the mapping on this laptop. They didn't turn the decoded payload into an ASUS-supported recovery image. The standalone updater we examined expected a different container, and we didn't find a verified one for this exact model. We did not feed a decoded payload to that updater or borrow a container from another model.

## Where the write stopped

The private runner required the exact model, controller identity and starting bytes. It also checked charger and battery state, tested the volatile staging transfers, and wrote a journal before each erase and program operation. After each block it checked the requested range, neighboring bytes, and protected boot and recovery regions. It checked the programmed data through both read paths. A failure stopped the run without a retry, rollback, or reset.

Before the first write, all 59 candidate blocks passed staging checks in the controller's RAM. Fresh flash reads before and after staging still matched the backup. Software tests exercised failures such as a bad staging sum, a larger-than-expected erase, and a CPU read mismatch. Those tests checked whether the runner would stop. They couldn't prove how this chip would behave during a real erase.

That stop condition mattered. The first attempt issued 35 erase and program pairs. The first 34 passed the immediate checks. After the 35th write, a neighboring-byte check failed at a byte in the *next* block. That was the same first-bank byte that had previously disagreed between the raw and CPU reads. We hadn't touched its block yet.

Two fresh full raw reads then matched all 35 intended changes, with no changes outside them. A fresh CPU read also agreed on the written blocks. The old discrepancy at the untouched byte was still there. That distinction mattered: the failure had not shown that the new firmware couldn't be written to the suspect block. It had shown a read mismatch during a neighbor check.

The continuation was a separate run. It accepted only the exact partial state captured after the stop, skipped the 35 already correct blocks, and kept the same checks. It started with the suspect block. This time its raw and CPU reads agreed after programming. The remaining 23 blocks passed too. The final raw read matched the entire intended image, and a separate CPU read of the whole first bank calculated `0x490B`, the value it needed. The second bank was never written.

Only then did we reset the keyboard controller. Windows itself wasn't restarted. The ITE recovery device disappeared and the normal ASUS typing interface returned. I typed on the built-in keyboard to check that it actually worked. About a month later it was still working.

## What I'd take from this

Check the keys in BIOS and check the device mode early. If the normal typing interface is present, don't assume a firmware bank failed just because the keys don't respond. If a technician is already reading the flash, a checksum that passes through one access path doesn't settle what the CPU will see.

This repair got a valid first bank back in place. It didn't determine why the original bytes were wrong, or why the two read paths disagreed. A marginal flash cell or a read-path issue is still possible. We didn't establish that G-Helper, Windows debloating, heat, or selective suspend caused it. The month of use is a real result, but it isn't a controlled test of every boot and sleep state.

The private backups preserved the old **broken** state. They were useful for comparison, not a known-good rollback. We didn't test restoring them. That's one reason the write and reset tools aren't part of this release. If the IDs line up on your machine, use the inventory results to describe the problem. Don't use this write-up as a flashing recipe.

## Sources and release boundaries

- [ASUS GU603VV support](https://www.asus.com/us/supportonly/gu603vv/helpdesk_download/) is the vendor starting point for this model. The signed payload used in the repair was from the installed driver, not a file provided by this repository.
- The checksum and bank-order description is a reconstruction from the controller on this laptop. The offline checker implements only that calculation. It does not model instruction execution or the physical flash.
- The published evidence is the set of observations above. Machine identifiers, captures, firmware, vendor disassembly, recovery commands, and private logs are omitted. If you share your own results, share the small inventory summary and symptoms rather than uploading a dump.
