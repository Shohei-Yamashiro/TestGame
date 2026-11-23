# Builds the Windows release into build/windows and zips it for distribution.
# The game is a single .exe (the PCK is embedded); licence notices and portfolio docs go alongside it.
# Needs the Godot 4.7.2 export templates (Editor > Manage Export Templates, or extract the .tpz into
# %APPDATA%\Godot\export_templates\4.7.2.stable).
# Needs Microsoft Edge to print the guide PDF (tools/docs/build-docs.ps1).
# Usage: powershell -ExecutionPolicy Bypass -File tools\export\export_windows.ps1 [-Godot <console exe>]
param(
    [string]$Godot = "D:\Godot\lib\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$project = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$out = Join-Path $project "build\windows"
$name = "NEON GEOMETRY"
$buildDocs = Join-Path $project "tools\docs\build-docs.ps1"

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null

# Keep the shipped notices in step with the engine before packing them.
& $Godot --headless --path $project -s res://tools/licenses/generate_notices.gd | Out-Null
& $Godot --headless --path $project --export-release "Windows Desktop" (Join-Path $out "$name.exe")
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $out "$name.exe"))) {
    throw "export failed (exit $LASTEXITCODE)"
}

Copy-Item (Join-Path $project "THIRD-PARTY-NOTICES.txt") $out
Copy-Item (Join-Path $project "LICENSE") $out
Copy-Item (Join-Path $project "docs\distribution\LICENSE.txt") $out
Copy-Item (Join-Path $project "docs\distribution\README.txt") $out

$guidePdf = Join-Path $project "build\NEON_GEOMETRY-guide.pdf"
& $buildDocs -Html (Join-Path $project "docs\portfolio\guide.html") -Pdf $guidePdf | Out-Null
if (-not (Test-Path $guidePdf)) { throw "guide PDF was not created" }
# Japanese display name for readers (UTF-8 file so this script stays ASCII-only).
# Copied beside the zip (for Drive preview) and into the zip folder.
$pdfJaName = (Get-Content -LiteralPath (Join-Path $project "docs\portfolio\pdf-filename.txt") -Encoding UTF8 -Raw).Trim()
$pdfBesideZip = Join-Path $project "build\$pdfJaName"
Copy-Item $guidePdf $pdfBesideZip -Force
Copy-Item $pdfBesideZip (Join-Path $out $pdfJaName)

$version = (Select-String -Path (Join-Path $project "project.godot") -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
$zip = Join-Path $project "build\NEON_GEOMETRY-$version-windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip
Get-ChildItem $out | Format-Table Name, Length -AutoSize | Out-String | Write-Host
Write-Host "ZIP $zip"
Write-Host "PDF $pdfBesideZip"
