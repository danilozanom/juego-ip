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
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
'
$consoleHandle = [ConsoleHider.Win32]::GetConsoleWindow()
[ConsoleHider.Win32]::ShowWindow($consoleHandle, 0) | Out-Null

# ==========================================================
# Evitar que Windows escale mal la interfaz (letras borrosas/enormes)
# ==========================================================
[ConsoleHider.Win32]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ==========================================================
# Configuracion
# ==========================================================
$Rutas = @("172.16.0.0", "172.16.2.0", "172.16.4.0")
$Mascara = "255.255.255.0"
$ServidoresDns = @("172.16.4.100", "172.16.2.100", "172.16.0.100", "8.8.8.8")
$ServidoresDnsPorDefecto = @("8.8.8.8", "1.1.1.1")

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

function Get-GatewayPredeterminada {
    $ruta = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne "0.0.0.0" } |
        Sort-Object -Property RouteMetric |
        Select-Object -First 1
    if ($ruta) { return $ruta.NextHop }
    return $null
}

function Set-DnsAdaptador {
    param([string]$Adaptador, [string[]]$Servidores)
    Set-DnsClientServerAddress -InterfaceAlias $Adaptador -ServerAddresses $Servidores -ErrorAction Stop
}

function Reset-DnsAdaptador {
    param([string]$Adaptador, [string[]]$Servidores)
    Set-DnsClientServerAddress -InterfaceAlias $Adaptador -ServerAddresses $Servidores -ErrorAction Stop
}

# ==========================================================
# Interfaz grafica
# ==========================================================
$fontBase    = New-Object System.Drawing.Font("Segoe UI", 10)
$fontLogo    = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$fontLogoSub = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$fontLogoSub2= New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$fontBoton   = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fontLog     = New-Object System.Drawing.Font("Segoe UI", 9.5)

$colorFondo    = [System.Drawing.Color]::FromArgb(246, 247, 249)
$colorAccento  = [System.Drawing.Color]::FromArgb(0, 120, 212)
$colorTexto    = [System.Drawing.Color]::FromArgb(40, 40, 40)
$colorLogoAzul = [System.Drawing.Color]::FromArgb(11, 45, 92)
$colorLogoNaranja = [System.Drawing.Color]::FromArgb(240, 120, 90)
$colorOk       = [System.Drawing.Color]::FromArgb(30, 140, 70)
$colorError    = [System.Drawing.Color]::FromArgb(200, 45, 45)
$colorAviso    = [System.Drawing.Color]::FromArgb(150, 150, 150)

$form = New-Object System.Windows.Forms.Form
$form.Text = "FARMASOFT"
$form.Size = New-Object System.Drawing.Size(520, 740)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $colorFondo
$form.Font = $fontBase
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96.0, 96.0)

# --------------------- Logotipo ---------------------
$lblLogo = New-Object System.Windows.Forms.Label
$lblLogo.Text = "Farmasoft"
$lblLogo.Font = $fontLogo
$lblLogo.ForeColor = $colorLogoAzul
$lblLogo.AutoSize = $true
$lblLogo.Location = New-Object System.Drawing.Point(30, 20)
$form.Controls.Add($lblLogo)

$lblLogoSub1 = New-Object System.Windows.Forms.Label
$lblLogoSub1.Text = "una empresa"
$lblLogoSub1.Font = $fontLogoSub
$lblLogoSub1.ForeColor = $colorLogoNaranja
$lblLogoSub1.AutoSize = $true
$lblLogoSub1.Location = New-Object System.Drawing.Point(210, 26)
$form.Controls.Add($lblLogoSub1)

$lblLogoSub2 = New-Object System.Windows.Forms.Label
$lblLogoSub2.Text = "Glintt Life"
$lblLogoSub2.Font = $fontLogoSub2
$lblLogoSub2.ForeColor = $colorLogoNaranja
$lblLogoSub2.AutoSize = $true
$lblLogoSub2.Location = New-Object System.Drawing.Point(210, 42)
$form.Controls.Add($lblLogoSub2)

$lblSubtitulo = New-Object System.Windows.Forms.Label
$lblSubtitulo.Text = "Gestor de DNS y Routes"
$lblSubtitulo.ForeColor = [System.Drawing.Color]::Gray
$lblSubtitulo.AutoSize = $true
$lblSubtitulo.Location = New-Object System.Drawing.Point(32, 68)
$form.Controls.Add($lblSubtitulo)

