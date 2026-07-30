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

Add-Type -Name DwmApi -Namespace WinApi -MemberDefinition '
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
'

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
function Test-IPv4 {
    param([string]$Ip)
    if ($Ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    foreach ($octeto in ($Ip -split '\.')) {
        if ([int]$octeto -gt 255) { return $false }
    }
    return $true
}

function Get-RouteExists {
    param([string]$Destino)
    try {
        $salida = route print | Select-String -SimpleMatch $Destino
        return [bool]$salida
    } catch {
        return $false
    }
}

function Add-RutaEstatica {
    param([string]$Destino, [string]$Gateway)
    try {
        if (Get-RouteExists -Destino $Destino) {
            return "Ya existia"
        }
        $resultado = route -p add $Destino mask $Mascara $Gateway 2>&1
        if ($LASTEXITCODE -ne 0) {
            return "Error: $resultado"
        }
        return "Agregada"
    } catch {
        return "Error: $_"
    }
}

function Remove-RutaEstatica {
    param([string]$Destino)
    try {
        if (-not (Get-RouteExists -Destino $Destino)) {
            return "No existia"
        }
        $resultado = route delete $Destino 2>&1
        if ($LASTEXITCODE -ne 0) {
            return "Error: $resultado"
        }
        return "Eliminada"
    } catch {
        return "Error: $_"
    }
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
# Esquinas redondeadas (estilo Windows 11 / Fluent)
# Se dibujan con GDI+ (Paint), NO recortando con Control.Region:
# recortar con Region deja las esquinas sin pintar y aparecen
# como manchas/brillos negros. Dibujando el borde redondeado
# directamente se evita ese problema por completo.
# ==========================================================
function Get-RoundedPath {
    param([int]$Width, [int]$Height, [int]$Radius)
    $d = $Radius * 2
    if ($d -gt $Width) { $d = $Width }
    if ($d -gt $Height) { $d = $Height }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($Width - $d, 0, $d, $d, 270, 90)
    $path.AddArc($Width - $d, $Height - $d, $d, $d, 0, 90)
    $path.AddArc(0, $Height - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# ==========================================================
# Paleta oscura minimalista (Fluent / Windows 11 dark)
# ==========================================================
$fontBase      = New-Object System.Drawing.Font("Segoe UI", 10)
$fontTitulo    = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$fontSub       = New-Object System.Drawing.Font("Segoe UI", 10)
$fontSeccion   = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fontBoton     = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$fontLog       = New-Object System.Drawing.Font("Segoe UI", 9.5)
$fontLogEstado = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$colorFondo      = [System.Drawing.Color]::FromArgb(24, 24, 27)
$colorTarjeta    = [System.Drawing.Color]::FromArgb(34, 34, 38)
$colorTarjetaAlt = [System.Drawing.Color]::FromArgb(42, 42, 47)
$colorBorde      = [System.Drawing.Color]::FromArgb(54, 54, 60)
$colorAccento    = [System.Drawing.Color]::FromArgb(90, 140, 255)
$colorTexto      = [System.Drawing.Color]::FromArgb(235, 235, 240)
$colorTextoSuave = [System.Drawing.Color]::FromArgb(148, 148, 158)
$colorOk         = [System.Drawing.Color]::FromArgb(98, 189, 128)
$colorEliminado  = [System.Drawing.Color]::FromArgb(224, 168, 92)
$colorError      = [System.Drawing.Color]::FromArgb(226, 108, 108)
$colorAviso      = [System.Drawing.Color]::FromArgb(130, 130, 140)

# ==========================================================
# Formulario principal
# ==========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "FARMASOFT"
$form.Size = New-Object System.Drawing.Size(560, 760)
$form.MinimumSize = New-Object System.Drawing.Size(520, 640)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $true
$form.BackColor = $colorFondo
$form.Font = $fontBase
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96.0, 96.0)

$form.Add_Load({
    try {
        $valorOscuro = 1
        [WinApi.DwmApi]::DwmSetWindowAttribute($form.Handle, 20, [ref]$valorOscuro, 4) | Out-Null
    } catch {}
})

# Tarjeta con esquinas redondeadas: un unico panel que dibuja su propio
# fondo y borde redondeados en el evento Paint (sin usar Control.Region).
function New-Tarjeta {
    param([int]$X, [int]$Y, [int]$Ancho, [int]$Alto, [int]$Radio = 14)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $panel.BackColor = $colorFondo
    $panel.Padding = New-Object System.Windows.Forms.Padding(4)

    $panel.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $ancho = $sender.Width - 1
        $alto = $sender.Height - 1
        if ($ancho -le 0 -or $alto -le 0) { return }
        $path = Get-RoundedPath -Width $ancho -Height $alto -Radius $Radio
        $brush = New-Object System.Drawing.SolidBrush($colorTarjeta)
        $pen = New-Object System.Drawing.Pen($colorBorde, 1)
        $e.Graphics.FillPath($brush, $path)
        $e.Graphics.DrawPath($pen, $path)
        $brush.Dispose()
        $pen.Dispose()
        $path.Dispose()
    })

    $form.Controls.Add($panel)
    return $panel
}

function New-BotonPrimario {
    param([string]$Texto, [int]$X, [int]$Y, [int]$Ancho, [int]$Alto = 40)
    $boton = New-Object System.Windows.Forms.Button
    $boton.Text = $Texto
    $boton.Font = $fontBoton
    $boton.FlatStyle = "Flat"
    $boton.FlatAppearance.BorderSize = 0
    $boton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(110, 156, 255)
    $boton.BackColor = $colorAccento
    $boton.ForeColor = [System.Drawing.Color]::White
    $boton.Location = New-Object System.Drawing.Point($X, $Y)
    $boton.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $boton.UseVisualStyleBackColor = $false
    return $boton
}

function New-BotonSecundario {
    param([string]$Texto, [int]$X, [int]$Y, [int]$Ancho, [int]$Alto = 40)
    $boton = New-Object System.Windows.Forms.Button
    $boton.Text = $Texto
    $boton.Font = $fontBoton
    $boton.FlatStyle = "Flat"
    $boton.FlatAppearance.BorderSize = 1
    $boton.FlatAppearance.BorderColor = $colorBorde
    $boton.FlatAppearance.MouseOverBackColor = $colorTarjetaAlt
    $boton.BackColor = $colorTarjeta
    $boton.ForeColor = $colorTexto
    $boton.Location = New-Object System.Drawing.Point($X, $Y)
    $boton.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $boton.UseVisualStyleBackColor = $false
    return $boton
}

# --------------------- Cabecera ---------------------
$lblTitulo = New-Object System.Windows.Forms.Label
$lblTitulo.Text = "Farmasoft"
$lblTitulo.Font = $fontTitulo
$lblTitulo.ForeColor = $colorTexto
$lblTitulo.AutoSize = $true
$lblTitulo.Location = New-Object System.Drawing.Point(28, 22)
$form.Controls.Add($lblTitulo)

$lblSubtitulo = New-Object System.Windows.Forms.Label
$lblSubtitulo.Text = "Gestor de DNS y Routes"
$lblSubtitulo.Font = $fontSub
$lblSubtitulo.ForeColor = $colorTextoSuave
$lblSubtitulo.AutoSize = $true
$lblSubtitulo.Location = New-Object System.Drawing.Point(30, 58)
$form.Controls.Add($lblSubtitulo)

# --------------------- Tarjeta RUTAS ---------------------
$lblSeccionRutas = New-Object System.Windows.Forms.Label
$lblSeccionRutas.Text = "RUTAS"
$lblSeccionRutas.Font = $fontSeccion
$lblSeccionRutas.ForeColor = $colorTextoSuave
$lblSeccionRutas.AutoSize = $true
$lblSeccionRutas.Location = New-Object System.Drawing.Point(28, 96)
$form.Controls.Add($lblSeccionRutas)

$panelRutas = New-Tarjeta -X 28 -Y 126 -Ancho 490 -Alto 150

$lblGw = New-Object System.Windows.Forms.Label
$lblGw.Text = "Gateway"
$lblGw.ForeColor = $colorTexto
$lblGw.AutoSize = $true
$lblGw.Location = New-Object System.Drawing.Point(18, 22)
$panelRutas.Controls.Add($lblGw)

$txtGw = New-Object System.Windows.Forms.TextBox
$txtGw.Font = $fontBase
$txtGw.BorderStyle = "FixedSingle"
$txtGw.BackColor = $colorTarjetaAlt
$txtGw.ForeColor = $colorTexto
$txtGw.Location = New-Object System.Drawing.Point(100, 18)
$txtGw.Size = New-Object System.Drawing.Size(230, 28)
$panelRutas.Controls.Add($txtGw)

$btnDetectarGw = New-BotonSecundario -Texto "Detectar" -X 340 -Y 17 -Ancho 110 -Alto 30
$panelRutas.Controls.Add($btnDetectarGw)

$anchoBotonRuta = 149
$btnAgregarRutas = New-BotonPrimario -Texto "Añadir" -X 18 -Y 70 -Ancho $anchoBotonRuta
$panelRutas.Controls.Add($btnAgregarRutas)

$btnEliminarRutas = New-BotonSecundario -Texto "Eliminar" -X (18 + $anchoBotonRuta + 8) -Y 70 -Ancho $anchoBotonRuta
$panelRutas.Controls.Add($btnEliminarRutas)

$btnComprobarRutas = New-BotonSecundario -Texto "Comprobar" -X (18 + ($anchoBotonRuta + 8) * 2) -Y 70 -Ancho $anchoBotonRuta
$panelRutas.Controls.Add($btnComprobarRutas)

# --------------------- Tarjeta DNS ---------------------
$lblSeccionDns = New-Object System.Windows.Forms.Label
$lblSeccionDns.Text = "DNS"
$lblSeccionDns.Font = $fontSeccion
$lblSeccionDns.ForeColor = $colorTextoSuave
$lblSeccionDns.AutoSize = $true
$lblSeccionDns.Location = New-Object System.Drawing.Point(28, 292)
$form.Controls.Add($lblSeccionDns)

$panelDns = New-Tarjeta -X 28 -Y 322 -Ancho 490 -Alto 175

$lblAdaptador = New-Object System.Windows.Forms.Label
$lblAdaptador.Text = "Adaptador"
$lblAdaptador.ForeColor = $colorTexto
$lblAdaptador.AutoSize = $true
$lblAdaptador.Location = New-Object System.Drawing.Point(18, 22)
$panelDns.Controls.Add($lblAdaptador)

$cmbAdaptador = New-Object System.Windows.Forms.ComboBox
$cmbAdaptador.Font = $fontBase
$cmbAdaptador.FlatStyle = "Flat"
$cmbAdaptador.BackColor = $colorTarjetaAlt
$cmbAdaptador.ForeColor = $colorTexto
$cmbAdaptador.Location = New-Object System.Drawing.Point(100, 18)
$cmbAdaptador.Size = New-Object System.Drawing.Size(350, 28)
$cmbAdaptador.DropDownStyle = "DropDownList"
try {
    Get-Adaptadores | ForEach-Object { $cmbAdaptador.Items.Add($_) | Out-Null }
    if ($cmbAdaptador.Items.Count -gt 0) { $cmbAdaptador.SelectedIndex = 0 }
} catch {}
$panelDns.Controls.Add($cmbAdaptador)

$lblDnsInfo = New-Object System.Windows.Forms.Label
$lblDnsInfo.Text = "Se aplicaran:`r`n" + ($ServidoresDns -join "   ->   ")
$lblDnsInfo.ForeColor = $colorTextoSuave
$lblDnsInfo.AutoSize = $true
$lblDnsInfo.Location = New-Object System.Drawing.Point(18, 56)
$panelDns.Controls.Add($lblDnsInfo)

$anchoBotonDns = 227
$btnAplicarDns = New-BotonPrimario -Texto "Añadir DNS" -X 18 -Y 118 -Ancho $anchoBotonDns
$panelDns.Controls.Add($btnAplicarDns)

$btnRestaurarDns = New-BotonSecundario -Texto "Restaurar DNS" -X (18 + $anchoBotonDns + 8) -Y 118 -Ancho $anchoBotonDns
$panelDns.Controls.Add($btnRestaurarDns)

# --------------------- Tarjeta Registro de actividad ---------------------
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "REGISTRO DE ACTIVIDAD"
$lblLog.Font = $fontSeccion
$lblLog.ForeColor = $colorTextoSuave
$lblLog.AutoSize = $true
$lblLog.Anchor = "Top, Left"
$lblLog.Location = New-Object System.Drawing.Point(28, 512)
$form.Controls.Add($lblLog)

$panelLog = New-Tarjeta -X 28 -Y 542 -Ancho 490 -Alto 150
$panelLog.Anchor = "Top, Left, Right, Bottom"
$panelLog.Padding = New-Object System.Windows.Forms.Padding(8)

$dgvLog = New-Object System.Windows.Forms.DataGridView
$dgvLog.Dock = "Fill"
$dgvLog.BackgroundColor = $colorTarjeta
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
$dgvLog.GridColor = $colorBorde
$dgvLog.RowTemplate.Height = 28
$dgvLog.DefaultCellStyle.BackColor = $colorTarjeta
$dgvLog.DefaultCellStyle.ForeColor = $colorTexto
$dgvLog.DefaultCellStyle.SelectionBackColor = $colorTarjetaAlt
$dgvLog.DefaultCellStyle.SelectionForeColor = $colorTexto
$dgvLog.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$dgvLog.EnableHeadersVisualStyles = $false
$dgvLog.ScrollBars = "Vertical"
$dgvLog.AutoSizeColumnsMode = "Fill"
$panelLog.Controls.Add($dgvLog)

$colHora = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colHora.Name = "Hora"
$colHora.FillWeight = 15
$colHora.SortMode = "NotSortable"
$colHora.DefaultCellStyle.ForeColor = $colorTextoSuave
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
    } elseif ($valor -match "Agregada|Aplicado|Restaurado|^Existe$") {
        $e.CellStyle.ForeColor = $colorOk
    } elseif ($valor -match "Eliminada") {
        $e.CellStyle.ForeColor = $colorEliminado
    } elseif ($valor -match "Ya existia|No existia|No existe") {
        $e.CellStyle.ForeColor = $colorAviso
    } else {
        $e.CellStyle.ForeColor = $colorTexto
    }
})

