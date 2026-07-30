#requires -version 5.0
<#
    FARMASOFT - Gestor de Rutas y DNS
    App con interfaz grafica (WinForms) para:
      - Agregar / eliminar rutas estaticas persistentes
      - Configurar servidores DNS del adaptador de red
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
# Configuracion de rutas (igual que el .bat original)
# ==========================================================
$Rutas = @("172.16.0.0", "172.16.2.0", "172.16.4.0")
$Mascara = "255.255.255.0"

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
        return "YA EXISTIA"
    }
    $resultado = route -p add $Destino mask $Mascara $Gateway 2>&1
    if ($LASTEXITCODE -ne 0) {
        return "ERROR: $resultado"
    }
    return "AGREGADA"
}

function Remove-RutaEstatica {
    param([string]$Destino)
    if (-not (Get-RouteExists -Destino $Destino)) {
        return "NO EXISTIA"
    }
    $resultado = route delete $Destino 2>&1
    if ($LASTEXITCODE -ne 0) {
        return "ERROR: $resultado"
    }
    return "ELIMINADA"
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
$form = New-Object System.Windows.Forms.Form
$form.Text = "FARMASOFT - Gestor de Rutas y DNS"
$form.Size = New-Object System.Drawing.Size(520, 560)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::White

$fontTitle = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$fontLabel = New-Object System.Drawing.Font("Segoe UI", 9)

$lblTitulo = New-Object System.Windows.Forms.Label
$lblTitulo.Text = "FARMASOFT - Gestor de Rutas y DNS"
$lblTitulo.Font = $fontTitle
$lblTitulo.AutoSize = $true
$lblTitulo.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($lblTitulo)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(15, 55)
$tabControl.Size = New-Object System.Drawing.Size(480, 460)
$form.Controls.Add($tabControl)

# --------------------- Pestaña RUTAS ---------------------
$tabRutas = New-Object System.Windows.Forms.TabPage
$tabRutas.Text = "Rutas"
$tabControl.Controls.Add($tabRutas)

$lblGw = New-Object System.Windows.Forms.Label
$lblGw.Text = "Gateway:"
$lblGw.Font = $fontLabel
$lblGw.Location = New-Object System.Drawing.Point(15, 20)
$lblGw.AutoSize = $true
$tabRutas.Controls.Add($lblGw)

$txtGw = New-Object System.Windows.Forms.TextBox
$txtGw.Location = New-Object System.Drawing.Point(100, 17)
$txtGw.Size = New-Object System.Drawing.Size(150, 25)
$tabRutas.Controls.Add($txtGw)

$lblRutasInfo = New-Object System.Windows.Forms.Label
$lblRutasInfo.Text = "Rutas gestionadas: " + ($Rutas -join ", ")
$lblRutasInfo.Font = $fontLabel
$lblRutasInfo.Location = New-Object System.Drawing.Point(15, 55)
$lblRutasInfo.AutoSize = $true
$tabRutas.Controls.Add($lblRutasInfo)

$btnAgregarRutas = New-Object System.Windows.Forms.Button
$btnAgregarRutas.Text = "Agregar rutas"
$btnAgregarRutas.Location = New-Object System.Drawing.Point(15, 90)
$btnAgregarRutas.Size = New-Object System.Drawing.Size(150, 35)
$tabRutas.Controls.Add($btnAgregarRutas)

$btnEliminarRutas = New-Object System.Windows.Forms.Button
$btnEliminarRutas.Text = "Eliminar rutas"
$btnEliminarRutas.Location = New-Object System.Drawing.Point(175, 90)
$btnEliminarRutas.Size = New-Object System.Drawing.Size(150, 35)
$tabRutas.Controls.Add($btnEliminarRutas)

$txtResultadoRutas = New-Object System.Windows.Forms.TextBox
$txtResultadoRutas.Location = New-Object System.Drawing.Point(15, 140)
$txtResultadoRutas.Size = New-Object System.Drawing.Size(440, 260)
$txtResultadoRutas.Multiline = $true
$txtResultadoRutas.ReadOnly = $true
$txtResultadoRutas.ScrollBars = "Vertical"
$txtResultadoRutas.Font = New-Object System.Drawing.Font("Consolas", 9)
$tabRutas.Controls.Add($txtResultadoRutas)

$btnAgregarRutas.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtGw.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Introduce una Gateway valida.", "FARMASOFT", "OK", "Warning")
        return
    }
    $txtResultadoRutas.Clear()
    $txtResultadoRutas.AppendText("Procesando...`r`n`r`n")
    foreach ($ruta in $Rutas) {
        $estado = Add-RutaEstatica -Destino $ruta -Gateway $txtGw.Text
        $txtResultadoRutas.AppendText("$ruta - $estado`r`n")
    }
})

