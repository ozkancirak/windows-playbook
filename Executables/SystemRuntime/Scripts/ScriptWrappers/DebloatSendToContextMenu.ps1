param (
    [array]$Disable,
    [array]$Enable
)

$removableDrivePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$removableDriveValue = "NoDrivesInSendToMenu"
# First value in an array is the disable, second is enable
$items = @{
    "Removable Drives" = @(
        { New-ItemProperty -Path $removableDrivePath -Name $removableDriveValue -Value 1 -PropertyType DWORD -Force },
        { Remove-ItemProperty -Path $removableDrivePath -Name $removableDriveValue -Force -EA 0 }
    )
}
$sendTo = Get-ChildItem ([Environment]::GetFolderPath('SendTo')) -Force
$sys32 = [Environment]::GetFolderPath('System')
$shell = New-Object -Com WScript.Shell
$windir = [Environment]::GetFolderPath('Windows')
& "$windir\SystemRuntime\InitializePowerShell.ps1"

# Get Bluetooth path
foreach ($lnk in (($sendTo | Where-Object { $_.Extension -eq ".lnk" }).FullName)) {
    $target = $shell.CreateShortcut($lnk).TargetPath
    if ($target -eq "$sys32\fsquirt.exe") {
        $items["Bluetooth"] = $lnk
        $blueFound = $true
    } elseif ($target -eq "$sys32\WFS.exe") {
        $items["Fax recipient"] = $lnk
        $faxFound = $true
    }

    if ($faxFound -and $blueFound) {
        break
    }
}

# Items with specific extensions
foreach ($ext in @{
    "Compressed (zipped) folder" = "ZFSendToTarget"
    "Desktop (create shortcut)" = "DeskLink"
    "Mail recipient" = "MAPIMail"
    "Documents" = "mydocs"
}.GetEnumerator()) {
    $path = $sendTo | Where-Object { $_.Extension -eq ".$($ext.Value)" } | Select-Object -First 1
    if ($path) { $items[$ext.Key] = $path.FullName }
}

# Enable/disable functions
function EnableSendTo($value) {
    if ($value -is [string]) {
        $item = Get-Item -LiteralPath $value -Force
        $item.Attributes = $item.Attributes -band -bnot [System.IO.FileAttributes]::Hidden
    } elseif ($value -is [array]) {
        & $value[1] | Out-Null
    }
}
function DisableSendTo($value) {
    if ($value -is [string]) {
        $item = Get-Item -LiteralPath $value -Force
        $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
    } elseif ($value -is [array]) {
        & $value[0] | Out-Null
    }
}

function Show-SendToChoiceDialog {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Choices
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Send To Debloat"
    $form.ClientSize = New-Object System.Drawing.Size -ArgumentList 560, 360
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $prompt = New-Object System.Windows.Forms.Label
    $prompt.Text = "Tick the 'Send To' context menu items that you want to enable here (un-checked items are disabled)"
    $prompt.Location = New-Object System.Drawing.Point -ArgumentList 12, 12
    $prompt.Size = New-Object System.Drawing.Size -ArgumentList 536, 42
    $prompt.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )

    $choiceList = New-Object System.Windows.Forms.CheckedListBox
    $choiceList.CheckOnClick = $true
    $choiceList.IntegralHeight = $false
    $choiceList.Location = New-Object System.Drawing.Point -ArgumentList 12, 58
    $choiceList.Size = New-Object System.Drawing.Size -ArgumentList 536, 248
    $choiceList.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    foreach ($choice in $Choices) {
        [void]$choiceList.Items.Add($choice, $false)
    }

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $okButton.Location = New-Object System.Drawing.Point -ArgumentList 392, 320
    $okButton.Size = New-Object System.Drawing.Size -ArgumentList 75, 28
    $okButton.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point -ArgumentList 473, 320
    $cancelButton.Size = New-Object System.Drawing.Size -ArgumentList 75, 28
    $cancelButton.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )

    [void]$form.Controls.Add($prompt)
    [void]$form.Controls.Add($choiceList)
    [void]$form.Controls.Add($okButton)
    [void]$form.Controls.Add($cancelButton)
    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    try {
        $dialogResult = $form.ShowDialog()
        $selectedChoices = @(
            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
                foreach ($checkedItem in $choiceList.CheckedItems) {
                    [string]$checkedItem
                }
            }
        )

        [pscustomobject]@{
            Confirmed = $dialogResult -eq [System.Windows.Forms.DialogResult]::OK
            Choices = $selectedChoices
        }
    } finally {
        $form.Dispose()
    }
}

# Args
if ($Enable) {
    foreach ($item in $items.GetEnumerator()) {
        foreach ($itemToEnable in $Enable) {
            if ($item.Key -like "$itemToEnable") {
                EnableSendTo $item.Value
            }
        }
    }
    exit
} elseif ($Disable) {
    foreach ($item in $items.GetEnumerator()) {
        foreach ($itemToDisable in $Disable) {
            if ($item.Key -like "$itemToDisable") {
                DisableSendTo $item.Value
            }
        }
    }
    exit
}

# Prompt user
$choiceNames = @($items.Keys)
$choiceResult = Show-SendToChoiceDialog -Choices $choiceNames
if (-not $choiceResult.Confirmed) {
    exit
}
$choices = @($choiceResult.Choices)

# Loop through choices
foreach ($item in $items.GetEnumerator()) {
    $value = $item.Value
    # If it's in the choices, enable
    if ($item.Key -in $choices) {
        EnableSendTo $value
        continue
    }
    # If it's in the choices, disable
    if ($item.Key -notin $choices) {
        DisableSendTo $value
        continue
    }
}

# Restart Explorer prompt
if ((Read-MessageBox -Title "Send To Debloat" -Body 'Would you like to restart Windows Explorer? This will finalize the Send-To changes.' -Icon Info) -eq 'Yes') {
    Stop-Process -Name explorer -Force
}