# --------------------- Seccion RUTAS ---------------------
$lblSeccionRutas = New-Object System.Windows.Forms.Label
$lblSeccionRutas.Text = "Rutas"
$lblSeccionRutas.Font = $fontBoton
$lblSeccionRutas.ForeColor = $colorTexto
$lblSeccionRutas.AutoSize = $true
$lblSeccionRutas.Location = New-Object System.Drawing.Point(30, 120)
$form.Controls.Add($lblSeccionRutas)

$lblGw = New-Object System.Windows.Forms.Label
$lblGw.Text = "Gateway"
$lblGw.ForeColor = $colorTexto
$lblGw.AutoSize = $true
$lblGw.Location = New-Object System.Drawing.Point(30, 158)
$form.Controls.Add($lblGw)

$txtGw = New-Object System.Windows.Forms.TextBox
$txtGw.Font = $fontBase
$txtGw.Location = New-Object System.Drawing.Point(125, 154)
$txtGw.Size = New-Object System.Drawing.Size(220, 28)
$form.Controls.Add($txtGw)

$btnDetectarGw = New-Object System.Windows.Forms.Button
$btnDetectarGw.Text = "Detectar"
$btnDetectarGw.Font = $fontBoton
$btnDetectarGw.FlatStyle = "Flat"
$btnDetectarGw.FlatAppearance.BorderSize = 1
$btnDetectarGw.FlatAppearance.BorderColor = $colorAccento
$btnDetectarGw.BackColor = [System.Drawing.Color]::White
$btnDetectarGw.ForeColor = $colorAccento
$btnDetectarGw.Location = New-Object System.Drawing.Point(355, 153)
$btnDetectarGw.Size = New-Object System.Drawing.Size(105, 30)
$btnDetectarGw.UseVisualStyleBackColor = $false
$form.Controls.Add($btnDetectarGw)

$btnDetectarGw.Add_Click({
    $gwDetectada = Get-GatewayPredeterminada
    if ($gwDetectada) {
        $txtGw.Text = $gwDetectada
    } else {
        [System.Windows.Forms.MessageBox]::Show("No se pudo detectar la Gateway automaticamente.", "FARMASOFT", "OK", "Warning")
    }
})

$btnAgregarRutas = New-Object System.Windows.Forms.Button
$btnAgregarRutas.Text = "Añadir rutas"
$btnAgregarRutas.Font = $fontBoton
$btnAgregarRutas.FlatStyle = "Flat"
$btnAgregarRutas.FlatAppearance.BorderSize = 0
$btnAgregarRutas.BackColor = $colorAccento
$btnAgregarRutas.ForeColor = [System.Drawing.Color]::White
$btnAgregarRutas.Location = New-Object System.Drawing.Point(30, 195)
$btnAgregarRutas.Size = New-Object System.Drawing.Size(222, 42)
$btnAgregarRutas.UseVisualStyleBackColor = $false
$form.Controls.Add($btnAgregarRutas)

$btnEliminarRutas = New-Object System.Windows.Forms.Button
$btnEliminarRutas.Text = "Eliminar rutas"
$btnEliminarRutas.Font = $fontBoton
$btnEliminarRutas.FlatStyle = "Flat"
$btnEliminarRutas.FlatAppearance.BorderSize = 1
$btnEliminarRutas.FlatAppearance.BorderColor = $colorAccento
$btnEliminarRutas.BackColor = [System.Drawing.Color]::White
$btnEliminarRutas.ForeColor = $colorAccento
$btnEliminarRutas.Location = New-Object System.Drawing.Point(268, 195)
$btnEliminarRutas.Size = New-Object System.Drawing.Size(222, 42)
$btnEliminarRutas.UseVisualStyleBackColor = $false
$form.Controls.Add($btnEliminarRutas)

$btnComprobarRutas = New-Object System.Windows.Forms.Button
$btnComprobarRutas.Text = "Comprobar rutas"
$btnComprobarRutas.Font = $fontBoton
$btnComprobarRutas.FlatStyle = "Flat"
$btnComprobarRutas.FlatAppearance.BorderSize = 1
$btnComprobarRutas.FlatAppearance.BorderColor = $colorAccento
$btnComprobarRutas.BackColor = [System.Drawing.Color]::White
$btnComprobarRutas.ForeColor = $colorAccento
$btnComprobarRutas.Location = New-Object System.Drawing.Point(30, 245)
$btnComprobarRutas.Size = New-Object System.Drawing.Size(460, 38)
$btnComprobarRutas.UseVisualStyleBackColor = $false
$form.Controls.Add($btnComprobarRutas)

# --------------------- Seccion DNS ---------------------
$lblSeccionDns = New-Object System.Windows.Forms.Label
$lblSeccionDns.Text = "DNS"
$lblSeccionDns.Font = $fontBoton
$lblSeccionDns.ForeColor = $colorTexto
$lblSeccionDns.AutoSize = $true
$lblSeccionDns.Location = New-Object System.Drawing.Point(30, 300)
$form.Controls.Add($lblSeccionDns)

