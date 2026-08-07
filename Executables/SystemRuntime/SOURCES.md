# Sources
Some of the Playbook contains binary executables. This file provides some verification for those files, by listing the SHA256 hashes, sources, and when each was last verified/checked. Hashes were collected using `Get-FileHash` in PowerShell.

The root of the file paths listed here starts in `Executables`.

## Runtime-downloaded Edge removal helper

- Path: Not included in the repository; downloaded to a temporary directory as `Remove-Edge.exe`
    - Source: https://github.com/ShadowWhisperer/Remove-MS-Edge/releases/latest/download/Remove-Edge.exe
    - Repository: https://github.com/ShadowWhisperer/Remove-MS-Edge
    - Version: `latest` (not pinned)
    - SHA256 Hash: Not recorded or verified; the download URL currently tracks `latest`
- License: CC0-1.0
- Last Verified: 8/7/2026

## SetTimerResolution & MeasureSleep

- Path: `\SystemRuntime\Tools\SetTimerResolution.exe`
    - SHA256 Hash: `0515C2428E8960C751AD697ACA1C8D03BD43E2F0F1A0C0D2B4D998361C35EB57`
    - Source: https://github.com/valleyofdoom/TimerResolution/releases/download/SetTimerResolution-v1.0.0/SetTimerResolution.exe
    - Version: v1.0.0
- Path: `\SystemConfig\3. General Configuration\Timer Resolution\! MeasureSleep.exe`
    - SHA256 Hash: `377AC4DAF2590AE6AC4703E8B9B532CB1D2041EB0AFE7AD4F62546AF32BE1B11`
    - Source: https://github.com/valleyofdoom/TimerResolution/releases/download/MeasureSleep-v1.0.0/MeasureSleep.exe
    - Version: v1.0.0
- Repository: https://github.com/valleyofdoom/TimerResolution
- License: [GNU General Public License v3.0](https://github.com/valleyofdoom/TimerResolution/blob/main/LICENSE)
- Last Verified: 8/1/2026

## ViVeTool

> [!NOTE]  
> This is included in the Playbook and isn't in the SystemRuntime.

- Path: `Executables\ViVeTool-v0.3.4-IntelAmd.zip`
    - SHA256 hash: `CC27F073F3FE5DD2C3D947FAF558FD4B2F8E34454F812689B0D65EE8A52E4147`
    - Source: https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/ViVeTool-v0.3.4-IntelAmd.zip
    - Version: v0.3.4
- Path: `Executables\ViVeTool-v0.3.4-SnapdragonArm64.zip`
    - SHA256 hash: `30AD9A4912686355BFCE60E1D7BEF608735475B7E2160D67418EED8F5E3BA8C7`
    - Source: https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/ViVeTool-v0.3.4-SnapdragonArm64.zip
    - Version: v0.3.4
- Repository: https://github.com/thebookisclosed/ViVe
- License: [GNU General Public License v3.0](https://github.com/thebookisclosed/ViVe/blob/master/LICENSE)
- Last Verified: 7/22/2026
