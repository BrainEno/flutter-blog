# Windows control-flow tests with fake flutter/adb/emulator; not a real AVD test.
# Runs under the Windows PowerShell 5.1 used by run_android.cmd.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$temp = Join-Path ([IO.Path]::GetTempPath()) ('belog script test ' + [Guid]::NewGuid().ToString('N'))
$bin = Join-Path $temp 'fake tools'
$log = Join-Path $temp 'calls.log'
$config = Join-Path $temp 'config with spaces.json'
$marker = Join-Path $temp 'started.txt'
$pidFile = Join-Path $temp 'emulator.pid'
$oldPath = $env:PATH
$pubHostedUrlWasSet = Test-Path Env:PUB_HOSTED_URL
$oldPubHostedUrl = $env:PUB_HOSTED_URL
$engine = (Get-Command powershell.exe).Source

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Run-Subject([string[]]$ExtraArguments, [string]$ConfigPath = $config) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& $engine -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/run_android.ps1') -Config $ConfigPath -BootTimeoutSeconds 4 @ExtraArguments 2>&1 | Out-String)
        return @{ ExitCode = $LASTEXITCODE; Output = $output }
    } finally { $ErrorActionPreference = $oldPreference }
}

try {
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    @'
@echo off
if "%~1"=="--version" (
  echo {"frameworkVersion":"%MOCK_FLUTTER_VERSION%","dartSdkVersion":"%MOCK_DART_VERSION%"}
  exit /b 0
)
echo flutter %*>>"%BELOG_TEST_LOG%"
echo PUB_HOSTED_URL=%PUB_HOSTED_URL%>>"%BELOG_TEST_LOG%"
if "%~1"=="pub" (
  if "%MOCK_HASH_MISMATCH_PUB%"=="1" if "%PUB_HOSTED_URL%"=="https://pub.flutter-io.cn" (
    echo Downloaded archive for sample-1.0.0 had wrong content-hash. 1>&2
    exit /b 75
  )
  if "%MOCK_FAIL_PUB%"=="1" exit /b 2
)
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $bin 'flutter.cmd') -Encoding Ascii
    @'
@echo off
echo adb %*>>"%BELOG_TEST_LOG%"
echo MOCK_FAIL_REVERSE=%MOCK_FAIL_REVERSE%>>"%BELOG_TEST_LOG%"
if "%MOCK_NATIVE_STDERR%"=="1" echo adb daemon notice 1>&2
if "%MOCK_FAIL_ADB%"=="1" exit /b 9
if "%~1"=="devices" (
  echo List of devices attached
  if "%MOCK_NO_EMULATOR%"=="1" if not exist "%BELOG_TEST_STARTED%" exit /b 0
  echo emulator-5554    device
  exit /b 0
)
if "%~3"=="emu" (
  echo Demo
  echo OK
  exit /b 0
)
if "%~3"=="shell" (
  if "%MOCK_NEVER_BOOT%"=="1" (echo 0) else (echo 1)
  exit /b 0
)
if "%~3"=="reverse" (
  if "%MOCK_FAIL_REVERSE%"=="1" exit /b 8
  exit /b 0
)
exit /b 1
'@ | Set-Content -LiteralPath (Join-Path $bin 'adb.cmd') -Encoding Ascii
    $emulator = Join-Path $bin 'emulator.exe'
    Add-Type -OutputAssembly $emulator -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Diagnostics;
