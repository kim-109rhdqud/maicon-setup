# MAICON 2026 현장 PC 개발환경 자동 설치 (Windows 11)
#
# 실행: setup.bat 더블클릭 (관리자 권한으로 자동 전환)
#   또는  powershell -ExecutionPolicy Bypass -File setup.ps1 -Role laptop
#
# 옵션
#   -Role desktop|laptop   desktop = RTX 5070 학습용 PC (PyTorch GPU + YOLO 추가) / laptop = 개발 노트북
#   -Offline <폴더>         인터넷 없이 설치. prepare_offline.ps1 로 만든 offline 폴더 (외장 드라이브)
#                          생략해도 이 스크립트 옆에 offline 폴더가 있고 인터넷이 안 되면 자동으로 씀
#   -NoWsl                 WSL2 + Ubuntu + ROS2 설치 건너뜀 (M1·M6 등 ROS 안 쓰는 사람)
#   -RepoUrl <주소>         팀 저장소 clone
#   -Resume                (내부용) 재부팅 뒤 이어서 실행
#
# 설치 목록은 packages.csv 에서 관리한다 (Roles=manual 은 직접 설치, 스크립트는 있는지만 확인).
# 다시 실행해도 안전하다(깔린 것은 건너뜀).
# 로그: setup_log.txt

param(
    [string]$Role = "",
    [string]$Offline = "",
    [switch]$NoWsl,
    [string]$RepoUrl = "",
    [string]$WorkDir = "$env:USERPROFILE\maicon2026",
    [switch]$Resume,
    [switch]$Elevated
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log = Join-Path $Here "setup_log.txt"

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow; $script:Warnings += $m }
function Fail($m) { Write-Host "  [X]  $m" -ForegroundColor Red; $script:Warnings += $m }
$script:Warnings = @()

# ---------------------------------------------------------------- 관리자 권한으로 다시 실행
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $psargs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$($MyInvocation.MyCommand.Path)`"")
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v) { $psargs += "-$k" } } else { $psargs += "-$k"; $psargs += "`"$v`"" }
    }
    $psargs += "-Elevated"   # 새 창은 끝나면 바로 닫히므로, 결과를 볼 수 있게 마지막에 멈추라는 표시
    Write-Host "관리자 권한 창에서 설치를 계속합니다. 새로 뜬 창을 보세요 (UAC '예')."
    Start-Process powershell -Verb RunAs -ArgumentList $psargs
    exit
}
Start-Transcript -Path $Log -Append | Out-Null

function Quit-Setup($code) {
    Stop-Transcript | Out-Null
    if ($Elevated) { Read-Host "Enter 를 누르면 이 창이 닫힙니다" | Out-Null }
    exit $code
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

# ---------------------------------------------------------------- 0. 역할 · 온/오프라인
if (-not $Role) {
    $hasNvidia = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
    $default = "laptop"; if ($hasNvidia) { $default = "desktop" }
    $ans = Read-Host "이 PC 는? [desktop = RTX 5070 학습용 / laptop = 개발 노트북] (Enter = $default)"
    if ($ans) { $Role = $ans.Trim().ToLower() } else { $Role = $default }
}
if ($Role -ne "desktop" -and $Role -ne "laptop") { Fail "Role 은 desktop 또는 laptop: $Role"; Quit-Setup 1 }

$online = $false
# msftconnecttest 는 HTTP 전용 (HTTPS 는 인증서 불일치로 항상 실패). 실제로 쓰는 곳(GitHub, PyPI)도 같이 확인
foreach ($u in "http://www.msftconnecttest.com/connecttest.txt", "https://github.com", "https://pypi.org/simple/pip/") {
    try { Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 8 -Method Head | Out-Null; $online = $true; break } catch {}
}
if (-not $Offline -and -not $online -and (Test-Path (Join-Path $Here "offline"))) { $Offline = Join-Path $Here "offline" }
if ($Offline -and -not (Test-Path $Offline)) { Fail "offline 폴더 없음: $Offline"; Quit-Setup 1 }
$mode = "온라인(winget)"; if ($Offline) { $mode = "오프라인($Offline)" } elseif (-not $online) { $mode = "인터넷 없음 + offline 폴더 없음 → 대부분 실패함" }
Step "역할: $Role / 설치 방식: $mode / 재개: $Resume"

# ---------------------------------------------------------------- 공용 함수
function Installed-Winget($id) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
    $out = winget list --id $id -e --source winget --accept-source-agreements 2>$null | Out-String
    return $out -match [regex]::Escape($id)
}

