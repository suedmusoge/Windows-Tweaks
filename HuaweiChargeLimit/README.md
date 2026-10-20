# Huawei Charge Limit (experimental)

An experimental Windows PowerShell 5.1 / WinForms prototype intended to control Huawei laptop battery thresholds. It does not bundle Huawei binaries or run a resident background service.

## Before using it

This is an early prototype and remains unverified on the MateBook D15. The laptop exposes `OemWMIfun` with `UInt8Array u8Input` and `UInt8Array u8Output`; Huawei's own WMI helper uses a 64-byte `u8Input` buffer first, with a `u64Input` fallback on other provider versions. The app now follows the array interface exposed by this laptop and checks the response before enabling Apply.

Huawei documents that uninstalling PC Manager automatically enables Smart Charge. When Smart Charge is enabled, custom charge limits are unavailable/overridden. The app therefore reads the firmware charge-mode code (`0x1603`) on launch. On Apply, it selects Huawei's Home profile using `SetSmartChargeMode` (`0x462848011503`), verifies mode code 1, then writes and reads back the requested custom thresholds (`0x1003`). Home profile selection sets the known 40%/70% defaults first; the custom threshold write follows immediately.

The Smart Charge command encoding is based on static analysis of Huawei's exported `WmiUtil.dll` methods and the open-source [Huawei WMI project](https://github.com/qu1x/huawei-wmi), which documents the Home-profile command as the way to leave Smart Charge mode before restoring thresholds. This sequence remains experimental until tested on the MateBook D15. The script requests administrator elevation because firmware writes require it.

The first run issues only read commands `0x1103` (thresholds) and `0x1603` (charge mode). Apply remains disabled unless both responses decode plausibly. Apply requires confirmation, switches to Home mode, writes the custom threshold, then verifies both mode and threshold. The write path remains unverified on this model; if mode verification or threshold read-back fails, stop and report the exact app status.

## Run

From PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\HuaweiChargeLimit.ps1
```

The script prompts for UAC elevation if needed. It uses only built-in Windows PowerShell, WinForms, and CIM commands.

## Scope

- Read commands: `0x1103` for thresholds and `0x1603` for Smart Charge mode.
- Apply sequence: select Home mode (`0x1503` with mode 1, 72, 40, 70) to leave Smart Charge, then set the custom thresholds with `0x1003`.
- The command is packed into the 64-byte `u8Input` array exposed by the D15 WMI method.
- Does not modify fan speed, performance mode, Windows power plans, services, or unrelated registry settings.
- Does not include any PC Manager installer, DLL, driver, firmware image, or other Huawei binary.

The threshold mapping is based on the in-tree Linux Huawei WMI driver; Smart Charge command details are based on static analysis of Huawei PC Manager and the linked community project. The flow is still experimental until the mode read, controlled write, read-back, and real charging behavior are verified on this model.
