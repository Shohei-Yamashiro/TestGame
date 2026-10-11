# Builds the Windows release into build/windows and zips it for distribution.
# The game is a single .exe (the PCK is embedded); the licence notices go alongside it.
# Needs the Godot 4.7.2 export templates (Editor > Manage Export Templates, or extract the .tpz into
# %APPDATA%\Godot\export_templates\4.7.2.stable).
# Usage: powershell -ExecutionPolicy Bypass -File tools\export\export_windows.ps1 [-Godot <console exe>]
param(
    [string]$Godot = "D:\Godot\lib\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$project = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$out = Join-Path $project "build\windows"
$name = "NEON GEOMETRY"

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null

# Keep the shipped notices in step with the engine before packing them.
& $Godot --headless --path $project -s res://tools/licenses/generate_notices.gd | Out-Null
& $Godot --headless --path $project --export-release "Windows Desktop" (Join-Path $out "$name.exe")
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $out "$name.exe"))) {
    throw "export failed (exit $LASTEXITCODE)"
}
Copy-Item (Join-Path $project "THIRD-PARTY-NOTICES.txt") $out

$version = (Select-String -Path (Join-Path $project "project.godot") -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
$zip = Join-Path $project "build\NEON_GEOMETRY-$version-windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip
Get-ChildItem $out | Format-Table Name, Length -AutoSize | Out-String | Write-Host
Write-Host "ZIP $zip"