function Install-Offline($id, $name, $silent) {
    $dir = Join-Path $Offline "installers\$id"
    if (-not (Test-Path $dir)) { Warn "$name : 오프라인 설치 파일 없음 ($dir)"; return }
    $file = Get-ChildItem $dir -File | Where-Object { $_.Extension -match "^\.(exe|msi|msix|msixbundle|appx|appxbundle)$" } | Select-Object -First 1
    if (-not $file) { Warn "$name : 설치 파일을 못 찾음 ($dir)"; return }
    Write-Host "  설치 중(오프라인): $name  <- $($file.Name)"
    try {
        switch -Regex ($file.Extension) {
            "^\.msi$"        { Start-Process msiexec -ArgumentList "/i `"$($file.FullName)`" /qn /norestart $silent" -Wait }
            "^\.(msix|appx)" {
                $deps = Get-ChildItem (Join-Path $Offline "winget") -Filter *.appx -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
                if ($deps) { Add-AppxPackage -Path $file.FullName -DependencyPath $deps } else { Add-AppxPackage -Path $file.FullName }
            }
            default          { Start-Process $file.FullName -ArgumentList $silent -Wait }
        }
        Ok "$name 설치 완료"
    } catch { Fail "$name 오프라인 설치 실패: $($_.Exception.Message)" }
}

function Install-Package($id, $name, $silent) {
    if (Installed-Winget $id) { Ok "$name 이미 설치됨"; return }
    if ($Offline) { Install-Offline $id $name $silent; return }
    if (-not $online) { Warn "$name : 인터넷 없음, 건너뜀"; return }
    Write-Host "  설치 중: $name"
    $wo = winget install --id $id -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { Ok "$name 설치 완료" }   # -1978335189 = 이미 설치됨
    else {
        # 진행 표시(스피너·막대)를 뺀 마지막 몇 줄만 보여 줌
        $wo | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^[-\\|/]$' -and $_ -notmatch '[█▒]' } |
            Select-Object -Last 4 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
        Warn "$name 설치 실패 (winget 코드 $LASTEXITCODE)"
    }
}

# ---------------------------------------------------------------- 1. winget 준비
Step "1. winget"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    $bundle = $null
    if ($Offline) { $bundle = Get-ChildItem (Join-Path $Offline "winget") -Filter *.msixbundle -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($bundle) {
        $deps = Get-ChildItem (Join-Path $Offline "winget") -Filter *.appx | ForEach-Object { $_.FullName }
        try { Add-AppxPackage -Path $bundle.FullName -DependencyPath $deps; Refresh-Path; Ok "winget 설치(오프라인)" } catch { Fail "winget 오프라인 설치 실패: $($_.Exception.Message)" }
    } else {
        Warn "winget 없음. Microsoft Store 에서 '앱 설치 관리자' 업데이트 후 다시 실행 (오프라인이면 offline\winget 폴더 필요)"
    }
} else { Ok "winget $(winget --version)" }

# ---------------------------------------------------------------- 2. 프로그램 설치
if (-not $Resume) {
    Step "2. 프로그램 (packages.csv)"
    $pkgs = Import-Csv (Join-Path $Here "packages.csv")
    foreach ($p in $pkgs) {
        $roles = $p.Roles.Split(";")
        if ($roles -contains "wsl") { continue }                        # WSL 은 7단계에서
        if ($roles -contains "manual") {                                # 직접 설치하는 것: 깔렸는지만 확인
            if (Installed-Winget $p.Id) { Ok "$($p.Name) 있음 (직접 설치)" }
            else { Warn "$($p.Name) : 직접 설치 필요 → $($p.Note)" }
            continue
        }
        if (-not ($roles -contains "all" -or $roles -contains $Role)) { continue }
        Install-Package $p.Id $p.Name $p.Silent
    }
    Refresh-Path

    # OpenSSH 클라이언트 (Windows 기본 기능)
    if (Get-Command ssh -ErrorAction SilentlyContinue) { Ok "ssh 있음" }
    else {
        try { Add-WindowsCapability -Online -Name "OpenSSH.Client~~~~0.0.1.0" | Out-Null; Ok "OpenSSH 클라이언트 추가" }
        catch { Warn "OpenSSH 클라이언트 추가 실패 (설정 > 선택적 기능에서 수동)" }
    }
}

# ---------------------------------------------------------------- 3. Python · Git 확인
Step "3. Python · Git"
Refresh-Path
$py = $null
foreach ($c in @("py -3.10", "python")) {
    try { $v = Invoke-Expression "$c --version 2>&1"; if ("$v" -match "3\.10") { $py = $c; break } } catch {}
}
if (-not $py) { Fail "Python 3.10 을 못 찾음. 설치 실패했거나 창을 다시 열어야 함"; }
else { Ok "Python: $py" }

if (Get-Command git -ErrorAction SilentlyContinue) {
    if (-not (git config --global user.name)) {
        $n = Read-Host "  Git 이름 (GitHub 아이디, Enter = 건너뜀)"
        $e = Read-Host "  Git 이메일 (Enter = 건너뜀)"
        if ($n) { git config --global user.name $n }
        if ($e) { git config --global user.email $e }
    }
    git config --global core.autocrlf input      # 로봇(Linux)과 줄바꿈 맞춤
    git config --global init.defaultBranch main
    Ok "Git $(git --version)"
} else { Fail "Git 없음" }

# ---------------------------------------------------------------- 4. GPU (desktop)
if ($Role -eq "desktop") {
    Step "4. NVIDIA 드라이버"
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { nvidia-smi --query-gpu=name,driver_version --format=csv,noheader; Ok "드라이버 있음" }
    else { Warn "NVIDIA 드라이버 없음 → USB nvidia\ 폴더(또는 nvidia.com)의 RTX 5070 desktop용 WHQL 드라이버 설치 → 재부팅 → setup.bat 다시 실행 (GPU 확인은 그때 통과)" }
}

# ---------------------------------------------------------------- 5. 작업 폴더 · 저장소 · 가상환경
Step "5. 작업 폴더 $WorkDir"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
if ($RepoUrl -and $online -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $name = [IO.Path]::GetFileNameWithoutExtension($RepoUrl)
    if (Test-Path "$WorkDir\$name") { git -C "$WorkDir\$name" pull; Ok "저장소 갱신: $name" }
    else { git clone $RepoUrl "$WorkDir\$name"; if ($LASTEXITCODE -eq 0) { Ok "clone: $name" } else { Warn "clone 실패" } }
}

if ($py) {
    $venv = Join-Path $WorkDir "venv"
    if (-not (Test-Path "$venv\Scripts\python.exe")) { Invoke-Expression "$py -m venv `"$venv`"" }
    $vpy = "$venv\Scripts\python.exe"
    $pipArgs = @()
    if ($Offline) { $pipArgs = @("--no-index", "--find-links", (Join-Path $Offline "wheels")) }
    & $vpy -m pip install @pipArgs --upgrade pip --quiet 2>$null
    Write-Host "  공통 라이브러리"
    & $vpy -m pip install @pipArgs -r (Join-Path $Here "requirements-common.txt")
    if ($Role -eq "desktop") {
        Write-Host "  PyTorch (CUDA 12.8 빌드) — 먼저 설치해야 YOLO 가 CPU 버전을 끌어오지 않음"
        if ($Offline) { & $vpy -m pip install @pipArgs torch torchvision }
        else { & $vpy -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128 }
        & $vpy -m pip install @pipArgs -r (Join-Path $Here "requirements-train.txt")
    }
    & $vpy -m pip freeze | Out-File -Encoding utf8 (Join-Path $Here "installed-$Role.txt")
    Ok "venv: $venv  (설치된 버전: installed-$Role.txt)"
}

# ---------------------------------------------------------------- 6. VS Code 확장
Step "6. VS Code 확장 (팀 공통 2개만 — 나머지는 각자 VS Code 로그인 → 설정 동기화로 가져옴)"
Refresh-Path
$exts = @("ms-python.python", "ms-vscode-remote.remote-ssh")
if (Get-Command code -ErrorAction SilentlyContinue) {
    foreach ($e in $exts) {
        if ($Offline) {
            $vsix = Get-ChildItem (Join-Path $Offline "vsix") -Filter "$e*.vsix" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($vsix) { code --install-extension $vsix.FullName --force | Out-Null; Ok $e } else { Warn "$e : vsix 없음" }
        } else { code --install-extension $e --force | Out-Null; Ok $e }
    }
} else { Warn "VS Code 없음 (설치 후 다시 실행하면 확장도 깔림)" }
Write-Host "  개인 확장·설정: VS Code 에서 계정 로그인 → 설정 동기화 켜면 자동으로 따라옴" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 7. WSL2 + Ubuntu 22.04 + ROS2
if (-not $NoWsl) {
    Step "7. WSL2 + Ubuntu 22.04 + ROS2 Humble"
    $wslOk = $false
    try { wsl --status 2>$null | Out-Null; $wslOk = ($LASTEXITCODE -eq 0) } catch {}

    if (-not $wslOk) {
        Write-Host "  WSL 기능 켜기 (재부팅 필요)"
        dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
        dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
        if ($Offline) {
            $msi = Get-ChildItem (Join-Path $Offline "installers\Microsoft.WSL") -Filter *.msi -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($msi) { Start-Process msiexec -ArgumentList "/i `"$($msi.FullName)`" /qn /norestart" -Wait; Ok "WSL 설치(오프라인)" }
            else { Warn "offline\installers\Microsoft.WSL\*.msi 없음" }
        } elseif ($online) { wsl --install --no-distribution | Out-Null }

        # 재부팅 뒤 이어서 실행하도록 등록 (로그인하면 UAC 창이 뜸 → 예)
        $resumeArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Role $Role -Resume"
        if ($Offline) { $resumeArgs += " -Offline `"$Offline`"" }
        if ($RepoUrl) { $resumeArgs += " -RepoUrl `"$RepoUrl`"" }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "MaiconSetup" -Value "powershell $resumeArgs"
        Write-Host "`n재부팅이 필요합니다. 재부팅 후 로그인하면 자동으로 이어서 설치합니다." -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        $r = Read-Host "지금 재부팅할까요? (Y/n)"
        if ($r -ne "n") { Restart-Computer -Force }
        exit
    }

    wsl --set-default-version 2 | Out-Null
    $distros = (wsl -l -q 2>$null | Out-String)
    if ($distros -match "maicon-ros2") { Ok "WSL 배포판 maicon-ros2 있음" }
    else {
        $tar = $null
        if ($Offline) { $tar = Get-ChildItem (Join-Path $Offline "wsl") -Filter "*.tar*" -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if (-not $tar) { $tar = Get-ChildItem (Join-Path $Here "wsl") -Filter "ros2-humble-22.04.tar*" -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($tar) {
            Write-Host "  ROS2 포함 Ubuntu 가져오기: $($tar.Name) (몇 분 걸림)"
            New-Item -ItemType Directory -Force -Path "C:\WSL\maicon-ros2" | Out-Null
            wsl --import maicon-ros2 "C:\WSL\maicon-ros2" $tar.FullName --version 2
            if ($LASTEXITCODE -eq 0) { Ok "maicon-ros2 가져오기 완료 (실행: wsl -d maicon-ros2)" } else { Fail "wsl --import 실패" }
        } elseif ($online) {
            Write-Host "  Ubuntu 22.04 설치 후 ROS2 를 안에 설치 (인터넷, 15~30분)"
            wsl --install -d Ubuntu-22.04 --no-launch | Out-Null
            $sh = (Join-Path $Here "wsl\install_ros2.sh") -replace "\\", "/"
            wsl -d Ubuntu-22.04 -u root -- bash -lc "bash `"`$(wslpath '$sh')`""
            if ($LASTEXITCODE -eq 0) { Ok "Ubuntu-22.04 + ROS2 설치 완료" } else { Warn "ROS2 설치 중 오류 — wsl -d Ubuntu-22.04 로 들어가 install_ros2.sh 다시 실행" }
        } else { Warn "ROS2 rootfs tar 도 인터넷도 없음 → WSL 배포판 건너뜀" }
    }
}

# ---------------------------------------------------------------- 8. 확인
Step "8. 확인"
if ($py -and (Test-Path "$WorkDir\venv\Scripts\python.exe")) {
    # 출력이 로그(setup_log.txt)에도 남도록 Write-Host 로 받음. 한글 출력이 깨지지 않게 UTF-8
    $env:PYTHONIOENCODING = "utf-8"; $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
    & "$WorkDir\venv\Scripts\python.exe" (Join-Path $Here "check_env.py") $Role 2>&1 | ForEach-Object { Write-Host "  $_" }
    $code = $LASTEXITCODE; [Console]::OutputEncoding = $prevEnc
    if ($code -ne 0) { Fail "check_env.py 에서 문제 발견 (위 [X] 항목 확인)" }
} else { Fail "venv 가 없어 check_env.py 를 못 돌림" }
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "MaiconSetup" -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Warnings.Count) { Write-Host "확인할 것 $($script:Warnings.Count)건:" -ForegroundColor Yellow; $script:Warnings | ForEach-Object { Write-Host "  - $_" } }
else { Write-Host "모두 정상" -ForegroundColor Green }
Write-Host "가상환경 켜기:  $WorkDir\venv\Scripts\activate"
Write-Host "로그: $Log"
Stop-Transcript | Out-Null
if ($Elevated) { Read-Host "`nEnter 를 누르면 이 창이 닫힙니다" | Out-Null }
