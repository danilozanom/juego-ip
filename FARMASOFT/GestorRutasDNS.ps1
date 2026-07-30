#requires -version 5.0
<#
    FARMASOFT - Gestor de Rutas y DNS
    App con interfaz grafica (WinForms) para:
      - Agregar / eliminar rutas estaticas persistentes
      - Añadir DNS predefinidas al adaptador de red
#>

# ==========================================================
# Comprobar permisos de Administrador y auto-elevar
# ==========================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        Write-Host "El usuario cancelo la elevacion de permisos."
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================================
# Ocultar la ventana de consola de PowerShell
# ==========================================================
Add-Type -Name Win32 -Namespace ConsoleHider -MemberDefinition '
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'
$consoleHandle = [ConsoleHider.Win32]::GetConsoleWindow()
[ConsoleHider.Win32]::ShowWindow($consoleHandle, 0) | Out-Null

# ==========================================================
# Configuracion
# ==========================================================
$Rutas = @("172.16.0.0", "172.16.2.0", "172.16.4.0")
$Mascara = "255.255.255.0"
$ServidoresDns = @("172.16.4.100", "172.16.2.100", "172.16.0.100")

# ==========================================================
# Funciones de logica
# ==========================================================
function Get-RouteExists {
    param([string]$Destino)
    $salida = route print | Select-String -SimpleMatch $Destino
    return [bool]$salida
}

function Add-RutaEstatica {
    param([string]$Destino, [string]$Gateway)
    if (Get-RouteExists -Destino $Destino) {
        return "Ya existia"
    }
    $resultado = route -p add $Destino mask $Mascara $Gateway 2>&1
    if ($LASTEXITCODE -ne 0) {
        return "Error: $resultado"
    }
    return "Agregada"
}

function Remove-RutaEstatica {
    param([string]$Destino)
    if (-not (Get-RouteExists -Destino $Destino)) {
        return "No existia"
    }
    $resultado = route delete $Destino 2>&1
    if ($LASTEXITCODE -ne 0) {
        return "Error: $resultado"
    }
    return "Eliminada"
}

function Get-Adaptadores {
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -ExpandProperty Name
}

function Set-DnsAdaptador {
    param([string]$Adaptador, [string[]]$Servidores)
    Set-DnsClientServerAddress -InterfaceAlias $Adaptador -ServerAddresses $Servidores -ErrorAction Stop
}

function Reset-DnsAdaptador {
    param([string]$Adaptador)
    Set-DnsClientServerAddress -InterfaceAlias $Adaptador -ResetServerAddresses -ErrorAction Stop
}

# ==========================================================
# Interfaz grafica
# ==========================================================
$fontBase   = New-Object System.Drawing.Font("Calibri", 10)
$fontTitulo = New-Object System.Drawing.Font("Calibri", 16, [System.Drawing.FontStyle]::Bold)
$fontBoton  = New-Object System.Drawing.Font("Calibri", 10, [System.Drawing.FontStyle]::Bold)
$fontLog    = New-Object System.Drawing.Font("Consolas", 9)

$colorFondo   = [System.Drawing.Color]::FromArgb(246, 247, 249)
$colorAccento = [System.Drawing.Color]::FromArgb(0, 120, 212)
$colorTexto   = [System.Drawing.Color]::FromArgb(40, 40, 40)

$form = New-Object System.Windows.Forms.Form
$form.Text = "FARMASOFT"
$form.Size = New-Object System.Drawing.Size(460, 520)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $colorFondo
$form.Font = $fontBase

$lblTitulo = New-Object System.Windows.Forms.Label
$lblTitulo.Text = "FARMASOFT"
$lblTitulo.Font = $fontTitulo
$lblTitulo.ForeColor = $colorAccento
$lblTitulo.AutoSize = $true
$lblTitulo.Location = New-Object System.Drawing.Point(25, 20)
$form.Controls.Add($lblTitulo)

