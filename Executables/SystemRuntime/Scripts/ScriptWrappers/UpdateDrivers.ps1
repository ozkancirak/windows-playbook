[CmdletBinding()]
param (
    [switch]$RestartAfterUpdate,
    [switch]$Silent
)

$script:SelectedUpdates = @()

function Test-Admin {
    param (
        [System.Collections.IDictionary]$ScriptBoundParameters
    )

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Restarting script with administrator privileges..."

        $forwardedArguments = foreach ($parameter in $ScriptBoundParameters.GetEnumerator()) {
            if (
                $parameter.Value -is [System.Management.Automation.SwitchParameter] -and
                $parameter.Value.IsPresent
            ) {
                "-$($parameter.Key)"
            }
        }

        $elevationArguments = @(
            '-ExecutionPolicy Bypass'
            '-NoProfile'
            ('-File "{0}"' -f $PSCommandPath)
        )
        $elevationArguments += $forwardedArguments
        $elevationArgumentString = $elevationArguments -join ' '

        Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList $elevationArgumentString -Verb RunAs
        exit
    }
}
Test-Admin -ScriptBoundParameters $PSBoundParameters

function Install-PSWindowsUpdateModule {
    $requiredVersion = [version]'2.2.1.5'
    $minimumNuGetVersion = [version]'2.8.5.201'

    $requiredModule = Get-Module -ListAvailable -Name 'PSWindowsUpdate' |
        Where-Object { $_.Version -eq $requiredVersion } |
        Select-Object -First 1

    if (-not $requiredModule) {
        $nugetProvider = Get-PackageProvider -ListAvailable -Name 'NuGet' -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if (-not $nugetProvider -or $nugetProvider.Version -lt $minimumNuGetVersion) {
            Install-PackageProvider -Name 'NuGet' -MinimumVersion $minimumNuGetVersion `
                -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop | Out-Null
        }

        $null = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
        Install-Module -Name 'PSWindowsUpdate' -RequiredVersion $requiredVersion `
            -Repository 'PSGallery' -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    }

    $loadedModules = @(
        Import-Module -Name 'PSWindowsUpdate' -RequiredVersion $requiredVersion `
            -Force -PassThru -ErrorAction Stop
    )
    if ($requiredVersion -notin $loadedModules.Version) {
        throw "PSWindowsUpdate $requiredVersion could not be loaded."
    }
}

function Enable-MicrosoftUpdate {
    Write-Host "Enabling Microsoft Update for driver updates..."
    Add-WUServiceManager -ServiceID "7971f918-a847-4430-9279-4a52d1efe18d" -AddServiceFlag 7 -Confirm:$false | Out-Null
}

function Show-DriverSelection {
    param (
        [array]$Updates
    )
    if ($Updates.Count -eq 0) {
        return @()
    }

    Add-Type -AssemblyName PresentationFramework

    $Window = New-Object System.Windows.Window
    $Window.Title = "Select drivers to install"
    $Window.Width = 500
    $Window.Height = 400
    $Window.WindowStartupLocation = "CenterScreen"

    $StackPanel = New-Object System.Windows.Controls.StackPanel

    $ListBox = New-Object System.Windows.Controls.ListBox
    $ListBox.SelectionMode = "Extended"
    foreach ($update in $Updates) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = $update.Title.ToString().Trim()
        $item.Tag = $update
        $ListBox.Items.Add($item) | Out-Null
    }
    $StackPanel.Children.Add($ListBox) | Out-Null

    $OKButton = New-Object System.Windows.Controls.Button
    $OKButton.Content = "OK"
    $OKButton.Margin = "10,10,10,10"
    $OKButton.Add_Click({
        $Window.Tag = @($ListBox.SelectedItems | ForEach-Object { $_.Tag })
        $Window.Close()
    })
    $StackPanel.Children.Add($OKButton) | Out-Null

    $Window.Content = $StackPanel
    $Window.ShowDialog() | Out-Null

    return @($Window.Tag | Where-Object { $null -ne $_ })
}

function Update-Drivers {
    Write-Host "Checking for driver updates..."
    $Updates = Get-WUList -MicrosoftUpdate -Category "Drivers"

    if ($Updates.Count -gt 0) {
        Write-Host "Available driver updates:"
        $selection = Show-DriverSelection -Updates $Updates

        $selection = @($selection)

        if ($selection.Count -gt 0) {
            Write-Host "Installing selected driver updates..."
            $selection | Format-Table ComputerName, Status, KB, Size, Title -AutoSize

            $updateIds = @($selection | ForEach-Object { $_.Identity.UpdateID } | Where-Object { $_ })
            if ($updateIds.Count -ne $selection.Count) {
                Write-Error "Could not resolve the UpdateID of every selected driver update; aborting instead of installing unselected updates."
                return $false
            }

            $installResults = @(Get-WUInstall -MicrosoftUpdate -Category "Drivers" -UpdateID $updateIds -AcceptAll -IgnoreReboot -Confirm:$false -ErrorAction Stop)
            $installedUpdateIds = @(
                $installResults |
                    Where-Object { [string]$_.Status -match '^..I' } |
                    ForEach-Object { $_.Identity.UpdateID } |
                    Where-Object { $_ }
            )
            $notInstalledUpdateIds = @($updateIds | Where-Object { $_ -notin $installedUpdateIds })
            if ($notInstalledUpdateIds.Count -gt 0) {
                Write-Error "One or more selected driver updates were not installed successfully; restart was skipped."
                return $false
            }

            Write-Host "Driver updates installed successfully!"

            if ($RestartAfterUpdate) {
                Write-Host "Restarting the system in 10 seconds..."
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            }
            elseif (-not $Silent) {
                $restartChoice = Read-Host "Do you want to restart now? (Y/N)"
                if ($restartChoice -match "^[Yy]$") {
                    Write-Host "Restarting the system in 10 seconds..."
                    Start-Sleep -Seconds 10
                    Restart-Computer -Force
                }
            }
        }
        else {
            Write-Host "No drivers were selected for update."
        }
    }
    else {
        Write-Host "No driver updates found."
    }
}

Install-PSWindowsUpdateModule
Enable-MicrosoftUpdate
Update-Drivers

if (-not $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Silent')) {
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
