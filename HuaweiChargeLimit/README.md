# Huawei Charge Limit (experimental)

An experimental Windows PowerShell 5.1 / WinForms prototype intended to control Huawei laptop battery thresholds. It does not bundle Huawei binaries or run a resident background service.

## Before using it

This is an early prototype and remains unverified on the MateBook D15. The laptop exposes `OemWMIfun` with `UInt8Array u8Input` and `UInt8Array u8Output`; Huawei's own WMI helper uses a 64-byte `u8Input` buffer first, with a `u64Input` fallback on other provider versions. The app now follows the array interface exposed by this laptop and checks the response before enabling Apply.

The WMI path is now matched to the laptop's reported schema, but the command and response still need hardware validation. `GetSmartChargeMode` from Huawei's DLL is a separate query and does not by itself verify the raw threshold read. The script requests administrator elevation because firmware writes require it.

The first run issues only the threshold read command `0x1103`. Apply remains disabled unless the response decodes to a valid start/stop pair. Compare the displayed values with the laptop's known Huawei setting before using Apply; the write path has not yet been verified on this model.

## Run

From PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\HuaweiChargeLimit.ps1
```

The script prompts for UAC elevation if needed. It uses only built-in Windows PowerShell, WinForms, and CIM commands.

## Scope

- Intended protocol under investigation: read command `0x1103`, set command `0x1003`.
- The command is packed into the 64-byte `u8Input` array exposed by the D15 WMI method.
- Does not modify fan speed, performance mode, Windows power plans, services, or unrelated registry settings.
- Does not include any PC Manager installer, DLL, driver, firmware image, or other Huawei binary.

The command mapping is based on the in-tree Linux Huawei WMI driver and static analysis of Huawei PC Manager. The read/write flow is still experimental until the read, a controlled write, read-back, and real charging behavior are verified on this model.