public static class FakeEmulator {
    public static void Main(string[] args) {
        if (args.Length > 0 && args[0] == "-list-avds") {
            if (Environment.GetEnvironmentVariable("MOCK_NATIVE_STDERR") == "1") Console.Error.WriteLine("AVD list notice");
            if (Environment.GetEnvironmentVariable("MOCK_FAIL_AVD_LIST") == "1") Environment.Exit(7);
            Console.WriteLine("Demo");
        } else if (args.Length > 1 && args[0] == "-avd") {
            File.WriteAllText(Environment.GetEnvironmentVariable("BELOG_TEST_STARTED"), args[1]);
            File.WriteAllText(Environment.GetEnvironmentVariable("BELOG_TEST_PID"), Process.GetCurrentProcess().Id.ToString());
            Thread.Sleep(15000);
        }
    }
}
'@
    $env:PATH = $bin + ';' + $oldPath
    $env:BELOG_TEST_LOG = $log
    $env:BELOG_TEST_STARTED = $marker
    $env:BELOG_TEST_PID = $pidFile
    $env:MOCK_NO_EMULATOR = ''
    $env:MOCK_NEVER_BOOT = ''
    $env:MOCK_FAIL_PUB = ''
    $env:MOCK_HASH_MISMATCH_PUB = ''
    $env:MOCK_FAIL_REVERSE = ''
    $env:MOCK_FLUTTER_VERSION = '3.47.8'
    $env:MOCK_DART_VERSION = '3.10.4'
    # Never leave a first-run prompt waiting in a non-interactive test process.
    $env:BELOG_NO_PROMPT = '1'
    '{"API_BASE_URL":"http://10.0.2.2:8787","WEB_BASE_URL":""}' | Set-Content -LiteralPath $config -Encoding Ascii

    $reuse = Run-Subject @('-Avd', 'Demo')
    Assert-True ($reuse.ExitCode -eq 0) "Existing emulator scenario failed: $($reuse.Output)"
    $calls = Get-Content -LiteralPath $log -Raw
    Assert-True ($calls -match 'flutter run --debug --no-pub -d emulator-5554') 'Did not target the existing emulator.'
    Assert-True ($calls -notmatch 'adb .* reverse ') 'The emulator host alias should not need adb reverse.'
    Assert-True ($calls -match 'BELOG_DEV_BACKEND_CHECK=true') 'Missing local API probe define.'
    Assert-True ($calls.Contains($config)) 'Config path with spaces was not passed intact.'
    Assert-True (!(Test-Path $marker)) 'An existing AVD should not be started again.'

    # A loopback API origin uses the device's localhost, so forward its port
    # back to the host before starting Flutter.
    '{"API_BASE_URL":"http://localhost:4000","WEB_BASE_URL":""}' | Set-Content -LiteralPath $config -Encoding Ascii
    Remove-Item -LiteralPath $log -Force
    $loopback = Run-Subject @()
    Assert-True ($loopback.ExitCode -eq 0) "Loopback API scenario failed: $($loopback.Output)"
    $calls = Get-Content -LiteralPath $log -Raw
    Assert-True ($calls -match 'adb -s emulator-5554 reverse tcp:4000 tcp:4000') 'localhost API did not set up adb reverse.'
    Assert-True ($loopback.Output -match 'ADB reverse is active') 'The loopback forwarding was not reported.'
    Assert-True ($calls -match 'flutter run --debug --no-pub -d emulator-5554') 'Flutter was not started after forwarding.'

    $env:MOCK_FAIL_REVERSE = '1'
    Remove-Item -LiteralPath $log -Force
    $reverseFailure = Run-Subject @()
    $reverseLog = Get-Content -LiteralPath $log -Raw
    Assert-True ($reverseFailure.ExitCode -ne 0 -and $reverseFailure.Output -match 'Could not forward emulator localhost:4000') "An adb reverse failure was ignored (exit $($reverseFailure.ExitCode)): $($reverseFailure.Output) Mock log: $reverseLog"
    Assert-True ($reverseLog -notmatch 'flutter run') 'Flutter started without the required loopback tunnel.'
    $env:MOCK_FAIL_REVERSE = ''

    # A mirror checksum failure retries once against pub.dev, then Flutter uses
    # --no-pub so it cannot contact the broken mirror a second time.
    '{"API_BASE_URL":"https://api.real-site.dev","WEB_BASE_URL":""}' | Set-Content -LiteralPath $config -Encoding Ascii
    $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
    $env:MOCK_HASH_MISMATCH_PUB = '1'
    Remove-Item -LiteralPath $log -Force
    $hashFallback = Run-Subject @()
    Assert-True ($hashFallback.ExitCode -eq 0) "Pub mirror hash retry failed: $($hashFallback.Output)"
    Assert-True ($hashFallback.Output -match 'Retrying dependency resolution once against canonical https://pub.dev') 'The official Pub retry was not explained.'
    $hostLines = @(Get-Content -LiteralPath $log | Where-Object { $_ -like 'PUB_HOSTED_URL=*' })
    Assert-True ($hostLines.Count -eq 3) "Expected mirror, official retry and run invocations; got $($hostLines.Count)."
    Assert-True ($hostLines[0] -eq 'PUB_HOSTED_URL=https://pub.flutter-io.cn') 'The first attempt did not preserve the configured mirror.'
    Assert-True ($hostLines[1] -eq 'PUB_HOSTED_URL=https://pub.dev') 'A checksum mismatch did not retry through canonical pub.dev.'
    Assert-True ($hostLines[2] -eq 'PUB_HOSTED_URL=https://pub.flutter-io.cn') 'The mirror environment was not restored after dependency resolution.'
    Assert-True ((Get-Content -LiteralPath $log -Raw) -match 'flutter run --debug --no-pub -d emulator-5554') 'Flutter might re-fetch packages from the failing mirror.'
    $env:MOCK_HASH_MISMATCH_PUB = ''

    Remove-Item -LiteralPath $log -Force
    $env:MOCK_NO_EMULATOR = '1'
    # Successful adb/emulator commands may write startup notices to stderr.
    $env:MOCK_NATIVE_STDERR = '1'
    $new = Run-Subject @()
    Assert-True ($new.ExitCode -eq 0) "Fresh AVD scenario (with native stderr) failed: $($new.Output)"
    Assert-True (Test-Path $marker) 'The selected AVD was not launched.'
    Assert-True ((Get-Content $marker -Raw).Trim() -eq 'Demo') 'Started the wrong AVD.'
    Assert-True ((Get-Content $log -Raw) -match 'flutter run --debug --no-pub -d emulator-5554') 'Fresh AVD was not used.'
    Remove-Item -LiteralPath $marker -Force
    $env:MOCK_FAIL_AVD_LIST = '1'
    $failedList = Run-Subject @()
    Assert-True ($failedList.ExitCode -ne 0 -and $failedList.Output -match 'Could not list Android AVDs') 'AVD listing failure was ignored.'
    $env:MOCK_FAIL_AVD_LIST = ''
    $env:MOCK_NO_EMULATOR = ''
    $env:MOCK_NATIVE_STDERR = ''

    Remove-Item -LiteralPath $log -Force
    '{"API_BASE_URL":"https://user:badsecret@api.real-site.dev"}' | Set-Content -LiteralPath $config -Encoding Ascii
    $bad = Run-Subject @()
    Assert-True ($bad.ExitCode -ne 0) 'Credential-bearing config was accepted.'
    Assert-True (!$bad.Output.Contains('badsecret')) 'The error printed credential-bearing configuration.'
    Assert-True (!(Test-Path $log)) 'Invalid config should fail before invoking adb or flutter pub get.'

    '{"API_BASE_URL":"https://api.real-site.dev","SECRET":"badsecret"}' | Set-Content -LiteralPath $config -Encoding Ascii
    $badKey = Run-Subject @()
    Assert-True ($badKey.ExitCode -ne 0) 'Unknown config keys were accepted.'
    Assert-True (!$badKey.Output.Contains('badsecret')) 'The error printed a secret.'

    '{"API_BASE_URL":"https://api.real-site.dev"}' | Set-Content -LiteralPath $config -Encoding Ascii
    $env:MOCK_FAIL_ADB = '1'
    $failedAdb = Run-Subject @()
    Assert-True ($failedAdb.ExitCode -ne 0 -and $failedAdb.Output -match 'adb devices failed') 'adb failure was ignored.'
    $env:MOCK_FAIL_ADB = ''
    $env:MOCK_FAIL_PUB = '1'
    $failedPub = Run-Subject @()
    Assert-True ($failedPub.ExitCode -ne 0) 'flutter pub get failure was ignored.'
    $env:MOCK_FAIL_PUB = ''
    $env:MOCK_NEVER_BOOT = '1'
    $timeout = Run-Subject @()
    Assert-True ($timeout.ExitCode -ne 0 -and $timeout.Output -match 'timed out') 'Boot timeout was not surfaced.'

    # A different but still compatible SDK must not block local debugging.
    $env:MOCK_NEVER_BOOT = ''
    $env:MOCK_FLUTTER_VERSION = '3.41.9'
    $env:MOCK_DART_VERSION = '3.10.4'
    $drift = Run-Subject @()
    Assert-True ($drift.ExitCode -eq 0) "A compatible SDK version was refused: $($drift.Output)"
    Assert-True ($drift.Output -match 'CI and release builds use 3\.47\.8') 'The version drift warning was not printed.'
    # Below pubspec.yaml's Dart constraint the run is refused, with the way out.
    $env:MOCK_DART_VERSION = '3.4.0'
    $tooOld = Run-Subject @()
    Assert-True ($tooOld.ExitCode -ne 0) 'An SDK below the Dart constraint was accepted.'
    Assert-True ($tooOld.Output -match '3\.47\.8' -and $tooOld.Output -match 'flutter upgrade') 'The refusal did not explain how to upgrade.'
    Assert-True ($tooOld.Output -match 'remote-tracking branch') 'The refusal did not cover the broken-SDK upgrade case.'
    # Opting into strictness refuses the same compatible SDK.
    $env:MOCK_DART_VERSION = '3.10.4'
    $env:BELOG_STRICT_FLUTTER_VERSION = '1'
    $strictRun = Run-Subject @()
    Assert-True ($strictRun.ExitCode -ne 0) 'Strict mode accepted a different SDK.'
    $env:BELOG_STRICT_FLUTTER_VERSION = ''
    $env:MOCK_FLUTTER_VERSION = '3.47.8'

    # First run: a missing config is created from -ApiBaseUrl instead of failing.
    $fresh = Join-Path $temp 'first run env.json'
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $created = Run-Subject @('-ApiBaseUrl', 'http://10.0.2.2:3000') -ConfigPath $fresh
    Assert-True ($created.ExitCode -eq 0) "Missing config was not created: $($created.Output)"
    Assert-True (Test-Path -LiteralPath $fresh) 'The first-run config file was not written.'
    $bytes = [IO.File]::ReadAllBytes($fresh)
    Assert-True ($bytes[0] -eq 0x7B) 'The generated config must not start with a UTF-8 BOM.'
    $written = Get-Content -LiteralPath $fresh -Raw | ConvertFrom-Json
    Assert-True ($written.API_BASE_URL -eq 'http://10.0.2.2:3000') 'The requested API origin was not written.'
    Assert-True ($written.WEB_BASE_URL -eq '') 'WEB_BASE_URL should default to an empty string.'
    $logText = Get-Content -LiteralPath $log -Raw
    Assert-True ($logText -match '--dart-define-from-file=' -and $logText -match [regex]::Escape('first run env.json')) 'The generated config was not passed to flutter run.'

    # Without an origin and without a console, the hint names both ways out.
    $missing = Join-Path $temp 'still missing.json'
    $hint = Run-Subject @() -ConfigPath $missing
    Assert-True ($hint.ExitCode -ne 0) 'A missing config without an origin should fail.'
    Assert-True ($hint.Output -match '-ApiBaseUrl' -and $hint.Output -match 'env\.example\.json') 'The hint did not explain how to create the config.'
    Assert-True (!(Test-Path -LiteralPath $missing)) 'The script wrote a config without an origin.'

    # A credential-bearing origin is rejected before anything reaches the disk.
    $secretPath = Join-Path $temp 'secret env.json'
    $secret = Run-Subject @('-ApiBaseUrl', 'https://user:badsecret@api.real-site.dev') -ConfigPath $secretPath
    Assert-True ($secret.ExitCode -ne 0) 'A credential-bearing origin was accepted for creation.'
    Assert-True (!$secret.Output.Contains('badsecret')) 'The bootstrap error echoed a credential.'
    Assert-True (!(Test-Path -LiteralPath $secretPath)) 'An invalid origin was written to disk.'

    # An existing config is never silently replaced by the flag.
    $existing = Join-Path $temp 'existing env.json'
    '{"API_BASE_URL":"https://api.real-site.dev","WEB_BASE_URL":""}' | Set-Content -LiteralPath $existing -Encoding Ascii
    $refused = Run-Subject @('-ApiBaseUrl', 'http://10.0.2.2:3000') -ConfigPath $existing
    Assert-True ($refused.ExitCode -ne 0 -and $refused.Output -match 'already exists') 'The flag overwrote or ignored an existing config.'
    Assert-True ((Get-Content -LiteralPath $existing -Raw) -match 'api\.real-site\.dev') 'The existing config was modified.'

    Write-Host 'Windows PowerShell mock scenarios passed (no Android SDK/device exercised).'
    # Negative test cases intentionally leave a child process exit code of 1.
    # Do not leak it into the caller/Actions shell after all assertions pass.
    $global:LASTEXITCODE = 0
} finally {
    $env:PATH = $oldPath
    if ($pubHostedUrlWasSet) {
        $env:PUB_HOSTED_URL = $oldPubHostedUrl
    } else {
        Remove-Item Env:PUB_HOSTED_URL -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $pidFile) {
        $id = [int](Get-Content -LiteralPath $pidFile -Raw)
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc -and $proc.Path -eq $emulator) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    }
    foreach ($name in @('BELOG_TEST_LOG', 'BELOG_TEST_STARTED', 'BELOG_TEST_PID', 'MOCK_NO_EMULATOR', 'MOCK_NEVER_BOOT', 'MOCK_FAIL_PUB', 'MOCK_HASH_MISMATCH_PUB', 'MOCK_FAIL_REVERSE', 'MOCK_NATIVE_STDERR', 'MOCK_FAIL_ADB', 'MOCK_FAIL_AVD_LIST', 'MOCK_FLUTTER_VERSION', 'MOCK_DART_VERSION', 'BELOG_STRICT_FLUTTER_VERSION', 'BELOG_NO_PROMPT')) {
        Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
