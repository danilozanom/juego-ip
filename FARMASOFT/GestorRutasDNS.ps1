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
# Paleta y tipografia
# ==========================================================
$fontBase    = New-Object System.Drawing.Font("Segoe UI", 10)
$fontTitulo  = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$fontSub     = New-Object System.Drawing.Font("Segoe UI", 10)
$fontSeccion = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fontBoton   = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$fontLog     = New-Object System.Drawing.Font("Segoe UI", 9.5)
$fontLogEstado = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

# Paleta indigo/verde-azulado, mas moderna que la anterior
$colorFondo      = [System.Drawing.Color]::FromArgb(241, 243, 247)
$colorTarjeta    = [System.Drawing.Color]::White
$colorBorde      = [System.Drawing.Color]::FromArgb(225, 228, 235)
$colorAccento    = [System.Drawing.Color]::FromArgb(79, 70, 229)
$colorAccentoOsc = [System.Drawing.Color]::FromArgb(62, 55, 190)
$colorTexto      = [System.Drawing.Color]::FromArgb(30, 33, 42)
$colorTextoSuave = [System.Drawing.Color]::FromArgb(107, 114, 128)
$colorOk         = [System.Drawing.Color]::FromArgb(22, 163, 74)
$colorEliminado  = [System.Drawing.Color]::FromArgb(217, 119, 6)
$colorError      = [System.Drawing.Color]::FromArgb(220, 38, 38)
$colorAviso      = [System.Drawing.Color]::FromArgb(156, 163, 175)

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

# Ayuda para crear una "tarjeta" con borde de 1px de color (panel dentro de panel)
function New-Tarjeta {
    param([int]$X, [int]$Y, [int]$Ancho, [int]$Alto)
    $exterior = New-Object System.Windows.Forms.Panel
    $exterior.Location = New-Object System.Drawing.Point($X, $Y)
    $exterior.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $exterior.BackColor = $colorBorde
    $form.Controls.Add($exterior)

    $interior = New-Object System.Windows.Forms.Panel
    $interior.Location = New-Object System.Drawing.Point(1, 1)
    $interior.Size = New-Object System.Drawing.Size(($Ancho - 2), ($Alto - 2))
    $interior.BackColor = $colorTarjeta
    $exterior.Controls.Add($interior)

    return @{ Exterior = $exterior; Interior = $interior }
}

# --------------------- Cabecera ---------------------
$lblTitulo = New-Object System.Windows.Forms.Label
$lblTitulo.Text = "Farmasoft"
$lblTitulo.Font = $fontTitulo
$lblTitulo.ForeColor = $colorAccento
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
$lblSeccionRutas.ForeColor = $colorTexto
$lblSeccionRutas.AutoSize = $true
$lblSeccionRutas.Location = New-Object System.Drawing.Point(28, 96)
$form.Controls.Add($lblSeccionRutas)

$tarjetaRutas = New-Tarjeta -X 28 -Y 126 -Ancho 490 -Alto 150
$interiorRutas = $tarjetaRutas.Interior

$lblGw = New-Object System.Windows.Forms.Label
$lblGw.Text = "Gateway"
$lblGw.ForeColor = $colorTexto
$lblGw.AutoSize = $true
$lblGw.Location = New-Object System.Drawing.Point(18, 22)
$interiorRutas.Controls.Add($lblGw)

$txtGw = New-Object System.Windows.Forms.TextBox
$txtGw.Font = $fontBase
$txtGw.Location = New-Object System.Drawing.Point(100, 18)
$txtGw.Size = New-Object System.Drawing.Size(230, 28)
$interiorRutas.Controls.Add($txtGw)

