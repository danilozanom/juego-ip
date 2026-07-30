#requires -version 5.0
<#
    FARMASOFT - Gestor de DNS y Routes
    App con interfaz grafica (WinForms) para:
      - Agregar / eliminar / comprobar rutas estaticas persistentes
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
    # Las farmacias tienen dos redes IPv4 (192.x y 172.x). La puerta de enlace
    # del equipo suele ser la 192.x, pero las rutas necesitan la gateway de la
    # red 172.x: se detecta la IP local que empieza por 172. y se cambia el
    # ultimo octeto por 1.
    $ip172 = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -like "172.*" } |
        Select-Object -First 1
    if ($ip172) {
        $octetos = $ip172.IPAddress -split "\."
        $octetos[3] = "1"
        return ($octetos -join ".")
    }

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
# Paleta y tipografia
# ==========================================================
$fontBase    = New-Object System.Drawing.Font("Segoe UI", 10)
$fontTitulo  = New-Object System.Drawing.Font("Segoe UI Semibold", 20, [System.Drawing.FontStyle]::Bold)
$fontSub     = New-Object System.Drawing.Font("Segoe UI", 10)
$fontSeccion = New-Object System.Drawing.Font("Segoe UI Semibold", 11, [System.Drawing.FontStyle]::Bold)
$fontBoton   = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$fontLog     = New-Object System.Drawing.Font("Segoe UI", 9.5)
$fontLogEstado = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5, [System.Drawing.FontStyle]::Bold)

$colorFondo   = [System.Drawing.Color]::FromArgb(244, 245, 247)
$colorTarjeta = [System.Drawing.Color]::White
$colorBorde   = [System.Drawing.Color]::FromArgb(224, 226, 230)
$colorAccento = [System.Drawing.Color]::FromArgb(0, 112, 200)
$colorTexto   = [System.Drawing.Color]::FromArgb(32, 34, 38)
$colorTextoSuave = [System.Drawing.Color]::FromArgb(110, 114, 122)
$colorOk      = [System.Drawing.Color]::FromArgb(20, 140, 80)
$colorError   = [System.Drawing.Color]::FromArgb(205, 45, 45)
$colorAviso   = [System.Drawing.Color]::FromArgb(150, 150, 150)

# ==========================================================
# Formulario principal
# ==========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "FARMASOFT"
$form.Size = New-Object System.Drawing.Size(560, 800)
$form.MinimumSize = New-Object System.Drawing.Size(500, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $true
$form.BackColor = $colorFondo
$form.Font = $fontBase
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96.0, 96.0)
$form.Padding = New-Object System.Windows.Forms.Padding(20)

# --------------------- Layout raiz ---------------------
$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = "Fill"
$root.ColumnCount = 1
$root.RowCount = 4
$root.BackColor = $colorFondo
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$form.Controls.Add($root)

function New-Tarjeta {
    param([string]$Titulo)
    $grupo = New-Object System.Windows.Forms.GroupBox
    $grupo.Text = $Titulo
    $grupo.Font = $fontSeccion
    $grupo.ForeColor = $colorTexto
    $grupo.BackColor = $colorTarjeta
    $grupo.Dock = "Fill"
    $grupo.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
    $grupo.Padding = New-Object System.Windows.Forms.Padding(15, 12, 15, 15)
    return $grupo
}

# --------------------- Cabecera ---------------------
$panelHeader = New-Object System.Windows.Forms.Panel
$panelHeader.AutoSize = $true
$panelHeader.Dock = "Top"
$panelHeader.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)

$lblTitulo = New-Object System.Windows.Forms.Label
$lblTitulo.Text = "Farmasoft"
$lblTitulo.Font = $fontTitulo
$lblTitulo.ForeColor = $colorAccento
$lblTitulo.AutoSize = $true
$lblTitulo.Location = New-Object System.Drawing.Point(0, 0)
$panelHeader.Controls.Add($lblTitulo)

