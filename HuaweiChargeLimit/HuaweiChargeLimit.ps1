# Huawei Charge Limit - lightweight Windows Forms front end for Huawei ROOT\WMI.
# Reads and writes only battery start/stop charge thresholds (commands 0x1103/0x1003).
# Requires Windows PowerShell 5.1 and administrator elevation for firmware writes.
# Optional -ApplyAtLogon mode is used by a Task Scheduler task to restore the saved
# firmware threshold once at sign-in; no resident service or polling loop is used.

[CmdletBinding()]
param([switch]$ApplyAtLogon)

$ErrorActionPreference = 'Stop'
$script:SettingsPath = Join-Path $env:ProgramData 'HuaweiChargeLimit\settings.json'
$script:TaskName = 'Huawei Charge Limit - Restore firmware threshold'
$script:ScriptPath = $PSCommandPath

# Re-launch elevated so the WMI firmware method has the required rights.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($ApplyAtLogon) { exit 2 }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Verb RunAs -ArgumentList $arguments
    exit
}

function Invoke-HuaweiWmiCommand {
    param([Parameter(Mandatory)][UInt64]$Command)

    $lastError = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            $instance = Get-CimInstance -Namespace 'root/wmi' -ClassName 'OemWMIMethod' |
                Select-Object -First 1
            if (-not $instance) {
                throw "Huawei OemWMIMethod instance is unavailable in root/wmi."
            }

            $result = Invoke-CimMethod -InputObject $instance -MethodName 'OemWMIfun' `
                -Arguments @{ u64Input = $Command }
            if ($null -eq $result.u8Output) {
                throw "Firmware WMI call returned no u8Output data."
            }

            [byte[]]$bytes = $result.u8Output
            if ($bytes.Length -lt 3) {
                throw "Firmware WMI response was too short ($($bytes.Length) bytes)."
            }

            # Huawei's response byte 0 is the firmware status: 0 means success.
            if ($bytes[0] -eq 0) {
                return ,$bytes
            }
            $lastError = "Firmware status byte was $($bytes[0]) (attempt $attempt of 2)."
        }
        catch {
            $lastError = $_.Exception.Message
        }
    }
    throw "Huawei firmware command failed: $lastError"
}

function Get-HuaweiChargeThreshold {
    # Linux's in-tree Huawei WMI driver identifies 0x1103 as BATTERY_THRESH_GET.
    [byte[]]$bytes = Invoke-HuaweiWmiCommand -Command ([UInt64]0x1103)

    # The threshold getter returns the pair in the last non-zero slots of its
    # 256-byte payload; a 0-100 pair is also decoded correctly.
    $index = $bytes.Length - 1
    while ($index -gt 2 -and $bytes[$index] -eq 0) { $index-- }
    if ($index -lt 2) { throw 'Could not decode threshold values from firmware response.' }

    $start = [int]$bytes[$index - 1]
    $stop  = [int]$bytes[$index]
    if ($start -gt 100 -or $stop -gt 100 -or $stop -le $start) {
        throw "Firmware returned an unexpected threshold pair: $start% to $stop%."
    }

    [pscustomobject]@{ Start = $start; Stop = $stop }
}

function Set-HuaweiChargeThreshold {
    param(
        [Parameter(Mandatory)][ValidateRange(0, 100)][int]$Start,
        [Parameter(Mandatory)][ValidateRange(0, 100)][int]$Stop
    )
    if ($Stop -le $Start) { throw 'Stop threshold must be greater than start threshold.' }

    # Opcode 0x1003; little-endian bytes 2 and 3 are start and stop respectively.
    [UInt64]$command = [UInt64]0x1003
    $command = $command -bor ([UInt64]$Start -shl 16)
    $command = $command -bor ([UInt64]$Stop  -shl 24)
    [void](Invoke-HuaweiWmiCommand -Command $command)
}

function Save-ChargeSettings {
    param([int]$Start, [int]$Stop)
    $directory = Split-Path -Parent $script:SettingsPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [pscustomobject]@{ Start = $Start; Stop = $Stop } |
        ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
}

function Install-LogonRestoreTask {
    if (-not (Test-Path $script:SettingsPath)) {
        throw 'Apply and verify a charge threshold before enabling sign-in restore.'
    }
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -ApplyAtLogon' -f $script:ScriptPath
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 30) -StartWhenAvailable
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
}

function Remove-LogonRestoreTask {
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path $script:SettingsPath) { Remove-Item $script:SettingsPath -Force }
}

if ($ApplyAtLogon) {
    try {
        if (-not (Test-Path $script:SettingsPath)) { exit 3 }
        $saved = Get-Content -Path $script:SettingsPath -Raw | ConvertFrom-Json
        Set-HuaweiChargeThreshold -Start ([int]$saved.Start) -Stop ([int]$saved.Stop)
        $check = Get-HuaweiChargeThreshold
        if ($check.Start -ne [int]$saved.Start -or $check.Stop -ne [int]$saved.Stop) { exit 4 }
        exit 0
    } catch { exit 5 }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'Huawei Charge Limit'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = [System.Drawing.Size]::new(430, 316)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

$title = [System.Windows.Forms.Label]::new()
$title.Text = 'Battery charging thresholds'
$title.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Regular)
$title.Location = [System.Drawing.Point]::new(20, 16)
$title.Size = [System.Drawing.Size]::new(380, 28)
$form.Controls.Add($title)

$description = [System.Windows.Forms.Label]::new()
$description.Text = 'Firmware starts charging below the first value and stops at the second.'
$description.Location = [System.Drawing.Point]::new(22, 50)
$description.Size = [System.Drawing.Size]::new(390, 38)
$form.Controls.Add($description)

$startLabel = [System.Windows.Forms.Label]::new()
$startLabel.Text = 'Start charging below (%)'
$startLabel.Location = [System.Drawing.Point]::new(24, 101)
$startLabel.Size = [System.Drawing.Size]::new(220, 24)
$form.Controls.Add($startLabel)

$startBox = [System.Windows.Forms.NumericUpDown]::new()
$startBox.Minimum = 0
$startBox.Maximum = 100
$startBox.Value = 65
$startBox.Location = [System.Drawing.Point]::new(285, 98)
$startBox.Size = [System.Drawing.Size]::new(100, 25)
$form.Controls.Add($startBox)

$stopLabel = [System.Windows.Forms.Label]::new()
$stopLabel.Text = 'Stop charging at (%)'
$stopLabel.Location = [System.Drawing.Point]::new(24, 139)
$stopLabel.Size = [System.Drawing.Size]::new(220, 24)
$form.Controls.Add($stopLabel)

$stopBox = [System.Windows.Forms.NumericUpDown]::new()
$stopBox.Minimum = 1
$stopBox.Maximum = 100
$stopBox.Value = 70
$stopBox.Location = [System.Drawing.Point]::new(285, 136)
$stopBox.Size = [System.Drawing.Size]::new(100, 25)
$form.Controls.Add($stopBox)

$status = [System.Windows.Forms.Label]::new()
$status.Text = 'Reading current firmware settings…'
$status.Location = [System.Drawing.Point]::new(22, 170)
$status.Size = [System.Drawing.Size]::new(390, 42)
$status.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$form.Controls.Add($status)

$readButton = [System.Windows.Forms.Button]::new()
$readButton.Text = 'Read current'
$readButton.Location = [System.Drawing.Point]::new(22, 266)
$readButton.Size = [System.Drawing.Size]::new(112, 34)
$form.Controls.Add($readButton)

$applyButton = [System.Windows.Forms.Button]::new()
$applyButton.Text = 'Apply'
$applyButton.Location = [System.Drawing.Point]::new(251, 266)
$applyButton.Size = [System.Drawing.Size]::new(78, 34)
$applyButton.Enabled = $false
$form.Controls.Add($applyButton)
$form.AcceptButton = $applyButton

$defaultButton = [System.Windows.Forms.Button]::new()
$defaultButton.Text = '100% default'
$defaultButton.Location = [System.Drawing.Point]::new(335, 266)
$defaultButton.Size = [System.Drawing.Size]::new(92, 34)
$defaultButton.Enabled = $false
$form.Controls.Add($defaultButton)

$script:CanApply = $false

$startupCheck = [System.Windows.Forms.CheckBox]::new()
$startupCheck.Text = 'Reapply at sign-in if firmware forgets the limit'
$startupCheck.Location = [System.Drawing.Point]::new(22, 222)
$startupCheck.Size = [System.Drawing.Size]::new(390, 24)
$startupCheck.Enabled = $false
$form.Controls.Add($startupCheck)
$existingTask = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
if ($existingTask) { $startupCheck.Checked = $true }
$startupCheck.Add_CheckedChanged({
    try {
        if ($startupCheck.Checked) {
            $threshold = Get-HuaweiChargeThreshold
            Save-ChargeSettings -Start $threshold.Start -Stop $threshold.Stop
            Install-LogonRestoreTask
            $status.Text = 'Sign-in restore enabled. It runs once and exits; no background service.'
            $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 110, 45)
        } else {
            Remove-LogonRestoreTask
            $status.Text = 'Sign-in restore disabled; the firmware setting is left as-is.'
            $status.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
        }
    } catch {
        $startupCheck.Checked = $false
        $status.Text = "Startup setting failed: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::Firebrick
    }
})

$readAction = {
    try {
        $threshold = Get-HuaweiChargeThreshold
        $startBox.Value = $threshold.Start
        $stopBox.Value = $threshold.Stop
        $status.Text = "Firmware setting: start $($threshold.Start)%, stop $($threshold.Stop)%"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 110, 45)
        $script:CanApply = $true
        $applyButton.Enabled = $true
        $defaultButton.Enabled = $true
        $startupCheck.Enabled = $true
    }
    catch {
        $status.Text = "Read failed: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::Firebrick
        $script:CanApply = $false
        $applyButton.Enabled = $false
        $defaultButton.Enabled = $false
        $startupCheck.Enabled = $false
    }
}

$readButton.Add_Click($readAction)
$form.Add_Shown($readAction)

$applyButton.Add_Click({
    if (-not $script:CanApply) { return }
    $start = [int]$startBox.Value
    $stop = [int]$stopBox.Value
    if ($stop -le $start) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'The stop percentage must be higher than the start percentage.',
            'Invalid thresholds', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Set the firmware to start charging below $start% and stop at $stop%?",
        'Confirm charge limit', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $applyButton.Enabled = $false
        $status.Text = 'Applying and verifying firmware setting…'
        $form.Refresh()
        Set-HuaweiChargeThreshold -Start $start -Stop $stop
        $check = Get-HuaweiChargeThreshold
        if ($check.Start -ne $start -or $check.Stop -ne $stop) {
            throw "Read-back differs: firmware reports $($check.Start)% to $($check.Stop)% instead."
        }
        Save-ChargeSettings -Start $start -Stop $stop
        $status.Text = "Applied and verified: start $start%, stop $stop%."
        $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 110, 45)
    }
    catch {
        $status.Text = "Apply failed: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::Firebrick
    }
    finally {
        $applyButton.Enabled = $script:CanApply
    }
})

$defaultButton.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'Set the firmware thresholds to 0% start and 100% stop (no practical charge cap)?',
        'Restore standard charging', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $defaultButton.Enabled = $false
        Set-HuaweiChargeThreshold -Start 0 -Stop 100
        $check = Get-HuaweiChargeThreshold
        if ($check.Start -ne 0 -or $check.Stop -ne 100) {
            throw "Read-back differs: firmware reports $($check.Start)% to $($check.Stop)% instead."
        }
        Save-ChargeSettings -Start 0 -Stop 100
        $startBox.Value = 0
        $stopBox.Value = 100
        $status.Text = 'Standard 0–100% charging applied and verified.'
        $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 110, 45)
    }
    catch {
        $status.Text = "Restore failed: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::Firebrick
    }
    finally {
        $defaultButton.Enabled = $script:CanApply
    }
})

[void]$form.ShowDialog()