$btnEliminarRutas.Add_Click({
    $txtResultadoRutas.Clear()
    $txtResultadoRutas.AppendText("Procesando...`r`n`r`n")
    foreach ($ruta in $Rutas) {
        $estado = Remove-RutaEstatica -Destino $ruta
        $txtResultadoRutas.AppendText("$ruta - $estado`r`n")
    }
})

# --------------------- Pestaña DNS ---------------------
$tabDns = New-Object System.Windows.Forms.TabPage
$tabDns.Text = "DNS"
$tabControl.Controls.Add($tabDns)

$lblAdaptador = New-Object System.Windows.Forms.Label
$lblAdaptador.Text = "Adaptador de red:"
$lblAdaptador.Font = $fontLabel
$lblAdaptador.Location = New-Object System.Drawing.Point(15, 20)
$lblAdaptador.AutoSize = $true
$tabDns.Controls.Add($lblAdaptador)

$cmbAdaptador = New-Object System.Windows.Forms.ComboBox
$cmbAdaptador.Location = New-Object System.Drawing.Point(150, 17)
$cmbAdaptador.Size = New-Object System.Drawing.Size(280, 25)
$cmbAdaptador.DropDownStyle = "DropDownList"
try {
    Get-Adaptadores | ForEach-Object { $cmbAdaptador.Items.Add($_) | Out-Null }
    if ($cmbAdaptador.Items.Count -gt 0) { $cmbAdaptador.SelectedIndex = 0 }
} catch {}
$tabDns.Controls.Add($cmbAdaptador)

$btnRefrescar = New-Object System.Windows.Forms.Button
$btnRefrescar.Text = "Refrescar"
$btnRefrescar.Location = New-Object System.Drawing.Point(15, 55)
$btnRefrescar.Size = New-Object System.Drawing.Size(415, 25)
$tabDns.Controls.Add($btnRefrescar)

$lblDns1 = New-Object System.Windows.Forms.Label
$lblDns1.Text = "DNS Preferido:"
$lblDns1.Font = $fontLabel
$lblDns1.Location = New-Object System.Drawing.Point(15, 100)
$lblDns1.AutoSize = $true
$tabDns.Controls.Add($lblDns1)

$txtDns1 = New-Object System.Windows.Forms.TextBox
$txtDns1.Location = New-Object System.Drawing.Point(150, 97)
$txtDns1.Size = New-Object System.Drawing.Size(200, 25)
$tabDns.Controls.Add($txtDns1)

$lblDns2 = New-Object System.Windows.Forms.Label
$lblDns2.Text = "DNS Alternativo:"
$lblDns2.Font = $fontLabel
$lblDns2.Location = New-Object System.Drawing.Point(15, 135)
$lblDns2.AutoSize = $true
$tabDns.Controls.Add($lblDns2)

$txtDns2 = New-Object System.Windows.Forms.TextBox
$txtDns2.Location = New-Object System.Drawing.Point(150, 132)
$txtDns2.Size = New-Object System.Drawing.Size(200, 25)
$tabDns.Controls.Add($txtDns2)

