# Builds dist/TrueSync-Connector.msix for Microsoft Store upload (Windows only).
# The Store signs the package, so it is left unsigned here.
# Identity values come from Partner Center > Product management > Product identity,
# stored in windows/msix/identity.json.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$identity = Get-Content 'windows/msix/identity.json' -Raw | ConvertFrom-Json
foreach ($field in 'name', 'publisher', 'publisherDisplayName') {
  if ([string]::IsNullOrWhiteSpace($identity.$field)) { throw "windows/msix/identity.json is missing '$field'." }
}

[xml]$project = Get-Content 'TrueSync.Connector/TrueSync.Connector.csproj'
$version = ($project.Project.PropertyGroup | Where-Object { $_.Version } | Select-Object -First 1).Version
$parts = @($version.Split('.')) + @('0', '0', '0')
# Store packages require the fourth (revision) part to be 0.
$packageVersion = '{0}.{1}.{2}.0' -f $parts[0], $parts[1], $parts[2]

$layout = 'dist/msix-layout'
$output = 'dist/TrueSync-Connector.msix'
Remove-Item $layout, $output -Recurse -Force -ErrorAction SilentlyContinue

dotnet publish TrueSync.Connector -c Release -r win-x64 --self-contained true -o $layout
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }

Copy-Item 'windows/msix/Assets' "$layout/Assets" -Recurse
$manifest = (Get-Content 'windows/msix/AppxManifest.xml' -Raw).
  Replace('__IDENTITY_NAME__', [Security.SecurityElement]::Escape($identity.name)).
  Replace('__IDENTITY_PUBLISHER__', [Security.SecurityElement]::Escape($identity.publisher)).
  Replace('__PUBLISHER_DISPLAY_NAME__', [Security.SecurityElement]::Escape($identity.publisherDisplayName)).
  Replace('__VERSION__', $packageVersion)
Set-Content "$layout/AppxManifest.xml" $manifest -Encoding UTF8

$makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" |
  Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
if (-not $makeappx) { throw 'makeappx.exe not found. Install the Windows 10/11 SDK.' }

& $makeappx.FullName pack /d $layout /p $output /o
if ($LASTEXITCODE -ne 0) { throw 'makeappx pack failed.' }
Write-Host "Built $output (version $packageVersion)"
