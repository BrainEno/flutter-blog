[CmdletBinding()]
param(
    [string]$Avd = '',
    [string]$Config = 'env.json',
    [ValidateRange(1, 1800)][int]$BootTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Find-Tool([string]$Name, [string]$SdkRelative) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $roots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    foreach ($root in $roots) {
        if ($root) {
            $candidate = Join-Path $root $SdkRelative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw "Cannot find $Name. Install Android SDK platform-tools and emulator, or set ANDROID_SDK_ROOT."
}

function Invoke-Checked([string]$Executable, [string[]]$ToolArguments) {
    & $Executable @ToolArguments
    if ($LASTEXITCODE -ne 0) { throw "A required command failed ($LASTEXITCODE): $([IO.Path]::GetFileName($Executable))." }
}

function Validate-Origin($Value, [string]$Name) {
    if ($Value -isnot [string] -or !$Value -or $Value -match '\s') {
        throw "$Name must be a non-empty HTTP(S) origin."
    }
    $uri = $null
    $ok = [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)
    if (!$ok -or $uri.Scheme -notin @('http', 'https') -or !$uri.Host -or
        $uri.UserInfo -or $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or
        $uri.Host -match '(^|\.)(example\.(com|org|net)|example|invalid|test)$') {
        throw "$Name must be a real HTTP(S) origin, with no credentials, path, query or fragment."
    }
    return $uri
}

function Get-Emulators {
    $lines = & $script:Adb devices
    if ($LASTEXITCODE -ne 0) { throw 'adb devices failed. Check the Android SDK installation.' }
    foreach ($line in $lines) {
        if ($line -match '^(emulator-\d+)\s+(device|offline)\s*$') {
            [PSCustomObject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
}

function Get-EmulatorAvd([string]$Serial) {
    try {
        $lines = & $script:Adb -s $Serial emu avd name 2>$null
        if ($LASTEXITCODE -ne 0) { return '' }
        foreach ($line in $lines) {
            $name = $line.Trim()
            if ($name -and $name -ne 'OK') { return $name }
        }
    } catch { return '' }
    return ''
}

try {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (!$flutterCommand) { throw 'Flutter is not on PATH. Install Flutter 3.47.8 first.' }
    $flutter = $flutterCommand.Source
    $versionText = (& $flutter --version --machine | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Could not query the Flutter SDK.' }
    try { $flutterVersion = ($versionText | ConvertFrom-Json).frameworkVersion }
    catch { throw 'Could not parse flutter --version --machine.' }
    if ($flutterVersion -ne '3.47.8') { throw "Flutter 3.47.8 is required; found $flutterVersion." }

    if (![IO.Path]::IsPathRooted($Config)) { $Config = Join-Path $ProjectRoot $Config }
    if (!(Test-Path -LiteralPath $Config -PathType Leaf)) {
        throw 'Config not found. Copy env.example.json to env.json and edit the public API origin.'
    }
    $Config = (Resolve-Path -LiteralPath $Config).Path
    try { $data = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'Cannot read config JSON. Copy env.example.json to env.json and edit the public origins.' }
    if (!$data -or $data -is [array] -or $data -isnot [PSCustomObject]) { throw 'Config must be a JSON object.' }
    foreach ($property in $data.PSObject.Properties) {
        if (-not (@('API_BASE_URL', 'WEB_BASE_URL') -ccontains $property.Name)) {
            throw 'Config may contain only API_BASE_URL and WEB_BASE_URL; never embed secrets in a client build.'
        }
    }
    $apiProperty = $data.PSObject.Properties['API_BASE_URL']
    if (!$apiProperty) { throw 'API_BASE_URL is required.' }
    $api = Validate-Origin $apiProperty.Value 'API_BASE_URL'
    $webProperty = $data.PSObject.Properties['WEB_BASE_URL']
    if ($webProperty -and $webProperty.Value -cne '') { $null = Validate-Origin $webProperty.Value 'WEB_BASE_URL' }
    if ($api.Host -in @('localhost', '127.0.0.1', '::1')) {
        Write-Host 'Warning: localhost inside the Android emulator is not the host. Use 10.0.2.2 for a host-local API.'
    }
    if ($api.Scheme -eq 'http') {
        Write-Host 'Warning: HTTP is allowed only by the debug app and sends credentials unencrypted. Use a trusted local backend.'
    }
    Write-Host 'Public client configuration OK.'

    $script:Adb = Find-Tool 'adb' 'platform-tools\adb.exe'
    $emulator = Find-Tool 'emulator' 'emulator\emulator.exe'
    $deadline = [DateTime]::UtcNow.AddSeconds($BootTimeoutSeconds)
    $running = @(Get-Emulators | Sort-Object Serial)
    $serial = ''
    if ($Avd) {
        foreach ($device in $running) {
            if ($device.State -eq 'device') {
                $name = Get-EmulatorAvd $device.Serial
                if (!$name) { throw "Cannot identify $($device.Serial). Wait for it to boot, then retry." }
                if ($name -ceq $Avd) { $serial = $device.Serial; break }
            }
        }
        if (!$serial -and @($running | Where-Object { $_.State -eq 'offline' }).Count -gt 0) {
            throw 'An emulator is still offline/booting. Wait for it before selecting an AVD to avoid starting a duplicate.'
        }
    } elseif ($running.Count -gt 0) {
        $serial = $running[0].Serial
    }

    $process = $null
    if (!$serial) {
        $avds = @(& $emulator -list-avds | Where-Object { $_.Trim() } | Sort-Object)
        if ($LASTEXITCODE -ne 0) { throw 'Could not list Android AVDs.' }
        if ($avds.Count -eq 0) { throw 'No AVD found. Create an Android Virtual Device in Android Studio first.' }
        if (!$Avd) {
            $Avd = $avds[0].Trim()
            if ($avds.Count -gt 1) { Write-Host "Using the first available AVD. Pass -Avd to select another." }
        }
        if (@($avds | Where-Object { $_.Trim() -ceq $Avd }).Count -ne 1) { throw 'Selected AVD was not found. List available AVDs with emulator -list-avds.' }
        if ($Avd -match '["\r\n]') { throw 'AVD name contains an unsupported character.' }
        Write-Host "Starting Android AVD: $Avd"
        $process = Start-Process -FilePath $emulator -ArgumentList @('-avd', ('"' + $Avd + '"')) -PassThru
        while ([DateTime]::UtcNow -lt $deadline -and !$serial) {
            foreach ($device in @(Get-Emulators | Where-Object { $_.State -eq 'device' })) {
                if ((Get-EmulatorAvd $device.Serial) -ceq $Avd) { $serial = $device.Serial; break }
            }
            if (!$serial) {
                if ($process.HasExited) { throw 'The Android emulator exited before registering with adb.' }
                Start-Sleep -Seconds 2
            }
        }
        if (!$serial) { throw 'Timed out waiting for the AVD to register with adb.' }
    }

    Write-Host "Waiting for Android emulator $serial to finish booting..."
    $ready = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $boot = & $script:Adb -s $serial shell getprop sys.boot_completed 2>$null
            if ($LASTEXITCODE -eq 0 -and (($boot -join '').Trim() -eq '1')) { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'Android emulator boot timed out. Open Android Studio Device Manager and retry.' }

    Push-Location $ProjectRoot
    try {
        Invoke-Checked $flutter @('pub', 'get')
        Invoke-Checked $flutter @('run', '--debug', '-d', $serial, "--dart-define-from-file=$Config", '--dart-define=BELOG_DEV_BACKEND_CHECK=true')
    } finally { Pop-Location }
} catch {
    [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
    exit 1
}
