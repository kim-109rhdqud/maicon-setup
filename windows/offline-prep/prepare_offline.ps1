# 오프라인 설치용 파일을 미리 받아 둔다 (인터넷 되는 Windows PC 에서 실행, 대회 전에 1번)
#
#   powershell -ExecutionPolicy Bypass -File offline-prep\prepare_offline.ps1 -Out E:\maicon-offline
#
# 만들어지는 폴더 (외장 드라이브에 통째로 복사해서 setup.ps1 -Offline <폴더> 로 씀)
#   offline\winget\        winget 자체 설치 파일 (App Installer msixbundle + 의존 appx)
#   offline\installers\<Id>\   packages.csv 의 각 프로그램 설치 파일 (winget download)
#   offline\vsix\          VS Code 확장
#   offline\wheels\        Python 패키지 (Windows x64, Python 3.10 용)  ← PyTorch 포함 약 3GB
#   offline\wsl\           ROS2 포함 Ubuntu rootfs tar (있으면)
#   offline\nvidia\        (수동) RTX 5070 드라이버 exe
#   offline\REPORT.txt     받지 못한 것 목록
#
# 필요: winget 1.6 이상, Python 3.10 (py -3.10). Python 3.10 이 없으면 아무 Python 으로도 받을 수 있게 옵션을 줌.

param(
    [string]$Out = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "offline"),
    [switch]$SkipWheels,
    [switch]$SkipInstallers
)
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Missing = @()
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Miss($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow; $script:Missing += $m }

foreach ($d in "winget", "installers", "vsix", "wheels", "wsl", "nvidia") { New-Item -ItemType Directory -Force -Path (Join-Path $Out $d) | Out-Null }

# ---------------------------------------------------------------- 1. winget 자체
Step "1. winget 설치 파일 (새 Windows 에 winget 이 없거나 오래됐을 때용)"
$wg = Join-Path $Out "winget"
$urls = @{
    "Microsoft.DesktopAppInstaller.msixbundle" = "https://aka.ms/getwinget"
    "Microsoft.VCLibs.x64.14.00.Desktop.appx"  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
}
foreach ($k in $urls.Keys) {
    $f = Join-Path $wg $k
    if (Test-Path $f) { Ok "$k 있음"; continue }
    try { Invoke-WebRequest -Uri $urls[$k] -OutFile $f -UseBasicParsing; Ok $k } catch { Miss "winget: $k 받기 실패 ($($urls[$k]))" }
}
# Microsoft.UI.Xaml 은 nuget 패키지 안에 appx 가 들어 있음
$xaml = Join-Path $wg "Microsoft.UI.Xaml.2.8.x64.appx"
if (-not (Test-Path $xaml)) {
    try {
        $nupkg = Join-Path $env:TEMP "xaml.zip"
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6" -OutFile $nupkg -UseBasicParsing
        Expand-Archive $nupkg (Join-Path $env:TEMP "xaml") -Force
        Copy-Item (Join-Path $env:TEMP "xaml\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx") $xaml
        Ok "Microsoft.UI.Xaml.2.8.x64.appx"
    } catch { Miss "winget: Microsoft.UI.Xaml appx 받기 실패" }
} else { Ok "Microsoft.UI.Xaml 있음" }

# ---------------------------------------------------------------- 2. 프로그램 설치 파일
if (-not $SkipInstallers) {
    Step "2. 프로그램 설치 파일 (winget download)"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Miss "이 PC 에 winget 이 없어 설치 파일을 못 받음" }
    else {
        $pkgs = Import-Csv (Join-Path $Here "packages.csv")
        foreach ($p in $pkgs) {
            $dir = Join-Path $Out "installers\$($p.Id)"
            if ((Test-Path $dir) -and (Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "exe|msi|msix|appx" })) { Ok "$($p.Name) 있음"; continue }
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Write-Host "  받는 중: $($p.Name) ($($p.Id))"
            winget download --id $p.Id -e --source winget -d $dir --architecture x64 --accept-package-agreements --accept-source-agreements --skip-license 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                winget download --id $p.Id -e --source winget -d $dir --accept-package-agreements --accept-source-agreements --skip-license 2>&1 | Out-Null
            }
            if (Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "exe|msi|msix|appx" }) { Ok $p.Name }
            else { Miss "$($p.Name) ($($p.Id)): winget download 실패 → 직접 받아서 $dir 에 넣기. $($p.Note)" }
        }
    }
}

