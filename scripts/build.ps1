[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutputDirectory = "dist",
    [switch]$SkipUPX,
    [switch]$RunTests
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    throw $Message
}

# The script lives in scripts/, but all operations run from the project root.
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Fail "No se encontró Go en PATH. Instala Go y vuelve a ejecutar el script."
}

if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $TargetOS = "windows"
    $BinaryName = "mcp-server-email.exe"
} elseif ($IsLinux) {
    $TargetOS = "linux"
    $BinaryName = "mcp-server-email"
} elseif ($IsMacOS) {
    $TargetOS = "darwin"
    $BinaryName = "mcp-server-email"
} else {
    Fail "Sistema operativo no soportado."
}

$TargetArch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    "X64"   { "amd64"; break }
    "Arm64" { "arm64"; break }
    "X86"   { "386"; break }
    default { Fail "Arquitectura no soportada: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    try { $Version = (git describe --tags --always --dirty 2>$null).Trim() } catch { $Version = "dev" }
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = "dev" }
}

$OutputPath = Join-Path $ProjectRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$BinaryPath = Join-Path $OutputPath $BinaryName

if ($RunTests) {
    Write-Host "Ejecutando pruebas..." -ForegroundColor Cyan
    & go test ./...
    if ($LASTEXITCODE -ne 0) { Fail "Las pruebas fallaron." }
}

$LdFlags = "-s -w -X main.version=$Version"
$BuildArgs = @(
    "build", "-trimpath", "-buildvcs=false", "-ldflags=$LdFlags",
    "-o", $BinaryPath, ".\cmd\mcp-server-email"
)

Write-Host "Compilando $TargetOS/$TargetArch -> $BinaryPath" -ForegroundColor Cyan
$env:CGO_ENABLED = "0"
$env:GOOS = $TargetOS
$env:GOARCH = $TargetArch
& go @BuildArgs
if ($LASTEXITCODE -ne 0) { Fail "La compilación falló." }

if (-not $SkipUPX) {
    $UpxCommand = Get-Command upx -ErrorAction SilentlyContinue
    if ($UpxCommand) {
        Write-Host "Comprimiendo con UPX ($($UpxCommand.Source))..." -ForegroundColor Cyan
        & $UpxCommand.Source --best --lzma $BinaryPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "UPX no pudo comprimir el binario; se conserva sin comprimir."
        }
    } else {
        Write-Warning "UPX no está disponible en PATH; se omite la compresión."
    }
}

Write-Host "Build completado: $BinaryPath" -ForegroundColor Green
