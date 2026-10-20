# Huawei Charge Limit (experimental)

A small Windows PowerShell 5.1 / WinForms utility for reading and setting Huawei laptop battery start/stop charging thresholds through the firmware WMI interface. It does not bundle Huawei binaries or run a resident background service.

## Before using it

This is an early prototype and is **not currently compatible with the reported MateBook D15 WMI schema**. The app's battery protocol requires an `OemWMIfun` method with a 64-bit `u64Input` parameter. The target laptop reports `u8Input (UInt8)` and scalar outputs instead. The app now checks this signature before sending any command and fails closed; do not use the prior prototype build on this laptop.

The required Huawei firmware interface is still being identified. `GetSmartChargeMode` from Huawei's DLL is a separate query and does not prove that the raw threshold commands are supported by the exposed WMI method. The script requests administrator elevation because supported firmware writes require it.

After the read succeeds and the values make sense for the machine, enter the desired start and stop percentages. The app requires `stop > start`, asks for confirmation, writes the firmware setting, then reads it back and compares both values. Observe Windows' charging status afterwards to confirm the charger actually stops at the selected level.

## Run

From PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\HuaweiChargeLimit.ps1
```

The script prompts for UAC elevation if needed. It uses only built-in Windows PowerShell, WinForms, and CIM commands.

## Optional sign-in restore

The checkbox creates a Task Scheduler job that reapplies the last verified threshold once at user sign-in and exits. It is optional and has no polling loop. This may help if the firmware forgets its threshold across some sleep or power transitions, but it cannot reapply the setting while Windows is shut down. Keep the script at the same path after enabling the task.

## Scope

- Read thresholds with WMI command `0x1103`.
- Set thresholds with WMI command `0x1003`.
- Does not modify fan speed, performance mode, Windows power plans, services, or unrelated registry settings.
- Does not include any PC Manager installer, DLL, driver, firmware image, or other Huawei binary.

The protocol mapping is based on the in-tree Linux Huawei WMI driver and static analysis of Huawei PC Manager. Treat the app as experimental until its read, write, read-back, and real charging behavior are verified on the intended laptop.
