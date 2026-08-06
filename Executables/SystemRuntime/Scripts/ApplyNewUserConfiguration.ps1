$runPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'SystemConfigNewUserSetup'
$windir = [Environment]::GetFolderPath('Windows')
$systemConfig = Join-Path $windir 'SystemConfig'
$systemRuntime = Join-Path $windir 'SystemRuntime'

function Invoke-UserSetting {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "User setting script was not found: '$Path'."
    }

    & $Path /justcontext
    if ($LASTEXITCODE -ne 0) {
        throw "User setting script failed with exit code $LASTEXITCODE`: '$Path'."
    }
}

try {
    & "$systemRuntime\InitializePowerShell.ps1"

    if (
        -not (Test-Path -LiteralPath $systemConfig -PathType Container) -or
        -not (Test-Path -LiteralPath $systemRuntime -PathType Container)
    ) {
        throw 'User setup files were not found.'
    }

    $title = 'Preparing user settings...'
    $Host.UI.RawUI.WindowTitle = $title
    Write-Host $title -ForegroundColor Yellow
    Write-Host $('-' * ($title.Length + 3)) -ForegroundColor Yellow
    Write-Host "You'll be logged out in 10 to 20 seconds, and once you login again, your new account will be ready for use."

    if ([System.Environment]::OSVersion.Version.Build -ge 22000) {
        Invoke-UserSetting -Path (
            Join-Path $systemConfig '4. Interface Tweaks\Context Menus\Windows 11\Old Context Menu (default).cmd'
        )
        Invoke-UserSetting -Path (
            Join-Path $systemConfig '4. Interface Tweaks\File Explorer Customization\Gallery\Disable Gallery (default).cmd'
        )
    }

    Invoke-UserSetting -Path (
        Join-Path $systemConfig '3. General Configuration\File Sharing\Network Navigation Pane\Disable Network Navigation Pane (default).cmd'
    )
    Invoke-UserSetting -Path (
        Join-Path $systemConfig '4. Interface Tweaks\File Explorer Customization\Automatic Folder Discovery\Disable Automatic Folder Discovery (default).cmd'
    )
    Invoke-UserSetting -Path (
        Join-Path $systemConfig '4. Interface Tweaks\Visual Effects (Animations)\Optimized Visual Effects (default).cmd'
    )

    $browser = $null
    try {
        $browser = Get-ItemPropertyValue `
            -Path 'HKLM:\SOFTWARE\SystemConfig\SetupOptions' `
            -Name 'Browser' `
            -ErrorAction Stop
    }
    catch {
        Write-Warning 'No saved browser selection was found; using the taskbar fallback.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$browser)) {
        $browser = $null
    }

    $taskbarScript = Join-Path $systemRuntime 'Scripts\ConfigureTaskbarPins.ps1'
    if (-not (Test-Path -LiteralPath $taskbarScript -PathType Leaf)) {
        throw "Taskbar pin script was not found: '$taskbarScript'."
    }

    & $taskbarScript -Browser $browser -CurrentUserOnly -NoExplorerStop
    if (-not $?) {
        throw 'Failed to configure taskbar pins for the current user.'
    }

    $searchPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
    $null = New-Item -Path $searchPath -Force -ErrorAction Stop
    $null = New-ItemProperty `
        -Path $searchPath `
        -Name 'SearchboxTaskbarMode' `
        -Value 1 `
        -PropertyType DWord `
        -Force `
        -ErrorAction Stop

    $runValues = Get-ItemProperty -LiteralPath $runPath -ErrorAction SilentlyContinue
    if (
        $null -ne $runValues -and
        $runValues.PSObject.Properties.Name -contains $runValueName
    ) {
        Remove-ItemProperty -LiteralPath $runPath -Name $runValueName -ErrorAction Stop
    }

    $remainingRunValues = Get-ItemProperty -LiteralPath $runPath -ErrorAction SilentlyContinue
    if (
        $null -ne $remainingRunValues -and
        $remainingRunValues.PSObject.Properties.Name -contains $runValueName
    ) {
        throw "Failed to remove '$runValueName' from the current user's Run key."
    }
}
catch {
    Write-Host 'The playbook could not finish configuring this user. Setup will retry at the next sign-in.' -ForegroundColor Red
    Write-Error $_
    exit 1
}

Start-Sleep -Seconds 5
& "$windir\System32\logoff.exe"