$lblAdaptador = New-Object System.Windows.Forms.Label
$lblAdaptador.Text = "Adaptador"
$lblAdaptador.ForeColor = $colorTexto
$lblAdaptador.AutoSize = $true
$lblAdaptador.Location = New-Object System.Drawing.Point(30, 338)
$form.Controls.Add($lblAdaptador)

$cmbAdaptador = New-Object System.Windows.Forms.ComboBox
$cmbAdaptador.Font = $fontBase
$cmbAdaptador.Location = New-Object System.Drawing.Point(125, 334)
$cmbAdaptador.Size = New-Object System.Drawing.Size(335, 28)
$cmbAdaptador.DropDownStyle = "DropDownList"
try {
    Get-Adaptadores | ForEach-Object { $cmbAdaptador.Items.Add($_) | Out-Null }
    if ($cmbAdaptador.Items.Count -gt 0) { $cmbAdaptador.SelectedIndex = 0 }
} catch {}
$form.Controls.Add($cmbAdaptador)

$lblDnsInfo = New-Object System.Windows.Forms.Label
$lblDnsInfo.Text = "Se aplicaran:`r`n" + ($ServidoresDns -join "  ->  ")
$lblDnsInfo.ForeColor = [System.Drawing.Color]::Gray
$lblDnsInfo.AutoSize = $true
$lblDnsInfo.Location = New-Object System.Drawing.Point(30, 372)
$form.Controls.Add($lblDnsInfo)

$btnAplicarDns = New-Object System.Windows.Forms.Button
$btnAplicarDns.Text = "Añadir DNS"
$btnAplicarDns.Font = $fontBoton
$btnAplicarDns.FlatStyle = "Flat"
$btnAplicarDns.FlatAppearance.BorderSize = 0
$btnAplicarDns.BackColor = $colorAccento
$btnAplicarDns.ForeColor = [System.Drawing.Color]::White
$btnAplicarDns.Location = New-Object System.Drawing.Point(30, 440)
$btnAplicarDns.Size = New-Object System.Drawing.Size(222, 42)
$btnAplicarDns.UseVisualStyleBackColor = $false
$form.Controls.Add($btnAplicarDns)

$btnRestaurarDns = New-Object System.Windows.Forms.Button
$btnRestaurarDns.Text = "Restaurar DNS"
$btnRestaurarDns.Font = $fontBoton
$btnRestaurarDns.FlatStyle = "Flat"
$btnRestaurarDns.FlatAppearance.BorderSize = 1
$btnRestaurarDns.FlatAppearance.BorderColor = $colorAccento
$btnRestaurarDns.BackColor = [System.Drawing.Color]::White
$btnRestaurarDns.ForeColor = $colorAccento
$btnRestaurarDns.Location = New-Object System.Drawing.Point(268, 440)
$btnRestaurarDns.Size = New-Object System.Drawing.Size(222, 42)
$btnRestaurarDns.UseVisualStyleBackColor = $false
$form.Controls.Add($btnRestaurarDns)

# --------------------- Registro de actividad ---------------------
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Registro de actividad"
$lblLog.Font = $fontBoton
$lblLog.ForeColor = $colorTexto
$lblLog.AutoSize = $true
$lblLog.Location = New-Object System.Drawing.Point(30, 500)
$form.Controls.Add($lblLog)

$panelLog = New-Object System.Windows.Forms.Panel
$panelLog.Location = New-Object System.Drawing.Point(30, 530)
$panelLog.Size = New-Object System.Drawing.Size(460, 150)
$panelLog.BackColor = [System.Drawing.Color]::FromArgb(215, 218, 222)
$form.Controls.Add($panelLog)

$dgvLog = New-Object System.Windows.Forms.DataGridView
$dgvLog.Location = New-Object System.Drawing.Point(1, 1)
$dgvLog.Size = New-Object System.Drawing.Size(458, 148)
$dgvLog.BackgroundColor = [System.Drawing.Color]::White
$dgvLog.BorderStyle = "None"
$dgvLog.Font = $fontLog
$dgvLog.ColumnHeadersVisible = $false
$dgvLog.RowHeadersVisible = $false
$dgvLog.AllowUserToAddRows = $false
$dgvLog.AllowUserToDeleteRows = $false
$dgvLog.AllowUserToResizeRows = $false
$dgvLog.AllowUserToResizeColumns = $false
$dgvLog.ReadOnly = $true
$dgvLog.MultiSelect = $false
$dgvLog.SelectionMode = "FullRowSelect"
$dgvLog.CellBorderStyle = "SingleHorizontal"
$dgvLog.GridColor = [System.Drawing.Color]::FromArgb(230, 231, 233)
$dgvLog.RowTemplate.Height = 28
$dgvLog.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(235, 244, 253)
$dgvLog.DefaultCellStyle.SelectionForeColor = $colorTexto
$dgvLog.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$dgvLog.EnableHeadersVisualStyles = $false
$dgvLog.ScrollBars = "Vertical"

