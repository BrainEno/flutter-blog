[CmdletBinding()]
param(
    [string]$Avd = '',
    [string]$Config = 'env.json',
    # Creates the config on first run instead of asking for it interactively.
    [string]$ApiBaseUrl = '',
    [string]$WebBaseUrl = '',
    [ValidateRange(1, 1800)][int]$BootTimeoutSeconds = 300,
    [switch]$StrictFlutterVersion
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

function Test-PubDevHostedUrl([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    $uri = $null
    if (![Uri]::TryCreate($Value.Trim(), [UriKind]::Absolute, [ref]$uri)) { return $false }
    return $uri.Scheme -ieq 'https' -and $uri.Host -ieq 'pub.dev' -and $uri.AbsolutePath -eq '/'
}

function Invoke-PubGet([string]$Flutter) {
    # Preserve the configured mirror unless it returns bytes that disagree with
    # pubspec.lock. In that case retry once against canonical pub.dev; never
    # weaken or rewrite the lockfile checksum to accommodate a mirror.
    $pubOutput = @()
    $preference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Flutter pub get 2>&1 | Tee-Object -Variable pubOutput | Out-Host
        $pubExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $preference
    }
    if ($pubExitCode -eq 0) { return }

    $outputText = $pubOutput -join [Environment]::NewLine
    $hashMismatch = $outputText -match '(?is)(wrong|mismatch|does not match|failed).{0,100}content[- ]hash|content[- ]hash.{0,100}(wrong|mismatch|does not match|failed)'
    if (!$hashMismatch) {
        throw "A required command failed ($pubExitCode): flutter pub get."
    }

    $configuredHostedUrl = $env:PUB_HOSTED_URL
    if (Test-PubDevHostedUrl $configuredHostedUrl) {
        throw 'pub.dev reported a package content-hash mismatch. Do not edit pubspec.lock; verify the package cache/network and retry.'
    }

    Write-Host 'Warning: the configured Pub mirror returned an archive whose content hash does not match pubspec.lock.'
    Write-Host 'Retrying dependency resolution once against canonical https://pub.dev; lockfile integrity checks remain enabled.'
    $hostedUrlWasSet = Test-Path Env:PUB_HOSTED_URL
    try {
        $env:PUB_HOSTED_URL = 'https://pub.dev'
        Invoke-Checked $Flutter @('pub', 'get')
    } catch {
        throw 'The Pub mirror failed the lockfile content-hash check and the retry from pub.dev also failed. Ensure this machine can reach pub.dev or use a trusted mirror that serves the exact locked archive; the launcher does not rewrite lockfile hashes.'
    } finally {
        if ($hostedUrlWasSet) {
            $env:PUB_HOSTED_URL = $configuredHostedUrl
        } else {
            Remove-Item Env:PUB_HOSTED_URL -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-QuietNative([string]$Executable, [string[]]$ToolArguments) {
    # Windows PowerShell 5.1 can surface native stderr as a terminating error
    # under Stop even for successful commands (e.g. adb starting its daemon).
    # Suppress that stream locally, preserving the exit status for the caller.
    $ErrorActionPreference = 'Continue'
    & $Executable @ToolArguments 2>$null
    $script:LastNativeExit = $LASTEXITCODE
}

function Get-VersionParts([string]$Value) {
    $match = [regex]::Match([string]$Value, '^\s*(\d+(?:\.\d+)*)')
    if (!$match.Success) { return }
    $match.Groups[1].Value.Split('.') | ForEach-Object { [int]$_ }
}

# $null means "cannot tell" so the caller can warn instead of refusing to start.
function Test-VersionAtLeast([string]$Value, [string]$Minimum) {
    $actual = @(Get-VersionParts $Value)
    $floor = @(Get-VersionParts $Minimum)
    if ($actual.Count -eq 0 -or $floor.Count -eq 0) { return $null }
    $width = [Math]::Max($actual.Count, $floor.Count)
    for ($index = 0; $index -lt $width; $index++) {
        $have = if ($index -lt $actual.Count) { $actual[$index] } else { 0 }
        $want = if ($index -lt $floor.Count) { $floor[$index] } else { 0 }
        if ($have -gt $want) { return $true }
        if ($have -lt $want) { return $false }
    }
    return $true
}

function Get-PinnedDartFloor {
    $pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
    if (!(Test-Path -LiteralPath $pubspec -PathType Leaf)) { return '' }
    $match = [regex]::Match((Get-Content -LiteralPath $pubspec -Raw), 'sdk:\s*"[^"]*>=\s*([0-9][0-9.]*)')
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}

function Format-FlutterUpgradeHelp([string]$Pinned) {
    return @(
        'Upgrade the SDK: flutter upgrade'
        "If that reports `"upstream branch 'refs/heads/stable' not stored as a remote-tracking branch`","
        "repair the SDK's own Git clone first, then upgrade:"
        '  git -C "<path-to-flutter-sdk>" fetch origin stable'
        '  git -C "<path-to-flutter-sdk>" branch --set-upstream-to=origin/stable stable'
        '  flutter upgrade'
        "Or install Flutter $Pinned and put it first on PATH."
    ) -join [Environment]::NewLine
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

# Writes the public, Git-ignored dart-define file. `-Encoding UTF8` would add a
# BOM under Windows PowerShell 5.1, which Flutter's JSON parser rejects.
function Write-ConfigFile([string]$Path, [string]$ApiUrl, [string]$WebUrl) {
    $directory = [IO.Path]::GetDirectoryName($Path)
    if ($directory -and !(Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Cannot create $([IO.Path]::GetFileName($Path)): its directory does not exist."
    }
    $payload = [ordered]@{ API_BASE_URL = $ApiUrl; WEB_BASE_URL = $WebUrl }
    $json = ($payload | ConvertTo-Json) + [Environment]::NewLine
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [IO.File]::WriteAllText($Path, $json, $encoding)
}

function Get-ConfigBootstrapHint([string]$Path) {
    $name = [IO.Path]::GetFileName($Path)
    $launcher = [IO.Path]::GetFileName($PSCommandPath)
    return @(
        "Config not found: $name"
        "Create it in one step (the value must be the API origin this emulator can reach):"
        "  .\scripts\$launcher -ApiBaseUrl http://10.0.2.2:PORT"
        "Or copy env.example.json to $name and set API_BASE_URL yourself (use http://10.0.2.2:PORT for a host-local API)."
    ) -join [Environment]::NewLine
}

function Get-Emulators {
    $lines = Invoke-QuietNative $script:Adb @('devices')
    if ($script:LastNativeExit -ne 0) { throw 'adb devices failed. Check the Android SDK installation.' }
    foreach ($line in $lines) {
        if ($line -match '^(emulator-\d+)\s+(device|offline)\s*$') {
            [PSCustomObject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
}

function Get-EmulatorAvd([string]$Serial) {
    try {
        $lines = Invoke-QuietNative $script:Adb @('-s', $Serial, 'emu', 'avd', 'name')
        if ($script:LastNativeExit -ne 0) { return '' }
        foreach ($line in $lines) {
            $name = $line.Trim()
            if ($name -and $name -ne 'OK') { return $name }
        }
    } catch { return '' }
    return ''
}

try {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (!$flutterCommand) { throw 'Flutter is not on PATH. Install the pinned Flutter SDK (tool/flutter_version.txt) first.' }
    $flutter = $flutterCommand.Source
    $versionText = (& $flutter --version --machine | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Could not query the Flutter SDK. Run `flutter --version` and `flutter doctor` to see the SDK error.' }
    $pinFile = Join-Path $ProjectRoot 'tool\flutter_version.txt'
    if (!(Test-Path -LiteralPath $pinFile -PathType Leaf)) {
        throw 'Missing tool/flutter_version.txt, which records the pinned Flutter SDK.'
    }
    $pinned = (Get-Content -LiteralPath $pinFile -Raw).Trim()
    try { $machine = $versionText | ConvertFrom-Json }
    catch { throw 'Could not parse flutter --version --machine.' }
    $flutterVersion = [string]$machine.frameworkVersion
    $dartVersion = [string]$machine.dartSdkVersion
    $strict = $StrictFlutterVersion -or ($env:BELOG_STRICT_FLUTTER_VERSION -eq '1')
    if ($flutterVersion -cne $pinned) {
        $compatible = Test-VersionAtLeast $dartVersion (Get-PinnedDartFloor)
        $found = if ($dartVersion) { "$flutterVersion (Dart $dartVersion)" } else { $flutterVersion }
        if ($strict -or $compatible -eq $false) {
            $reason = if ($compatible -eq $false) {
                "pubspec.yaml requires Dart $(Get-PinnedDartFloor) or newer; this SDK does not satisfy it."
            } else { '' }
            $message = @(
                "Flutter $pinned is required; found $found."
                $reason
                (Format-FlutterUpgradeHelp $pinned)
            ) | Where-Object { $_ }
            throw (($message | Out-String).Trim())
        }
        # stderr, like the failure path: the launcher wrapper shows both, and
        # the script's mock tests can assert on a warning they can capture.
        [Console]::Error.WriteLine("Warning: Flutter $flutterVersion is installed; CI and release builds use $pinned.")
        if ($null -eq $compatible) {
            [Console]::Error.WriteLine("Warning: could not compare this SDK with pubspec.yaml's Dart constraint.")
        }
        [Console]::Error.WriteLine('Local debug continues; it only needs a compatible Dart SDK.')
        [Console]::Error.WriteLine('Pass -StrictFlutterVersion (or set BELOG_STRICT_FLUTTER_VERSION=1) to require the pinned SDK.')
    }

    if (![IO.Path]::IsPathRooted($Config)) { $Config = Join-Path $ProjectRoot $Config }
    if ($ApiBaseUrl) { $ApiBaseUrl = $ApiBaseUrl.Trim() }
    if ($WebBaseUrl) { $WebBaseUrl = $WebBaseUrl.Trim() }
    $configExists = Test-Path -LiteralPath $Config -PathType Leaf
    if ($configExists -and ($ApiBaseUrl -or $WebBaseUrl)) {
        throw "-ApiBaseUrl/-WebBaseUrl only create a missing config; $([IO.Path]::GetFileName($Config)) already exists. Edit it, or pass -Config to use another file."
    }
    if (!$configExists) {
        # First run: ask once instead of sending the user to copy a file by hand.
        $origin = $ApiBaseUrl
        # Ask only in an attended console: CI, piped input and
        # BELOG_NO_PROMPT=1 get the copy-paste hint instead of a hanging prompt.
        $inputRedirected = $true
        try { $inputRedirected = [Console]::IsInputRedirected } catch { }
        $interactive = !$env:CI -and !$env:BELOG_NO_PROMPT -and !$inputRedirected
        if (!$origin -and $interactive) {
            Write-Host "No $([IO.Path]::GetFileName($Config)) yet: the app needs the API origin the emulator can reach."
            Write-Host 'Example: http://10.0.2.2:3000 for an API running on this machine.'
            # Three tries, so a typo does not force a restart of the script.
            for ($attempt = 1; $attempt -le 3 -and !$origin; $attempt++) {
                $answer = Read-Host 'API_BASE_URL (empty cancels)'
                if (!$answer) { break }
                $answer = $answer.Trim()
                try { $null = Validate-Origin $answer 'API_BASE_URL'; $origin = $answer }
                catch { Write-Host 'Not a plain HTTP(S) origin (no credentials, path, query or fragment). Example: http://10.0.2.2:3000' }
            }
        }
        if (!$origin) { throw (Get-ConfigBootstrapHint $Config) }
        try { $null = Validate-Origin $origin 'API_BASE_URL' }
        catch { throw 'API_BASE_URL must be a plain HTTP(S) origin: no credentials, path, query or fragment.' }
        if ($WebBaseUrl) {
            try { $null = Validate-Origin $WebBaseUrl 'WEB_BASE_URL' }
            catch { throw 'WEB_BASE_URL must be a plain HTTP(S) origin: no credentials, path, query or fragment.' }
        }
        Write-ConfigFile $Config $origin $WebBaseUrl
        # The file is Git-ignored and holds only these public origins.
        Write-Host "Wrote $([IO.Path]::GetFileName($Config)) with API_BASE_URL $origin (public config only, Git-ignored). Edit it to point at another backend."
    }
    $Config = (Resolve-Path -LiteralPath $Config).Path
    try { $data = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'Cannot read config JSON. Run `copy env.example.json env.json`, then set API_BASE_URL (and optionally WEB_BASE_URL) to real HTTP(S) origins.' }
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
    if ($api.IsLoopback) {
        Write-Host "Detected a loopback API origin; after boot the script will set up adb reverse for port $($api.Port)."
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
        $avds = @(Invoke-QuietNative $emulator @('-list-avds') | Where-Object { $_.Trim() } | Sort-Object)
        if ($script:LastNativeExit -ne 0) { throw 'Could not list Android AVDs.' }
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
            $boot = Invoke-QuietNative $script:Adb @('-s', $serial, 'shell', 'getprop', 'sys.boot_completed')
            if ($script:LastNativeExit -eq 0 -and (($boot -join '').Trim() -eq '1')) { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'Android emulator boot timed out. Open Android Studio Device Manager and retry.' }

    if ($api.IsLoopback) {
        $port = $api.Port
        if ($port -lt 1 -or $port -gt 65535) { throw 'The loopback API origin has an invalid TCP port for adb reverse.' }
        $mapping = "tcp:$port"
        try {
            $null = Invoke-QuietNative $script:Adb @('-s', $serial, 'reverse', $mapping, $mapping)
            if ($script:LastNativeExit -ne 0) { throw 'adb reverse returned a non-zero exit code.' }
        } catch {
            throw "Could not forward emulator localhost:$port to the host. Check adb reverse support or use http://10.0.2.2:$port in env.json."
        }
        Write-Host "ADB reverse is active: emulator localhost:$port forwards to the host's localhost:$port."
    }

    Push-Location $ProjectRoot
    try {
        Invoke-PubGet $flutter
        Invoke-Checked $flutter @('run', '--debug', '--no-pub', '-d', $serial, "--dart-define-from-file=$Config", '--dart-define=BELOG_DEV_BACKEND_CHECK=true')
    } finally { Pop-Location }
} catch {
    [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
    exit 1
}
