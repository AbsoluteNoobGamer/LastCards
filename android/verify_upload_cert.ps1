# Verifies the Play upload key SHA-1 in upload-keystore.p12 matches your expectations.
# Run from the android/ directory, or: pwsh -File android/verify_upload_cert.ps1
# Compare output to: Play Console > App integrity > App signing > Upload key certificate
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$jks = Join-Path $root "upload-keystore.p12"
$props = Join-Path $root "key.properties"
$kt = "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe"
if (-not (Test-Path $kt)) { $kt = "keytool" }

if (-not (Test-Path $props)) {
    Write-Error "Missing key.properties. Cannot read storePassword."
    exit 1
}
if (-not (Test-Path $jks)) { Write-Error "Missing $jks"; exit 1 }

$line = Get-Content $props -ErrorAction Stop | Where-Object { $_ -match '^\s*storePassword=' } | Select-Object -First 1
if (-not $line) { Write-Error "storePassword= not found in key.properties"; exit 1 }
$pass = $line -replace '^\s*storePassword=','' | ForEach-Object { $_.Trim() }

$aliasLine = Get-Content $props | Where-Object { $_ -match '^\s*keyAlias=' } | Select-Object -First 1
$alias = if ($aliasLine) { ($aliasLine -replace '^\s*keyAlias=','').Trim() } else { "upload" }

Write-Host "Keystore: $jks"
Write-Host "Alias: $alias"
& $kt -list -v -keystore $jks -storepass $pass 2>&1 | Select-String "SHA1|Alias name|Invalid|Exception"
Write-Host ""
Write-Host "This SHA-1 (under Certificate fingerprints) must match Upload key in Play Console."
