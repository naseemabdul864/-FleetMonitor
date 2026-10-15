$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python Launcher (py) was not found. Install Python 3.10+ first."
}

Write-Host "Starting FleetMonitor dashboard at http://localhost:8501"
& py -3 -m streamlit run app\dashboard.py