# ---------------------------------------------------------------- 3. VS Code 확장 (vsix)
Step "3. VS Code 확장"
$exts = @("ms-python.python", "ms-vscode-remote.remote-ssh")   # 팀 공통만. 개인 확장은 각자 동기화
foreach ($e in $exts) {
    $f = Join-Path $Out "vsix\$e.vsix"
    if (Test-Path $f) { Ok "$e 있음"; continue }
    $pub, $name = $e.Split(".", 2)
    $u = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$pub/vsextensions/$name/latest/vspackage"
    try { Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing -Headers @{ "Accept-Encoding" = "gzip" }
          # 마켓은 gzip 으로 줄 때가 있음 → 풀어 줌
          $bytes = [IO.File]::ReadAllBytes($f)
          if ($bytes[0] -eq 0x1f -and $bytes[1] -eq 0x8b) {
              $in = New-Object IO.MemoryStream(,$bytes); $gz = New-Object IO.Compression.GzipStream($in, [IO.Compression.CompressionMode]::Decompress)
              $outS = [IO.File]::Create($f); $gz.CopyTo($outS); $outS.Close(); $gz.Close()
          }
          Ok $e
    } catch { Miss "VS Code 확장 $e 받기 실패 (VS Code 에서 확장 페이지 → Download Extension 으로 수동)" }
}

# ---------------------------------------------------------------- 4. Python 휠 (Windows x64 / Python 3.10)
if (-not $SkipWheels) {
    Step "4. Python 패키지 휠"
    $wh = Join-Path $Out "wheels"
    $pyCmd = $null
    try { if ((py -3.10 --version 2>&1) -match "3\.10") { $pyCmd = "py -3.10" } } catch {}
    if (-not $pyCmd) { try { if ((python --version 2>&1) -match "Python 3") { $pyCmd = "python" } } catch {} }
    if (-not $pyCmd) { Miss "Python 이 없어 휠을 못 받음 (Python 3.10 설치 후 다시 실행)" }
    else {
        $plat = "--platform win_amd64 --python-version 3.10 --only-binary=:all: --implementation cp"
        Invoke-Expression "$pyCmd -m pip download pip setuptools wheel -d `"$wh`" $plat"
        Invoke-Expression "$pyCmd -m pip download -r `"$Here\requirements-common.txt`" -d `"$wh`" $plat"
        Write-Host "  PyTorch cu128 (약 3GB)"
        Invoke-Expression "$pyCmd -m pip download torch torchvision -d `"$wh`" $plat --index-url https://download.pytorch.org/whl/cu128"
        # ultralytics 등은 torch 의존성을 PyPI(CPU 버전)에서 끌어오지 않게 --no-deps 로 받고, 나머지 의존성은 따로
        Invoke-Expression "$pyCmd -m pip download -r `"$Here\requirements-train.txt`" -d `"$wh`" $plat --extra-index-url https://download.pytorch.org/whl/cu128"
        $n = (Get-ChildItem $wh -Filter *.whl).Count
        if ($n -gt 10) { Ok "휠 $n 개" } else { Miss "휠이 $n 개뿐 — pip download 출력 확인" }
    }
}

# ---------------------------------------------------------------- 5. WSL rootfs
Step "5. ROS2 포함 Ubuntu (wsl --export)"
$tar = Join-Path $Out "wsl\ros2-humble-22.04.tar"
if (Test-Path $tar) { Ok "ros2-humble-22.04.tar 있음" }
elseif ((wsl -l -q 2>$null | Out-String) -match "maicon-ros2") {
    Write-Host "  이 PC 의 maicon-ros2 배포판을 내보냄 (몇 GB, 몇 분)"
    wsl --export maicon-ros2 $tar
    if ($LASTEXITCODE -eq 0) { Ok "ros2-humble-22.04.tar" } else { Miss "wsl --export 실패" }
} else { Miss "ROS2 rootfs tar 없음 → 리눅스에서 offline-prep\build_rootfs.sh 로 만들거나, 이 PC 에 maicon-ros2 를 먼저 만든 뒤 다시 실행. 없으면 현장에서 인터넷으로 설치" }

# ---------------------------------------------------------------- 6. 수동 항목
Step "6. 수동으로 넣을 것"
if (-not (Get-ChildItem (Join-Path $Out "nvidia") -Filter *.exe -ErrorAction SilentlyContinue)) { Miss "NVIDIA RTX 5070 드라이버 exe → offline\nvidia\ (https://www.nvidia.com/drivers)" }

# ---------------------------------------------------------------- 보고
$report = Join-Path $Out "REPORT.txt"
$size = [math]::Round((Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum / 1GB, 2)
@("만든 날짜: $(Get-Date)", "전체 크기: ${size} GB", "", "못 받은 것 ($($Missing.Count)):") + ($Missing | ForEach-Object { " - $_" }) | Out-File -Encoding utf8 $report
Write-Host "`n전체 ${size} GB. 못 받은 것 $($Missing.Count)건 → $report" -ForegroundColor Cyan
$Missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