$lblSubtitulo = New-Object System.Windows.Forms.Label
$lblSubtitulo.Text = "Gestor de rutas y DNS"
$lblSubtitulo.ForeColor = [System.Drawing.Color]::Gray
$lblSubtitulo.AutoSize = $true
$lblSubtitulo.Location = New-Object System.Drawing.Point(27, 55)
$form.Controls.Add($lblSubtitulo)

# --------------------- Seccion RUTAS ---------------------
$lblSeccionRutas = New-Object System.Windows.Forms.Label
$lblSeccionRutas.Text = "Rutas"
$lblSeccionRutas.Font = $fontBoton
$lblSeccionRutas.ForeColor = $colorTexto
$lblSeccionRutas.AutoSize = $true
$lblSeccionRutas.Location = New-Object System.Drawing.Point(25, 95)
$form.Controls.Add($lblSeccionRutas)

$lblGw = New-Object System.Windows.Forms.Label
$lblGw.Text = "Gateway"
$lblGw.ForeColor = $colorTexto
$lblGw.AutoSize = $true
$lblGw.Location = New-Object System.Drawing.Point(25, 128)
$form.Controls.Add($lblGw)

$txtGw = New-Object System.Windows.Forms.TextBox
$txtGw.Location = New-Object System.Drawing.Point(110, 124)
$txtGw.Size = New-Object System.Drawing.Size(180, 26)
$form.Controls.Add($txtGw)

$btnAgregarRutas = New-Object System.Windows.Forms.Button
$btnAgregarRutas.Text = "Añadir rutas"
$btnAgregarRutas.Font = $fontBoton
$btnAgregarRutas.FlatStyle = "Flat"
$btnAgregarRutas.FlatAppearance.BorderSize = 0
$btnAgregarRutas.BackColor = $colorAccento
$btnAgregarRutas.ForeColor = [System.Drawing.Color]::White
$btnAgregarRutas.Location = New-Object System.Drawing.Point(25, 165)
$btnAgregarRutas.Size = New-Object System.Drawing.Size(190, 38)
$form.Controls.Add($btnAgregarRutas)

$btnEliminarRutas = New-Object System.Windows.Forms.Button
$btnEliminarRutas.Text = "Eliminar rutas"
$btnEliminarRutas.Font = $fontBoton
$btnEliminarRutas.FlatStyle = "Flat"
$btnEliminarRutas.FlatAppearance.BorderSize = 1
$btnEliminarRutas.FlatAppearance.BorderColor = $colorAccento
$btnEliminarRutas.BackColor = [System.Drawing.Color]::White
$btnEliminarRutas.ForeColor = $colorAccento
$btnEliminarRutas.Location = New-Object System.Drawing.Point(225, 165)
$btnEliminarRutas.Size = New-Object System.Drawing.Size(190, 38)
$form.Controls.Add($btnEliminarRutas)

# --------------------- Seccion DNS ---------------------
$lblSeccionDns = New-Object System.Windows.Forms.Label
$lblSeccionDns.Text = "DNS"
$lblSeccionDns.Font = $fontBoton
$lblSeccionDns.ForeColor = $colorTexto
$lblSeccionDns.AutoSize = $true
$lblSeccionDns.Location = New-Object System.Drawing.Point(25, 225)
$form.Controls.Add($lblSeccionDns)

$lblAdaptador = New-Object System.Windows.Forms.Label
$lblAdaptador.Text = "Adaptador"
$lblAdaptador.ForeColor = $colorTexto
$lblAdaptador.AutoSize = $true
$lblAdaptador.Location = New-Object System.Drawing.Point(25, 260)
$form.Controls.Add($lblAdaptador)

$cmbAdaptador = New-Object System.Windows.Forms.ComboBox
$cmbAdaptador.Location = New-Object System.Drawing.Point(110, 256)
$cmbAdaptador.Size = New-Object System.Drawing.Size(305, 26)
$cmbAdaptador.DropDownStyle = "DropDownList"
try {
    Get-Adaptadores | ForEach-Object { $cmbAdaptador.Items.Add($_) | Out-Null }
    if ($cmbAdaptador.Items.Count -gt 0) { $cmbAdaptador.SelectedIndex = 0 }
} catch {}
$form.Controls.Add($cmbAdaptador)