$lblSubtitulo = New-Object System.Windows.Forms.Label
$lblSubtitulo.Text = "Gestor de DNS y Routes"
$lblSubtitulo.Font = $fontSub
$lblSubtitulo.ForeColor = $colorTextoSuave
$lblSubtitulo.AutoSize = $true
$lblSubtitulo.Location = New-Object System.Drawing.Point(3, 38)
$panelHeader.Controls.Add($lblSubtitulo)

$panelHeader.Height = 65
$root.Controls.Add($panelHeader, 0, 0)

# --------------------- Tarjeta RUTAS ---------------------
$grupoRutas = New-Tarjeta -Titulo "Rutas"
$tablaRutas = New-Object System.Windows.Forms.TableLayoutPanel
$tablaRutas.Dock = "Fill"
$tablaRutas.ColumnCount = 3
$tablaRutas.RowCount = 2
$tablaRutas.BackColor = $colorTarjeta
[void]$tablaRutas.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tablaRutas.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tablaRutas.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tablaRutas.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tablaRutas.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

$lblGw = New-Object System.Windows.Forms.Label
$lblGw.Text = "Gateway"
$lblGw.ForeColor = $colorTexto
$lblGw.AutoSize = $true
$lblGw.Anchor = "Left"
$lblGw.Margin = New-Object System.Windows.Forms.Padding(0, 8, 10, 8)
$tablaRutas.Controls.Add($lblGw, 0, 0)

$txtGw = New-Object System.Windows.Forms.TextBox
$txtGw.Font = $fontBase
$txtGw.Dock = "Fill"
$txtGw.Margin = New-Object System.Windows.Forms.Padding(0, 5, 10, 5)
$tablaRutas.Controls.Add($txtGw, 1, 0)

$btnDetectarGw = New-Object System.Windows.Forms.Button
$btnDetectarGw.Text = "Detectar"
$btnDetectarGw.Font = $fontBoton
$btnDetectarGw.FlatStyle = "Flat"
$btnDetectarGw.FlatAppearance.BorderSize = 1
$btnDetectarGw.FlatAppearance.BorderColor = $colorAccento
$btnDetectarGw.BackColor = [System.Drawing.Color]::White
$btnDetectarGw.ForeColor = $colorAccento
$btnDetectarGw.Width = 100
$btnDetectarGw.Height = 32
$btnDetectarGw.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
$btnDetectarGw.UseVisualStyleBackColor = $false
$tablaRutas.Controls.Add($btnDetectarGw, 2, 0)

$panelBotonesRutas = New-Object System.Windows.Forms.TableLayoutPanel
$panelBotonesRutas.Dock = "Fill"
$panelBotonesRutas.ColumnCount = 3
$panelBotonesRutas.RowCount = 1
$panelBotonesRutas.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
$panelBotonesRutas.BackColor = $colorTarjeta
[void]$panelBotonesRutas.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)))
[void]$panelBotonesRutas.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)))
[void]$panelBotonesRutas.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.34)))
$tablaRutas.SetColumnSpan($panelBotonesRutas, 3)
$tablaRutas.Controls.Add($panelBotonesRutas, 0, 1)

$btnAgregarRutas = New-Object System.Windows.Forms.Button
$btnAgregarRutas.Text = "Añadir"
$btnAgregarRutas.Font = $fontBoton
$btnAgregarRutas.FlatStyle = "Flat"
$btnAgregarRutas.FlatAppearance.BorderSize = 0
$btnAgregarRutas.BackColor = $colorAccento
$btnAgregarRutas.ForeColor = [System.Drawing.Color]::White
$btnAgregarRutas.Dock = "Fill"
$btnAgregarRutas.Height = 38
$btnAgregarRutas.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
$btnAgregarRutas.UseVisualStyleBackColor = $false
$panelBotonesRutas.Controls.Add($btnAgregarRutas, 0, 0)

