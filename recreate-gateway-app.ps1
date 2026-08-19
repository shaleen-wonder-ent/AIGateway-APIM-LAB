# recreate-gateway-app.ps1
# ---------------------------------------------------------------------------------------
# SAFETY-NET (run ONLY if the "Enterprise AI Gateway" app registration was deleted, e.g.
# by the MISE/SFI compliance sweep, and D1 now fails with 401 / consent errors).
#
# What it does, unattended:
#   1. Creates a NEW "Enterprise AI Gateway" app registration (single tenant).
#   2. Reconfigures it exactly like the original: api://<appId> identifier URI,
#      an "access_as_user" delegated scope, Azure CLI pre-authorization,
#      SecurityGroup claims, and access-token v2.
#   3. Creates the service principal.
#   4. Rewrites the hard-coded App ID across the demo scripts, terraform.tfvars, and docs.
#   5. Runs `terraform apply` so APIM's named values pick up the new App ID / audience.
#
# After it finishes, do the two printed manual steps (interactive az login + run D1).
#
# Nothing else in the environment (APIM, Foundry, groups, telemetry) is affected.
# ---------------------------------------------------------------------------------------

param([switch]$Yes)

$ErrorActionPreference = "Stop"

# --- Constants that do NOT change ---
$displayName = "Enterprise AI Gateway"
$tenant      = "16b3c013-d300-468d-ac64-7eda0820b6d3"
$cliAppId    = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"   # Azure CLI public client (the caller)
$oldAppId    = "246e2a64-1f33-4479-b7b6-3b2cb348ab1f"   # the deleted app's ID (to replace)
$repo        = $PSScriptRoot
$infra       = Join-Path $repo "infra"
$graph       = "https://graph.microsoft.com/v1.0"

if (-not $Yes) {
  Write-Host "This creates a NEW app registration and rewrites the App ID across the repo." -ForegroundColor Yellow
  $ans = Read-Host "Proceed? (y/N)"
  if ($ans -ne "y") { Write-Host "Aborted."; return }
}

Write-Host "=== Recreating '$displayName' ===" -ForegroundColor Cyan

# 1) Create the app registration
$app = az ad app create --display-name $displayName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
$newAppId = $app.appId
$objId    = $app.id
Write-Host "Created app. New AppId = $newAppId" -ForegroundColor Green

# Graph auth
$graphToken = az account get-access-token --resource "https://graph.microsoft.com/" --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $graphToken"; "Content-Type" = "application/json" }

# 2) PATCH 1 - identifier URI + scope + token v2 + group claims (NOT pre-auth yet)
$scopeId = [guid]::NewGuid().ToString()
$patch1 = @{
  identifierUris        = @("api://$newAppId")
  groupMembershipClaims = "SecurityGroup"
  api = @{
    requestedAccessTokenVersion = 2
    oauth2PermissionScopes = @(@{
      id                      = $scopeId
      value                   = "access_as_user"
      type                    = "User"
      isEnabled               = $true
      adminConsentDisplayName = "Access the Enterprise AI Gateway"
      adminConsentDescription = "Allow the application to access the Enterprise AI Gateway on behalf of the signed-in user."
      userConsentDisplayName  = "Access the Enterprise AI Gateway"
      userConsentDescription  = "Allow this application to access the Enterprise AI Gateway on your behalf."
    })
  }
} | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method Patch -Uri "$graph/applications/$objId" -Headers $headers -Body $patch1 | Out-Null
Write-Host "Set identifier URI, access_as_user scope, token v2, and group claims." -ForegroundColor Green

# 3) PATCH 2 - pre-authorize Azure CLI for the scope (must be a separate call)
$patch2 = @{ api = @{ preAuthorizedApplications = @(@{ appId = $cliAppId; delegatedPermissionIds = @($scopeId) }) } } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method Patch -Uri "$graph/applications/$objId" -Headers $headers -Body $patch2 | Out-Null
Write-Host "Pre-authorized Azure CLI for access_as_user." -ForegroundColor Green

# 4) Create the service principal (harmless if it already exists)
try { az ad sp create --id $newAppId | Out-Null; Write-Host "Created service principal." -ForegroundColor Green }
catch { Write-Host "Service principal step skipped ($_)." -ForegroundColor DarkGray }

# 5) Rewrite the hard-coded App ID across demo scripts, tfvars, and docs
$targets = @()
$targets += Get-ChildItem (Join-Path $repo "demo") -Filter *.ps1 -ErrorAction SilentlyContinue
$tfvars = Join-Path $infra "terraform.tfvars"
if (Test-Path $tfvars) { $targets += Get-Item $tfvars }
$targets += Get-ChildItem $repo -Filter *.md -ErrorAction SilentlyContinue
foreach ($f in $targets) {
  $c = Get-Content $f.FullName -Raw
  if ($c -match $oldAppId) {
    ($c -replace $oldAppId, $newAppId) | Set-Content $f.FullName -NoNewline
    Write-Host "  updated $($f.Name)" -ForegroundColor DarkGray
  }
}
Write-Host "Rewrote App ID $oldAppId -> $newAppId across the repo." -ForegroundColor Green

# 6) Apply Terraform so APIM's aigw-audience / aigw-client-app-id named values update
Write-Host "Applying Terraform (updates APIM named values)..." -ForegroundColor Yellow
terraform "-chdir=$infra" apply -auto-approve | Out-Null
Write-Host "Terraform applied." -ForegroundColor Green

Write-Host ""
Write-Host "=== Almost done - two interactive steps left ===" -ForegroundColor Cyan
Write-Host "  1) az login --tenant $tenant --scope `"api://$newAppId/access_as_user`"" -ForegroundColor Yellow
Write-Host "  2) cd demo ; .\D1-keyless-access.ps1     (verify a real GPT-4o answer)" -ForegroundColor Yellow
Write-Host ""
Write-Host "New AppId: $newAppId" -ForegroundColor Green
Write-Host "(Groups, memberships, APIM, Foundry, and telemetry were untouched.)" -ForegroundColor DarkGray