$btnDetectarGw = New-Object System.Windows.Forms.Button
$btnDetectarGw.Text = "Detectar"
$btnDetectarGw.Font = $fontBoton
$btnDetectarGw.FlatStyle = "Flat"
$btnDetectarGw.FlatAppearance.BorderSize = 1
$btnDetectarGw.FlatAppearance.BorderColor = $colorAccento
$btnDetectarGw.BackColor = [System.Drawing.Color]::White
$btnDetectarGw.ForeColor = $colorAccento
$btnDetectarGw.Location = New-Object System.Drawing.Point(340, 17)
$btnDetectarGw.Size = New-Object System.Drawing.Size(110, 30)
$btnDetectarGw.UseVisualStyleBackColor = $false
$interiorRutas.Controls.Add($btnDetectarGw)

$anchoBotonRuta = 149
$btnAgregarRutas = New-Object System.Windows.Forms.Button
$btnAgregarRutas.Text = "Añadir"
$btnAgregarRutas.Font = $fontBoton
$btnAgregarRutas.FlatStyle = "Flat"
$btnAgregarRutas.FlatAppearance.BorderSize = 0
$btnAgregarRutas.BackColor = $colorAccento
$btnAgregarRutas.ForeColor = [System.Drawing.Color]::White
$btnAgregarRutas.Location = New-Object System.Drawing.Point(18, 70)
$btnAgregarRutas.Size = New-Object System.Drawing.Size($anchoBotonRuta, 40)
$btnAgregarRutas.UseVisualStyleBackColor = $false
$interiorRutas.Controls.Add($btnAgregarRutas)

$btnEliminarRutas = New-Object System.Windows.Forms.Button
$btnEliminarRutas.Text = "Eliminar"
$btnEliminarRutas.Font = $fontBoton
$btnEliminarRutas.FlatStyle = "Flat"
$btnEliminarRutas.FlatAppearance.BorderSize = 1
$btnEliminarRutas.FlatAppearance.BorderColor = $colorAccento
$btnEliminarRutas.BackColor = [System.Drawing.Color]::White
$btnEliminarRutas.ForeColor = $colorAccento
$btnEliminarRutas.Location = New-Object System.Drawing.Point((18 + $anchoBotonRuta + 8), 70)
$btnEliminarRutas.Size = New-Object System.Drawing.Size($anchoBotonRuta, 40)
$btnEliminarRutas.UseVisualStyleBackColor = $false
$interiorRutas.Controls.Add($btnEliminarRutas)

$btnComprobarRutas = New-Object System.Windows.Forms.Button
$btnComprobarRutas.Text = "Comprobar"
$btnComprobarRutas.Font = $fontBoton
$btnComprobarRutas.FlatStyle = "Flat"
$btnComprobarRutas.FlatAppearance.BorderSize = 1
$btnComprobarRutas.FlatAppearance.BorderColor = $colorBorde
$btnComprobarRutas.BackColor = [System.Drawing.Color]::White
$btnComprobarRutas.ForeColor = $colorTextoSuave
$btnComprobarRutas.Location = New-Object System.Drawing.Point((18 + ($anchoBotonRuta + 8) * 2), 70)
$btnComprobarRutas.Size = New-Object System.Drawing.Size($anchoBotonRuta, 40)
$btnComprobarRutas.UseVisualStyleBackColor = $false
$interiorRutas.Controls.Add($btnComprobarRutas)

# --------------------- Tarjeta DNS ---------------------
$lblSeccionDns = New-Object System.Windows.Forms.Label
$lblSeccionDns.Text = "DNS"
$lblSeccionDns.Font = $fontSeccion
$lblSeccionDns.ForeColor = $colorTexto
$lblSeccionDns.AutoSize = $true
$lblSeccionDns.Location = New-Object System.Drawing.Point(28, 292)
$form.Controls.Add($lblSeccionDns)

$tarjetaDns = New-Tarjeta -X 28 -Y 322 -Ancho 490 -Alto 175
$interiorDns = $tarjetaDns.Interior

$lblAdaptador = New-Object System.Windows.Forms.Label
$lblAdaptador.Text = "Adaptador"
$lblAdaptador.ForeColor = $colorTexto
$lblAdaptador.AutoSize = $true
$lblAdaptador.Location = New-Object System.Drawing.Point(18, 22)
$interiorDns.Controls.Add($lblAdaptador)