$btnEliminarRutas = New-Object System.Windows.Forms.Button
$btnEliminarRutas.Text = "Eliminar"
$btnEliminarRutas.Font = $fontBoton
$btnEliminarRutas.FlatStyle = "Flat"
$btnEliminarRutas.FlatAppearance.BorderSize = 1
$btnEliminarRutas.FlatAppearance.BorderColor = $colorAccento
$btnEliminarRutas.BackColor = [System.Drawing.Color]::White
$btnEliminarRutas.ForeColor = $colorAccento
$btnEliminarRutas.Dock = "Fill"
$btnEliminarRutas.Height = 38
$btnEliminarRutas.Margin = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$btnEliminarRutas.UseVisualStyleBackColor = $false
$panelBotonesRutas.Controls.Add($btnEliminarRutas, 1, 0)

$btnComprobarRutas = New-Object System.Windows.Forms.Button
$btnComprobarRutas.Text = "Comprobar"
$btnComprobarRutas.Font = $fontBoton
$btnComprobarRutas.FlatStyle = "Flat"
$btnComprobarRutas.FlatAppearance.BorderSize = 1
$btnComprobarRutas.FlatAppearance.BorderColor = $colorBorde
$btnComprobarRutas.BackColor = [System.Drawing.Color]::White
$btnComprobarRutas.ForeColor = $colorTextoSuave
$btnComprobarRutas.Dock = "Fill"
$btnComprobarRutas.Height = 38
$btnComprobarRutas.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
$btnComprobarRutas.UseVisualStyleBackColor = $false
$panelBotonesRutas.Controls.Add($btnComprobarRutas, 2, 0)

$grupoRutas.Controls.Add($tablaRutas)
$root.Controls.Add($grupoRutas, 0, 1)

# --------------------- Tarjeta DNS ---------------------
$grupoDns = New-Tarjeta -Titulo "DNS"
$tablaDns = New-Object System.Windows.Forms.TableLayoutPanel
$tablaDns.Dock = "Fill"
$tablaDns.ColumnCount = 2
$tablaDns.RowCount = 3
$tablaDns.BackColor = $colorTarjeta
[void]$tablaDns.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tablaDns.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tablaDns.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tablaDns.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tablaDns.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

$lblAdaptador = New-Object System.Windows.Forms.Label
$lblAdaptador.Text = "Adaptador"
$lblAdaptador.ForeColor = $colorTexto
$lblAdaptador.AutoSize = $true
$lblAdaptador.Anchor = "Left"
$lblAdaptador.Margin = New-Object System.Windows.Forms.Padding(0, 8, 10, 8)
$tablaDns.Controls.Add($lblAdaptador, 0, 0)

$cmbAdaptador = New-Object System.Windows.Forms.ComboBox
$cmbAdaptador.Font = $fontBase
$cmbAdaptador.Dock = "Fill"
$cmbAdaptador.Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 5)
$cmbAdaptador.DropDownStyle = "DropDownList"
try {
    Get-Adaptadores | ForEach-Object { $cmbAdaptador.Items.Add($_) | Out-Null }
    if ($cmbAdaptador.Items.Count -gt 0) { $cmbAdaptador.SelectedIndex = 0 }
} catch {}
$tablaDns.Controls.Add($cmbAdaptador, 1, 0)

$lblDnsInfo = New-Object System.Windows.Forms.Label
$lblDnsInfo.Text = "Se aplicaran: " + ($ServidoresDns -join "  ->  ")
$lblDnsInfo.ForeColor = $colorTextoSuave
$lblDnsInfo.AutoSize = $true
$lblDnsInfo.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 10)
$tablaDns.SetColumnSpan($lblDnsInfo, 2)
$tablaDns.Controls.Add($lblDnsInfo, 0, 1)

$panelBotonesDns = New-Object System.Windows.Forms.TableLayoutPanel
$panelBotonesDns.Dock = "Fill"
$panelBotonesDns.ColumnCount = 2
$panelBotonesDns.RowCount = 1
$panelBotonesDns.BackColor = $colorTarjeta
[void]$panelBotonesDns.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$panelBotonesDns.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$tablaDns.SetColumnSpan($panelBotonesDns, 2)
$tablaDns.Controls.Add($panelBotonesDns, 0, 2)