$colHora = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colHora.Name = "Hora"
$colHora.Width = 65
$colHora.SortMode = "NotSortable"
$dgvLog.Columns.Add($colHora) | Out-Null

$colEvento = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colEvento.Name = "Evento"
$colEvento.AutoSizeMode = "Fill"
$colEvento.SortMode = "NotSortable"
$dgvLog.Columns.Add($colEvento) | Out-Null

$colEstado = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colEstado.Name = "Estado"
$colEstado.Width = 110
$colEstado.SortMode = "NotSortable"
$colEstado.DefaultCellStyle.Alignment = "MiddleRight"
$colEstado.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$dgvLog.Columns.Add($colEstado) | Out-Null

$panelLog.Controls.Add($dgvLog)

$dgvLog.Add_CellFormatting({
    param($sender, $e)
    if ($dgvLog.Columns[$e.ColumnIndex].Name -ne "Estado") { return }
    $valor = [string]$e.Value
    if ($valor -match "Error") {
        $e.CellStyle.ForeColor = $colorError
    } elseif ($valor -match "Agregada|Aplicado|Eliminada|Restaurado|^Existe$") {
        $e.CellStyle.ForeColor = $colorOk
    } elseif ($valor -match "Ya existia|No existia|No existe") {
        $e.CellStyle.ForeColor = $colorAviso
    } else {
        $e.CellStyle.ForeColor = $colorTexto
    }
})

function Write-Log {
    param([string]$Evento, [string]$Estado)
    $marca = Get-Date -Format "HH:mm:ss"
    $fila = $dgvLog.Rows.Add($marca, $Evento, $Estado)
    $dgvLog.FirstDisplayedScrollingRowIndex = $dgvLog.Rows.Count - 1
}

# --------------------- Eventos ---------------------
$btnAgregarRutas.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtGw.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Introduce una Gateway valida.", "FARMASOFT", "OK", "Warning")
        return
    }
    foreach ($ruta in $Rutas) {
        $estado = Add-RutaEstatica -Destino $ruta -Gateway $txtGw.Text
        Write-Log -Evento "Ruta $ruta" -Estado $estado
    }
})

$btnEliminarRutas.Add_Click({
    foreach ($ruta in $Rutas) {
        $estado = Remove-RutaEstatica -Destino $ruta
        Write-Log -Evento "Ruta $ruta" -Estado $estado
    }
})

$btnComprobarRutas.Add_Click({
    foreach ($ruta in $Rutas) {
        if (Get-RouteExists -Destino $ruta) {
            Write-Log -Evento "Ruta $ruta" -Estado "Existe"
        } else {
            Write-Log -Evento "Ruta $ruta" -Estado "No existe"
        }
    }
})

$btnAplicarDns.Add_Click({
    if ($cmbAdaptador.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Selecciona un adaptador de red.", "FARMASOFT", "OK", "Warning")
        return
    }
    try {
        Set-DnsAdaptador -Adaptador $cmbAdaptador.SelectedItem -Servidores $ServidoresDns
        Write-Log -Evento "DNS en $($cmbAdaptador.SelectedItem): $($ServidoresDns -join ', ')" -Estado "Aplicado"
    } catch {
        Write-Log -Evento "DNS en $($cmbAdaptador.SelectedItem): $_" -Estado "Error"
    }
})

$btnRestaurarDns.Add_Click({
    if ($cmbAdaptador.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Selecciona un adaptador de red.", "FARMASOFT", "OK", "Warning")
        return
    }
    try {
        Reset-DnsAdaptador -Adaptador $cmbAdaptador.SelectedItem -Servidores $ServidoresDnsPorDefecto
        Write-Log -Evento "DNS en $($cmbAdaptador.SelectedItem): $($ServidoresDnsPorDefecto -join ', ')" -Estado "Restaurado"
    } catch {
        Write-Log -Evento "DNS en $($cmbAdaptador.SelectedItem): $_" -Estado "Error"
    }
})

# --------------------- Autodeteccion inicial ---------------------
$gwInicial = Get-GatewayPredeterminada
if ($gwInicial) {
    $txtGw.Text = $gwInicial
}

[void]$form.ShowDialog()
