#Requires -Version 5.1
<#
.SYNOPSIS
    Craftplan self-hosting quick-start for Windows 11 / PowerShell.

.DESCRIPTION
    Downloads docker-compose.yml and .env.example, generates all required
    secrets using .NET cryptography, writes them into .env, and starts
    Craftplan with `docker compose up -d`.

.EXAMPLE
    .\setup.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BaseUrl = 'https://raw.githubusercontent.com/puemos/craftplan/main'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "    WARNING: $Message" -ForegroundColor Yellow
}

function New-RandomBase64([int]$Bytes) {
    $data = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes($Bytes)
    return [Convert]::ToBase64String($data)
}

function Set-EnvValue([string]$Key, [string]$Value, [string]$FilePath) {
    $escaped = [regex]::Escape($Value)
    $content = Get-Content $FilePath -Raw
    # Replace "KEY=" (empty) or "KEY=existing" with the new value
    if ($content -match "(?m)^$Key=") {
        $content = $content -replace "(?m)^$Key=.*", "$Key=$Value"
    } else {
        $content = $content.TrimEnd() + "`n$Key=$Value`n"
    }
    # Write with LF line endings to avoid issues inside Linux containers
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Resolve-Path $FilePath).Path, ($content -replace "`r`n", "`n"), $utf8NoBom)
}

# ---------------------------------------------------------------------------
# Preflight: check Docker is running
# ---------------------------------------------------------------------------

Write-Step 'Checking Docker...'

try {
    $null = docker info 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Success 'Docker is running.'
} catch {
    Write-Host "`n  ERROR: Docker is not running or not installed." -ForegroundColor Red
    Write-Host '  Install Docker Desktop from https://www.docker.com/products/docker-desktop/'
    Write-Host '  and make sure it is started with the WSL2 backend enabled.'
    exit 1
}

# ---------------------------------------------------------------------------
# Download compose file and env template (skip if already present)
# ---------------------------------------------------------------------------

Write-Step 'Downloading docker-compose.yml...'
if (Test-Path 'docker-compose.yml') {
    Write-Warn 'docker-compose.yml already exists, skipping download.'
} else {
    Invoke-WebRequest -Uri "$BaseUrl/docker-compose.yml" -OutFile 'docker-compose.yml' -UseBasicParsing
    Write-Success 'Downloaded docker-compose.yml'
}

Write-Step 'Downloading .env.example...'
if (Test-Path '.env.example') {
    Write-Warn '.env.example already exists, skipping download.'
} else {
    Invoke-WebRequest -Uri "$BaseUrl/.env.example" -OutFile '.env.example' -UseBasicParsing
    Write-Success 'Downloaded .env.example'
}

# ---------------------------------------------------------------------------
# Create .env from template (skip if already present)
# ---------------------------------------------------------------------------

Write-Step 'Creating .env...'
if (Test-Path '.env') {
    Write-Warn '.env already exists. Secrets will be written into the existing file.'
} else {
    Copy-Item '.env.example' '.env'
    Write-Success 'Created .env from .env.example'
}

# ---------------------------------------------------------------------------
# Generate secrets
# ---------------------------------------------------------------------------

Write-Step 'Generating secrets...'

$secretKeyBase      = New-RandomBase64 48
$tokenSigningSecret = New-RandomBase64 48
$cloakKey           = New-RandomBase64 32
$postgresPassword   = New-RandomBase64 16

Set-EnvValue 'SECRET_KEY_BASE'      $secretKeyBase      '.env'
Set-EnvValue 'TOKEN_SIGNING_SECRET' $tokenSigningSecret '.env'
Set-EnvValue 'CLOAK_KEY'            $cloakKey           '.env'
Set-EnvValue 'POSTGRES_PASSWORD'    $postgresPassword   '.env'

Write-Success 'SECRET_KEY_BASE      generated'
Write-Success 'TOKEN_SIGNING_SECRET generated'
Write-Success 'CLOAK_KEY            generated'
Write-Success 'POSTGRES_PASSWORD    generated'

# ---------------------------------------------------------------------------
# Summary and launch
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '-------------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host ' Craftplan is ready to start!' -ForegroundColor White
Write-Host '-------------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Review .env if you want to customise HOST, PORT, or email settings,'
Write-Host '  then start Craftplan with:'
Write-Host ''
Write-Host '    docker compose up -d' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Once running, open http://localhost:4000 in your browser.'
Write-Host '  The first account you register becomes an admin.'
Write-Host ''

$answer = Read-Host 'Start Craftplan now? [Y/n]'
if ($answer -eq '' -or $answer -match '^[Yy]') {
    Write-Step 'Starting Craftplan...'
    docker compose up -d
    if ($LASTEXITCODE -eq 0) {
        Write-Host ''
        Write-Success 'Craftplan is running at http://localhost:4000'
    } else {
        Write-Host "`n  ERROR: docker compose up failed. Check the output above." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host '  Run `docker compose up -d` when you are ready.'
}