$btnAplicarDns = New-Object System.Windows.Forms.Button
$btnAplicarDns.Text = "Añadir DNS"
$btnAplicarDns.Font = $fontBoton
$btnAplicarDns.FlatStyle = "Flat"
$btnAplicarDns.FlatAppearance.BorderSize = 0
$btnAplicarDns.BackColor = $colorAccento
$btnAplicarDns.ForeColor = [System.Drawing.Color]::White
$btnAplicarDns.Dock = "Fill"
$btnAplicarDns.Height = 38
$btnAplicarDns.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
$btnAplicarDns.UseVisualStyleBackColor = $false
$panelBotonesDns.Controls.Add($btnAplicarDns, 0, 0)

$btnRestaurarDns = New-Object System.Windows.Forms.Button
$btnRestaurarDns.Text = "Restaurar DNS"
$btnRestaurarDns.Font = $fontBoton
$btnRestaurarDns.FlatStyle = "Flat"
$btnRestaurarDns.FlatAppearance.BorderSize = 1
$btnRestaurarDns.FlatAppearance.BorderColor = $colorAccento
$btnRestaurarDns.BackColor = [System.Drawing.Color]::White
$btnRestaurarDns.ForeColor = $colorAccento
$btnRestaurarDns.Dock = "Fill"
$btnRestaurarDns.Height = 38
$btnRestaurarDns.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
$btnRestaurarDns.UseVisualStyleBackColor = $false
$panelBotonesDns.Controls.Add($btnRestaurarDns, 1, 0)

$grupoDns.Controls.Add($tablaDns)
$root.Controls.Add($grupoDns, 0, 2)

# --------------------- Tarjeta Registro de actividad ---------------------
$grupoLog = New-Tarjeta -Titulo "Registro de actividad"
$grupoLog.Margin = New-Object System.Windows.Forms.Padding(0)

$dgvLog = New-Object System.Windows.Forms.DataGridView
$dgvLog.Dock = "Fill"
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
$dgvLog.GridColor = [System.Drawing.Color]::FromArgb(235, 236, 238)
$dgvLog.RowTemplate.Height = 28
$dgvLog.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(235, 244, 253)
$dgvLog.DefaultCellStyle.SelectionForeColor = $colorTexto
$dgvLog.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$dgvLog.EnableHeadersVisualStyles = $false
$dgvLog.ScrollBars = "Vertical"
$dgvLog.AutoSizeColumnsMode = "Fill"

$colHora = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colHora.Name = "Hora"
$colHora.FillWeight = 15
$colHora.SortMode = "NotSortable"
$dgvLog.Columns.Add($colHora) | Out-Null

$colEvento = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colEvento.Name = "Evento"
$colEvento.FillWeight = 60
$colEvento.SortMode = "NotSortable"
$dgvLog.Columns.Add($colEvento) | Out-Null

$colEstado = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colEstado.Name = "Estado"
$colEstado.FillWeight = 25
$colEstado.SortMode = "NotSortable"
$colEstado.DefaultCellStyle.Alignment = "MiddleRight"
$colEstado.DefaultCellStyle.Font = $fontLogEstado
$dgvLog.Columns.Add($colEstado) | Out-Null

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

$grupoLog.Controls.Add($dgvLog)
$root.Controls.Add($grupoLog, 0, 3)

function Write-Log {
    param([string]$Evento, [string]$Estado)
    $marca = Get-Date -Format "HH:mm:ss"
    $dgvLog.Rows.Add($marca, $Evento, $Estado) | Out-Null
    $dgvLog.FirstDisplayedScrollingRowIndex = $dgvLog.Rows.Count - 1
}

# --------------------- Eventos ---------------------
$btnDetectarGw.Add_Click({
    $gwDetectada = Get-GatewayPredeterminada
    if ($gwDetectada) {
        $txtGw.Text = $gwDetectada
    } else {
        [System.Windows.Forms.MessageBox]::Show("No se pudo detectar la Gateway automaticamente.", "FARMASOFT", "OK", "Warning")
    }
})

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