$btnAplicarDns = New-Object System.Windows.Forms.Button
$btnAplicarDns.Text = "Aplicar DNS"
$btnAplicarDns.Location = New-Object System.Drawing.Point(15, 175)
$btnAplicarDns.Size = New-Object System.Drawing.Size(200, 35)
$tabDns.Controls.Add($btnAplicarDns)

$btnRestaurarDns = New-Object System.Windows.Forms.Button
$btnRestaurarDns.Text = "Restaurar DNS (DHCP)"
$btnRestaurarDns.Location = New-Object System.Drawing.Point(230, 175)
$btnRestaurarDns.Size = New-Object System.Drawing.Size(200, 35)
$tabDns.Controls.Add($btnRestaurarDns)

$txtResultadoDns = New-Object System.Windows.Forms.TextBox
$txtResultadoDns.Location = New-Object System.Drawing.Point(15, 225)
$txtResultadoDns.Size = New-Object System.Drawing.Size(440, 175)
$txtResultadoDns.Multiline = $true
$txtResultadoDns.ReadOnly = $true
$txtResultadoDns.ScrollBars = "Vertical"
$txtResultadoDns.Font = New-Object System.Drawing.Font("Consolas", 9)
$tabDns.Controls.Add($txtResultadoDns)

$btnRefrescar.Add_Click({
    $cmbAdaptador.Items.Clear()
    try {
        Get-Adaptadores | ForEach-Object { $cmbAdaptador.Items.Add($_) | Out-Null }
        if ($cmbAdaptador.Items.Count -gt 0) { $cmbAdaptador.SelectedIndex = 0 }
    } catch {
        $txtResultadoDns.AppendText("Error al listar adaptadores: $_`r`n")
    }
})

function Test-IPv4 {
    param([string]$Ip)
    return $Ip -match '^(\d{1,3}\.){3}\d{1,3}$'
}

$btnAplicarDns.Add_Click({
    if ($cmbAdaptador.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Selecciona un adaptador de red.", "FARMASOFT", "OK", "Warning")
        return
    }
    $servidores = @()
    if (-not [string]::IsNullOrWhiteSpace($txtDns1.Text)) {
        if (-not (Test-IPv4 $txtDns1.Text)) {
            [System.Windows.Forms.MessageBox]::Show("DNS Preferido invalido.", "FARMASOFT", "OK", "Warning")
            return
        }
        $servidores += $txtDns1.Text
    }
    if (-not [string]::IsNullOrWhiteSpace($txtDns2.Text)) {
        if (-not (Test-IPv4 $txtDns2.Text)) {
            [System.Windows.Forms.MessageBox]::Show("DNS Alternativo invalido.", "FARMASOFT", "OK", "Warning")
            return
        }
        $servidores += $txtDns2.Text
    }
    if ($servidores.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Introduce al menos un servidor DNS.", "FARMASOFT", "OK", "Warning")
        return
    }
    try {
        Set-DnsAdaptador -Adaptador $cmbAdaptador.SelectedItem -Servidores $servidores
        $txtResultadoDns.AppendText("DNS aplicado en '$($cmbAdaptador.SelectedItem)': $($servidores -join ', ')`r`n")
    } catch {
        $txtResultadoDns.AppendText("ERROR al aplicar DNS: $_`r`n")
    }
})

$btnRestaurarDns.Add_Click({
    if ($cmbAdaptador.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Selecciona un adaptador de red.", "FARMASOFT", "OK", "Warning")
        return
    }
    try {
        Reset-DnsAdaptador -Adaptador $cmbAdaptador.SelectedItem
        $txtResultadoDns.AppendText("DNS restaurado a DHCP en '$($cmbAdaptador.SelectedItem)'`r`n")
    } catch {
        $txtResultadoDns.AppendText("ERROR al restaurar DNS: $_`r`n")
    }
})

[void]$form.ShowDialog()
