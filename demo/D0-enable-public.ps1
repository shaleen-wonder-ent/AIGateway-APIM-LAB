# Demo 0 - Enable public reachability for a laptop demo.
# Flips enable_private_ip_filter = false and applies Terraform.
# Identity, team, quota, content-safety and managed-identity controls all remain enforced.

$infra  = Join-Path (Split-Path $PSScriptRoot -Parent) "infra"
$tfvars = Join-Path $infra "terraform.tfvars"

Write-Host ""
Write-Host "Setting enable_private_ip_filter = false ..." -ForegroundColor Yellow
$content = Get-Content $tfvars
if ($content -match "enable_private_ip_filter") {
  ($content -replace "enable_private_ip_filter\s*=\s*(true|false)", "enable_private_ip_filter = false") | Set-Content $tfvars
} else {
  Add-Content $tfvars "`nenable_private_ip_filter = false"
}

Write-Host "Applying Terraform ..." -ForegroundColor Yellow
terraform "-chdir=$infra" apply -auto-approve

Write-Host ""
Write-Host "Public reachability is ON for this demo." -ForegroundColor Green
Write-Host "Still enforced: Entra identity, team subscription, quotas, content safety, managed identity." -ForegroundColor DarkGray
Write-Host "Run D7-restore.ps1 (or set the flag back to true) when you are done." -ForegroundColor DarkGray
