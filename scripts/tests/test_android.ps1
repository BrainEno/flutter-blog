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
$engine = (Get-Command powershell.exe).Source

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Run-Subject([string[]]$ExtraArguments) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& $engine -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/run_android.ps1') -Config $config -BootTimeoutSeconds 4 @ExtraArguments 2>&1 | Out-String)
        return @{ ExitCode = $LASTEXITCODE; Output = $output }
    } finally { $ErrorActionPreference = $oldPreference }
}

try {
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    @'
@echo off
if "%~1"=="--version" (
  echo {"frameworkVersion":"3.47.8"}
  exit /b 0
)
echo flutter %*>>"%BELOG_TEST_LOG%"
if "%~1"=="pub" if "%MOCK_FAIL_PUB%"=="1" exit /b 2
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $bin 'flutter.cmd') -Encoding Ascii
    @'
@echo off
echo adb %*>>"%BELOG_TEST_LOG%"
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
    '{"API_BASE_URL":"http://10.0.2.2:8787","WEB_BASE_URL":""}' | Set-Content -LiteralPath $config -Encoding Ascii

    $reuse = Run-Subject @('-Avd', 'Demo')
    Assert-True ($reuse.ExitCode -eq 0) "Existing emulator scenario failed: $($reuse.Output)"
    $calls = Get-Content -LiteralPath $log -Raw
    Assert-True ($calls -match 'flutter run --debug -d emulator-5554') 'Did not target the existing emulator.'
    Assert-True ($calls -match 'BELOG_DEV_BACKEND_CHECK=true') 'Missing local API probe define.'
    Assert-True ($calls.Contains($config)) 'Config path with spaces was not passed intact.'
    Assert-True (!(Test-Path $marker)) 'An existing AVD should not be started again.'

    Remove-Item -LiteralPath $log -Force
    $env:MOCK_NO_EMULATOR = '1'
    # Successful adb/emulator commands may write startup notices to stderr.
    $env:MOCK_NATIVE_STDERR = '1'
    $new = Run-Subject @()
    Assert-True ($new.ExitCode -eq 0) "Fresh AVD scenario (with native stderr) failed: $($new.Output)"
    Assert-True (Test-Path $marker) 'The selected AVD was not launched.'
    Assert-True ((Get-Content $marker -Raw).Trim() -eq 'Demo') 'Started the wrong AVD.'
    Assert-True ((Get-Content $log -Raw) -match 'flutter run --debug -d emulator-5554') 'Fresh AVD was not used.'
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

    Write-Host 'Windows PowerShell mock scenarios passed (no Android SDK/device exercised).'
    # Negative test cases intentionally leave a child process exit code of 1.
    # Do not leak it into the caller/Actions shell after all assertions pass.
    $global:LASTEXITCODE = 0
} finally {
    $env:PATH = $oldPath
    if (Test-Path -LiteralPath $pidFile) {
        $id = [int](Get-Content -LiteralPath $pidFile -Raw)
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc -and $proc.Path -eq $emulator) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    }
    foreach ($name in @('BELOG_TEST_LOG', 'BELOG_TEST_STARTED', 'BELOG_TEST_PID', 'MOCK_NO_EMULATOR', 'MOCK_NEVER_BOOT', 'MOCK_FAIL_PUB', 'MOCK_NATIVE_STDERR', 'MOCK_FAIL_ADB', 'MOCK_FAIL_AVD_LIST')) {
        Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
