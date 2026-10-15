$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Import-LocalEnv {
    $envPath = Join-Path $Root ".env"
    if (-not (Test-Path -LiteralPath $envPath)) {
        Write-Host "No .env found; using documented local defaults where possible."
        return
    }

    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
            continue
        }
        $pair = $line -split "=", 2
        if ($pair.Count -eq 2) {
            $key = $pair[0].Trim()
            $value = $pair[1].Trim().Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
    Write-Host "Loaded local .env configuration without displaying values."
}

function Get-Setting([string]$Name, [string]$Default) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

Import-LocalEnv

$pgHost = Get-Setting "POSTGRES_HOST" "localhost"
$pgPort = Get-Setting "POSTGRES_PORT" "5432"
$pgDb = Get-Setting "POSTGRES_DB" "fleetmonitor"
$pgUser = Get-Setting "POSTGRES_USER" "fleetmonitor"
$mongoUri = Get-Setting "MONGO_URI" "mongodb://localhost:27017"

$postgresPassword = [Environment]::GetEnvironmentVariable("POSTGRES_PASSWORD")
if (-not [string]::IsNullOrWhiteSpace($postgresPassword)) {
    [Environment]::SetEnvironmentVariable("PGPASSWORD", $postgresPassword, "Process")
}

$psql = Get-Command psql -ErrorAction SilentlyContinue
if ($psql) {
    Write-Host "Running PostgreSQL Stage 1 schema..."
    & $psql.Source -h $pgHost -p $pgPort -U $pgUser -d $pgDb -v ON_ERROR_STOP=1 -f (Join-Path $Root "db\postgres\01_schema.sql")
    Write-Host "Running PostgreSQL Stage 1 seed data..."
    & $psql.Source -h $pgHost -p $pgPort -U $pgUser -d $pgDb -v ON_ERROR_STOP=1 -f (Join-Path $Root "db\postgres\02_seed.sql")
    Write-Host "PostgreSQL Stage 1 completed."
} else {
    Write-Warning "psql was not found. Install PostgreSQL client tools, then rerun this script."
}

$mongosh = Get-Command mongosh -ErrorAction SilentlyContinue
if ($mongosh) {
    Write-Host "Running MongoDB Stage 3 collections and indexes..."
    & $mongosh.Source $mongoUri --quiet --file (Join-Path $Root "db\mongo\01_setup.js")
    Write-Host "Loading MongoDB sample GPS and maintenance documents..."
    & $mongosh.Source $mongoUri --quiet --file (Join-Path $Root "db\mongo\02_sample_documents.js")
    Write-Host "MongoDB Stage 3 completed."
} else {
    Write-Warning "mongosh was not found. Install MongoDB Shell, then rerun this script."
}

Write-Host "Setup script finished. Run scripts\run_dashboard.ps1 to start the dashboard."