$lblDnsInfo = New-Object System.Windows.Forms.Label
$lblDnsInfo.Text = "Se aplicaran: " + ($ServidoresDns -join "  ->  ")
$lblDnsInfo.ForeColor = [System.Drawing.Color]::Gray
$lblDnsInfo.AutoSize = $true
$lblDnsInfo.Location = New-Object System.Drawing.Point(25, 292)
$form.Controls.Add($lblDnsInfo)

$btnAplicarDns = New-Object System.Windows.Forms.Button
$btnAplicarDns.Text = "Añadir DNS"
$btnAplicarDns.Font = $fontBoton
$btnAplicarDns.FlatStyle = "Flat"
$btnAplicarDns.FlatAppearance.BorderSize = 0
$btnAplicarDns.BackColor = $colorAccento
$btnAplicarDns.ForeColor = [System.Drawing.Color]::White
$btnAplicarDns.Location = New-Object System.Drawing.Point(25, 320)
$btnAplicarDns.Size = New-Object System.Drawing.Size(190, 38)
$form.Controls.Add($btnAplicarDns)

$btnRestaurarDns = New-Object System.Windows.Forms.Button
$btnRestaurarDns.Text = "Restaurar DNS"
$btnRestaurarDns.Font = $fontBoton
$btnRestaurarDns.FlatStyle = "Flat"
$btnRestaurarDns.FlatAppearance.BorderSize = 1
$btnRestaurarDns.FlatAppearance.BorderColor = $colorAccento
$btnRestaurarDns.BackColor = [System.Drawing.Color]::White
$btnRestaurarDns.ForeColor = $colorAccento
$btnRestaurarDns.Location = New-Object System.Drawing.Point(225, 320)
$btnRestaurarDns.Size = New-Object System.Drawing.Size(190, 38)
$form.Controls.Add($btnRestaurarDns)

# --------------------- Registro de actividad ---------------------
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(25, 375)
$txtLog.Size = New-Object System.Drawing.Size(390, 100)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Font = $fontLog
$txtLog.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($txtLog)

function Write-Log {
    param([string]$Texto)
    $txtLog.AppendText("$Texto`r`n")
}

# --------------------- Eventos ---------------------
$btnAgregarRutas.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtGw.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Introduce una Gateway valida.", "FARMASOFT", "OK", "Warning")
        return
    }
    Write-Log "Añadiendo rutas..."
    foreach ($ruta in $Rutas) {
        $estado = Add-RutaEstatica -Destino $ruta -Gateway $txtGw.Text
        Write-Log "$ruta -> $estado"
    }
})

$btnEliminarRutas.Add_Click({
    Write-Log "Eliminando rutas..."
    foreach ($ruta in $Rutas) {
        $estado = Remove-RutaEstatica -Destino $ruta
        Write-Log "$ruta -> $estado"
    }
})

$btnAplicarDns.Add_Click({
    if ($cmbAdaptador.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Selecciona un adaptador de red.", "FARMASOFT", "OK", "Warning")
        return
    }
    try {
        Set-DnsAdaptador -Adaptador $cmbAdaptador.SelectedItem -Servidores $ServidoresDns
        Write-Log "DNS aplicado en '$($cmbAdaptador.SelectedItem)': $($ServidoresDns -join ', ')"
    } catch {
        Write-Log "Error al aplicar DNS: $_"
    }
})

$btnRestaurarDns.Add_Click({
    if ($cmbAdaptador.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Selecciona un adaptador de red.", "FARMASOFT", "OK", "Warning")
        return
    }
    try {
        Reset-DnsAdaptador -Adaptador $cmbAdaptador.SelectedItem
        Write-Log "DNS restaurado a DHCP en '$($cmbAdaptador.SelectedItem)'"
    } catch {
        Write-Log "Error al restaurar DNS: $_"
    }
})

[void]$form.ShowDialog()
