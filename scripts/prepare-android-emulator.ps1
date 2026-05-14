param(
    [string]$AvdName = "FYP_Pixel_9",
    [switch]$SkipEmulator,
    [switch]$SkipBackend
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "rakanstudent_mobile"
$backendDir = Join-Path $repoRoot "student-task-orchestrator\\backend"
$flutterBin = "C:\Users\USER\Downloads\flutter_windows_3.29.1-stable\flutter\bin"
$flutter = Join-Path $flutterBin "flutter.bat"
$androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$emulator = Join-Path $androidSdk "emulator\emulator.exe"
$adb = Join-Path $androidSdk "platform-tools\adb.exe"

if (-not (Test-Path $flutter)) {
    throw "Flutter not found at $flutter"
}

$env:Path = "$flutterBin;$($env:Path)"
$env:ANDROID_SDK_ROOT = $androidSdk

Write-Host "[1/5] Flutter SDK" -ForegroundColor Cyan
& $flutter --version

Write-Host "[2/5] Mobile env keys" -ForegroundColor Cyan
$envFile = Join-Path $mobileDir ".env"
if (-not (Test-Path $envFile)) {
    throw "Missing $envFile. Copy .env.example and fill values."
}

$envKeys = Get-Content $envFile |
    Where-Object { $_ -and -not $_.Trim().StartsWith('#') } |
    ForEach-Object { ($_ -split '=', 2)[0].Trim() }
$requiredSets = @(
    @{ Name = "API"; Keys = @("MOBILE_API_BASE_URL", "API_URL", "API_BASE_URL") },
    @{ Name = "Supabase URL"; Keys = @("MOBILE_SUPABASE_URL", "SUPABASE_URL") },
    @{ Name = "Supabase anon key"; Keys = @("MOBILE_SUPABASE_ANON_KEY", "SUPABASE_ANON_KEY") }
)
foreach ($required in $requiredSets) {
    if (-not ($required.Keys | Where-Object { $envKeys -contains $_ })) {
        throw "Missing env for $($required.Name). Expected one of: $($required.Keys -join ', ')"
    }
}

Write-Host "[3/5] Flutter deps + analyze" -ForegroundColor Cyan
Push-Location $mobileDir
try {
    & $flutter pub get
    & $flutter analyze
} finally {
    Pop-Location
}

if (-not $SkipBackend) {
    Write-Host "[4/5] Backend container" -ForegroundColor Cyan
    Push-Location $repoRoot
    try {
        docker compose up -d backend
    } finally {
        Pop-Location
    }
}

if (-not $SkipEmulator) {
    Write-Host "[5/5] Android emulator" -ForegroundColor Cyan
    if (-not (Test-Path $emulator)) {
        throw "Android emulator not found at $emulator"
    }

    $booted = & $adb devices | Select-String "emulator-" -Quiet
    if (-not $booted) {
        Start-Process -FilePath $emulator -ArgumentList @("-avd", $AvdName)
        Write-Host "Booting $AvdName ..."
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 5
            $bootStatus = & $adb shell getprop sys.boot_completed 2>$null
        } until ($bootStatus -match "1" -or (Get-Date) -gt $deadline)

        if ($bootStatus -notmatch "1") {
            throw "Emulator failed to boot within timeout."
        }
    } else {
        Write-Host "Emulator already running."
    }
}

Write-Host ""
Write-Host "Ready. Run mobile app with:" -ForegroundColor Green
Write-Host "cd `"$mobileDir`""
Write-Host "& `"$flutter`" run -d emulator-5554"