$cmbAdaptador = New-Object System.Windows.Forms.ComboBox
$cmbAdaptador.Font = $fontBase
$cmbAdaptador.Location = New-Object System.Drawing.Point(100, 18)
$cmbAdaptador.Size = New-Object System.Drawing.Size(350, 28)
$cmbAdaptador.DropDownStyle = "DropDownList"
try {
    Get-Adaptadores | ForEach-Object { $cmbAdaptador.Items.Add($_) | Out-Null }
    if ($cmbAdaptador.Items.Count -gt 0) { $cmbAdaptador.SelectedIndex = 0 }
} catch {}
$interiorDns.Controls.Add($cmbAdaptador)

$lblDnsInfo = New-Object System.Windows.Forms.Label
$lblDnsInfo.Text = "Se aplicaran:`r`n" + ($ServidoresDns -join "   ->   ")
$lblDnsInfo.ForeColor = $colorTextoSuave
$lblDnsInfo.AutoSize = $true
$lblDnsInfo.Location = New-Object System.Drawing.Point(18, 56)
$interiorDns.Controls.Add($lblDnsInfo)

$anchoBotonDns = 227
$btnAplicarDns = New-Object System.Windows.Forms.Button
$btnAplicarDns.Text = "Añadir DNS"
$btnAplicarDns.Font = $fontBoton
$btnAplicarDns.FlatStyle = "Flat"
$btnAplicarDns.FlatAppearance.BorderSize = 0
$btnAplicarDns.BackColor = $colorAccento
$btnAplicarDns.ForeColor = [System.Drawing.Color]::White
$btnAplicarDns.Location = New-Object System.Drawing.Point(18, 118)
$btnAplicarDns.Size = New-Object System.Drawing.Size($anchoBotonDns, 40)
$btnAplicarDns.UseVisualStyleBackColor = $false
$interiorDns.Controls.Add($btnAplicarDns)

$btnRestaurarDns = New-Object System.Windows.Forms.Button
$btnRestaurarDns.Text = "Restaurar DNS"
$btnRestaurarDns.Font = $fontBoton
$btnRestaurarDns.FlatStyle = "Flat"
$btnRestaurarDns.FlatAppearance.BorderSize = 1
$btnRestaurarDns.FlatAppearance.BorderColor = $colorAccento
$btnRestaurarDns.BackColor = [System.Drawing.Color]::White
$btnRestaurarDns.ForeColor = $colorAccento
$btnRestaurarDns.Location = New-Object System.Drawing.Point((18 + $anchoBotonDns + 8), 118)
$btnRestaurarDns.Size = New-Object System.Drawing.Size($anchoBotonDns, 40)
$btnRestaurarDns.UseVisualStyleBackColor = $false
$interiorDns.Controls.Add($btnRestaurarDns)

# --------------------- Tarjeta Registro de actividad ---------------------
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "REGISTRO DE ACTIVIDAD"
$lblLog.Font = $fontSeccion
$lblLog.ForeColor = $colorTexto
$lblLog.AutoSize = $true
$lblLog.Anchor = "Top, Left"
$lblLog.Location = New-Object System.Drawing.Point(28, 512)
$form.Controls.Add($lblLog)

$tarjetaLog = New-Tarjeta -X 28 -Y 542 -Ancho 490 -Alto 150
$exteriorLog = $tarjetaLog.Exterior
$interiorLog = $tarjetaLog.Interior
$exteriorLog.Anchor = "Top, Left, Right, Bottom"

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
$dgvLog.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(238, 237, 253)
$dgvLog.DefaultCellStyle.SelectionForeColor = $colorTexto
$dgvLog.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$dgvLog.EnableHeadersVisualStyles = $false
$dgvLog.ScrollBars = "Vertical"
$dgvLog.AutoSizeColumnsMode = "Fill"
$interiorLog.Controls.Add($dgvLog)

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
