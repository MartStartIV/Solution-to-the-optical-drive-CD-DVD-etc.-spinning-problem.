# --- CONFIGURACIÓN INICIAL 2026 (VERSIÓN v1.101 - PPSSPP SPECIAL UPDATE) ---
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   MONITOR DE UNIDAD ÓPTICA v1.101             " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# Selección de Letra de Unidad
$unidadesDisponibles = @("E", "F", "G", "Z")
Write-Host "Unidades detectables: $($unidadesDisponibles -join ', ')" -ForegroundColor Yellow
$letraElegida = Read-Host "Elija la letra de la unidad (Presione Enter para cargar unidad E)"
if ([string]::IsNullOrWhiteSpace($letraElegida)) { $letraElegida = "E" }
$driveLetter = "$($letraElegida.ToUpper()):"
$path = "\\.\$driveLetter"

if (-not (Test-Path $driveLetter)) {
    Write-Host "[!] Error: La unidad $driveLetter no existe." -ForegroundColor Red
    pause
    return
}

$opcion = Read-Host "¿Activar MODO ALTO RENDIMIENTO (Turbo) para Emuladores? (S/N)"
$modoTurbo = ($opcion -eq "S" -or $opcion -eq "s")

# --- VARIABLES DE ESTADO Y AJUSTE DINÁMICO ---
$stats = @{ Exitosos = 0; Saltados = 0; ExitososTurbo = 0; SaltadosTurbo = 0 }
$inicioGlobal = [System.Diagnostics.Stopwatch]::StartNew()
$relojEmulador = New-Object System.Diagnostics.Stopwatch
$buffer = New-Object byte[] 1

# Parámetros de detección de Baja Latencia y Estabilidad
$conteoBajaLatencia = 0
$conteoEstabilidadNormal = 0
$modoBajaLatenciaActivo = $false
$limiteInferior = 0.48
$limiteSuperior = 2.15

Write-Host "`nIniciando monitoreo especializado en $driveLetter..." -ForegroundColor Green

while($true) {
    try {
        # SE AGREGA PPSSPP A LA LISTA DE PROCESOS
        $emuladorActivo = Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue
        
        if ($emuladorActivo) {
            if (-not $relojEmulador.IsRunning) { $relojEmulador.Start() }
        } else {
            if ($relojEmulador.IsRunning) { $relojEmulador.Stop() }
        }

        $tiempo = Measure-Command {
            $streamSonda = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $streamSonda.Close()
            $streamSonda.Dispose()
        }
        $ms = $tiempo.TotalMilliseconds
        
        $ejecutarPulso = $false
        $esTurboActual = ($modoTurbo -and $emuladorActivo)
        $motivoSalto = "Fuera de Rango"

        # --- LÓGICA DE PRECISIÓN PARA DETECCIÓN DE HARDWARE ---
        if (-not $modoBajaLatenciaActivo) {
            if ($ms -lt 0.601 -and $ms -gt 0.100) {
                $conteoBajaLatencia++
                $conteoEstabilidadNormal = 0 
                if ($conteoBajaLatencia -ge 6) {
                    $modoBajaLatenciaActivo = $true
                    $limiteInferior = 0.380
                    $limiteSuperior = 1.18
                    Write-Host "`n[!] MODO BAJA LATENCIA ACTIVADO AUTOMÁTICAMENTE" -ForegroundColor Magenta
                }
            } 
            elseif ($ms -ge 0.601) {
                $conteoEstabilidadNormal++
                if ($conteoEstabilidadNormal -ge 8) {
                    $conteoBajaLatencia = 0
                    $conteoEstabilidadNormal = 0
                }
            }
        }

        # --- LÓGICA DE PULSO ADAPTATIVA (MEJORA PPSSPP) ---
        # Definimos límites temporales para el cálculo actual
        $limiteInfActual = $limiteInferior
        $limiteSupActual = $limiteSuperior

        # Si el emulador es PPSSPP, aplicamos el rango especial solicitado
        if ($emuladorActivo -and ($emuladorActivo.Name -like "*PPSSPP*")) {
            $limiteInfActual = 0.15
            $limiteSupActual = 25.98
        }

        if ($emuladorActivo) {
            if ($ms -ge $limiteInfActual -and $ms -le $limiteSupActual) {
                $accion = "MANTENIMIENTO JUEGO ($($emuladorActivo.Name))"
                $ejecutarPulso = $true
            } else {
                $motivoSalto = if ($ms -lt $limiteInfActual) { "LECTURA ACTIVA" } else { "LATENCIA ALTA" }
            }
        }
        elseif ($ms -ge $limiteInferior -and $ms -le ($limiteSuperior - 0.049)) {
            $accion = "PULSO REPOSO ESTÁNDAR"
            $ejecutarPulso = $true
        }

        if ($ejecutarPulso) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $stream = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $null = $stream.Read($buffer, 0, 1)
            $stream.Close()
            $stream.Dispose()
            
            if($esTurboActual) { $stats.ExitososTurbo++ } else { $stats.Exitosos++ }
            Write-Host ("`n{0} - [{1}] - Latencia: {2:N3}ms" -f (Get-Date -Format 'HH:mm:ss'), $accion, $ms) -ForegroundColor Green
        } 
        else {
            if($esTurboActual) { $stats.SaltadosTurbo++ } else { $stats.Saltados++ }
            Write-Host ("`n{0} - [SALTADO] - {1} ({2:N3}ms)" -f (Get-Date -Format 'HH:mm:ss'), $motivoSalto, $ms) -ForegroundColor Cyan
        }
    } 
    catch {
        Write-Host "`n$(Get-Date -Format 'HH:mm:ss') - [!] Unidad ocupada (Lectura de datos)." -ForegroundColor Yellow
    }

    # PANEL DE ESTADÍSTICAS
    $colorPanel = if($modoBajaLatenciaActivo){ "Magenta" } else { "White" }
    Write-Host "`n[ SESIÓN GLOBAL: $($inicioGlobal.Elapsed.ToString('hh\:mm\:ss')) | OK: $($stats.Exitosos) | SALTOS: $($stats.Saltados) ]" -ForegroundColor $colorPanel
    
    if ($relojEmulador.ElapsedMilliseconds -gt 0) {
        $colorSesion = if ($emuladorActivo) { "Green" } else { "Gray" }
        $estadoJuego = if ($emuladorActivo) { "EJECUTANDO" } else { "EN PAUSA/CERRADO" }
        Write-Host "[ SESIÓN JUEGO ($estadoJuego): $($relojEmulador.Elapsed.ToString('hh\:mm\:ss')) ]" -ForegroundColor $colorSesion
        if($modoTurbo) {
            Write-Host "[ MODO TURBO ACTIVO | OK: $($stats.ExitososTurbo) | SALTOS: $($stats.SaltadosTurbo) ]" -ForegroundColor Red
        }
    }

    # Gestión de tiempos de espera
    $segundosEspera = if ($emuladorActivo) { if ($modoTurbo) { 3 } else { 22 } } else { 23 }
    for ($i = $segundosEspera; $i -gt 0; $i--) {
        $statusExtra = if($modoBajaLatenciaActivo){ " (LOW-LAT)" } else { "" }
        $textoEstado = if($esTurboActual){ "TURBO" } else { "ESPERA$statusExtra" }
        $msg = "`r{0}: {1} seg. restantes...      " -f $textoEstado, $i
        Write-Host -NoNewline $msg
        Start-Sleep -Seconds 1
    }
    Write-Host "" 
}
