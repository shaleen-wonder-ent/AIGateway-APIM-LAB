# Demo 8 - Restore private-only posture.
# Flips enable_private_ip_filter = true and applies. The gateway then rejects public
# callers with 403 private_only; identity, team, quota, and safety controls still apply.
# Run D0-enable-public.ps1 to open it back up for a laptop demo.

$infra  = Join-Path (Split-Path $PSScriptRoot -Parent) "infra"
$tfvars = Join-Path $infra "terraform.tfvars"

Write-Host ""
Write-Host "Setting enable_private_ip_filter = true ..." -ForegroundColor Yellow
$content = Get-Content $tfvars
if ($content -match "enable_private_ip_filter") {
  ($content -replace "enable_private_ip_filter\s*=\s*(true|false)", "enable_private_ip_filter = true") | Set-Content $tfvars
} else {
  Add-Content $tfvars "`nenable_private_ip_filter = true"
}

Write-Host "Applying Terraform ..." -ForegroundColor Yellow
terraform "-chdir=$infra" apply -auto-approve

Write-Host ""
Write-Host "Private-only posture restored." -ForegroundColor Green
Write-Host "Public callers now get 403 private_only. In production, reach the gateway over a" -ForegroundColor DarkGray
Write-Host "VNet or VPN. Run D0-enable-public.ps1 to open it up for another laptop demo." -ForegroundColor DarkGray