function Write-Log {
    param([string]$Evento, [string]$Estado)
    $marca = Get-Date -Format "HH:mm:ss"
    $dgvLog.Rows.Add($marca, $Evento, $Estado) | Out-Null
    $dgvLog.FirstDisplayedScrollingRowIndex = $dgvLog.Rows.Count - 1
}

# --------------------- Eventos ---------------------
$btnDetectarGw.Add_Click({
    try {
        $gwDetectada = Get-GatewayPredeterminada
        if ($gwDetectada) {
            $txtGw.Text = $gwDetectada
        } else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo detectar la Gateway automaticamente.", "FARMASOFT", "OK", "Warning")
        }
    } catch {
        Write-Log -Evento "Detectar Gateway: $_" -Estado "Error"
    }
})

$btnAgregarRutas.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($txtGw.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Introduce una Gateway valida.", "FARMASOFT", "OK", "Warning")
            return
        }
        if (-not (Test-IPv4 $txtGw.Text)) {
            [System.Windows.Forms.MessageBox]::Show("La Gateway introducida no es una IPv4 valida.", "FARMASOFT", "OK", "Warning")
            return
        }
        foreach ($ruta in $Rutas) {
            $estado = Add-RutaEstatica -Destino $ruta -Gateway $txtGw.Text
            Write-Log -Evento "Ruta $ruta" -Estado $estado
        }
    } catch {
        Write-Log -Evento "Añadir rutas: $_" -Estado "Error"
    }
})

$btnEliminarRutas.Add_Click({
    try {
        foreach ($ruta in $Rutas) {
            $estado = Remove-RutaEstatica -Destino $ruta
            Write-Log -Evento "Ruta $ruta" -Estado $estado
        }
    } catch {
        Write-Log -Evento "Eliminar rutas: $_" -Estado "Error"
    }
})

$btnComprobarRutas.Add_Click({
    try {
        foreach ($ruta in $Rutas) {
            if (Get-RouteExists -Destino $ruta) {
                Write-Log -Evento "Ruta $ruta" -Estado "Existe"
            } else {
                Write-Log -Evento "Ruta $ruta" -Estado "No existe"
            }
        }
    } catch {
        Write-Log -Evento "Comprobar rutas: $_" -Estado "Error"
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
