# Huawei Charge Limit (experimental)

A small Windows PowerShell 5.1 / WinForms utility for reading and setting Huawei laptop battery start/stop charging thresholds through the firmware WMI interface. It does not bundle Huawei binaries or run a resident background service.

## Before using it

This is an early prototype and is **not currently compatible with the reported MateBook D15 WMI schema**. The app's battery protocol requires an `OemWMIfun` method with a 64-bit `u64Input` parameter. The target laptop reports `u8Input (UInt8)` and scalar outputs instead. The app now checks this signature before sending any command and fails closed; do not use the prior prototype build on this laptop.

The required Huawei firmware interface is still being identified. `GetSmartChargeMode` from Huawei's DLL is a separate query and does not prove that the raw threshold commands are supported by the exposed WMI method. The script requests administrator elevation because supported firmware writes require it.

No threshold read or write is supported by the current app on this laptop. Once we identify the compatible Huawei method, the first hardware test should be read-only; only a confirmed protocol should enable the setting controls.

## Run

From PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\HuaweiChargeLimit.ps1
```

The script prompts for UAC elevation if needed. It uses only built-in Windows PowerShell, WinForms, and CIM commands.

## Optional sign-in restore

The checkbox creates a Task Scheduler job that reapplies the last verified threshold once at user sign-in and exits. It is optional and has no polling loop. This may help if the firmware forgets its threshold across some sleep or power transitions, but it cannot reapply the setting while Windows is shut down. Keep the script at the same path after enabling the task.

## Scope

- Intended protocol under investigation: read command `0x1103`, set command `0x1003`.
- These commands are not sent unless the required 64-bit WMI parameter is present.
- Does not modify fan speed, performance mode, Windows power plans, services, or unrelated registry settings.
- Does not include any PC Manager installer, DLL, driver, firmware image, or other Huawei binary.

The command mapping is based on the in-tree Linux Huawei WMI driver and static analysis of Huawei PC Manager, but the Windows method path for this laptop has not been verified. No charge-limit functionality should be considered working until a compatible read, a controlled write, read-back, and real charging behavior are verified on this model.
