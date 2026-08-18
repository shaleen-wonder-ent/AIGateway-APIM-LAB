$gateway = "https://apim-aigw-shaleent-001.azure-api.net"
$tenant  = "16b3c013-d300-468d-ac64-7eda0820b6d3"
$appId   = "246e2a64-1f33-4479-b7b6-3b2cb348ab1f"
$subId   = "09e7c1cb-53ca-4d05-bcf0-8881c42e680e"

# Fresh Entra token + Engineering team key (values are NEVER printed)
$token = az account get-access-token --tenant $tenant --scope "api://$appId/access_as_user" --query accessToken -o tsv
$key   = az rest --method post --url "https://management.azure.com/subscriptions/$subId/resourceGroups/rg-aigw-demo/providers/Microsoft.ApiManagement/service/apim-aigw-shaleent-001/subscriptions/team-engineering/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv

$headers = @{ Authorization = "Bearer $token"; "Ocp-Apim-Subscription-Key" = $key; "Content-Type" = "application/json" }
$body = @{ model = "claude-3-5-haiku-20241022"; max_tokens = 40; messages = @(@{ role = "user"; content = "In one sentence, what is an AI Gateway?" }) } | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "STEP 1  Where is the client sending the request?" -ForegroundColor Yellow
Write-Host "  URL = $gateway/anthropic/v1/messages" -ForegroundColor Cyan
Write-Host "  (this is the APIM gateway, NOT api.anthropic.com)" -ForegroundColor DarkGray

Write-Host ""
Write-Host "STEP 2  What credentials does the client send? (header NAMES only)" -ForegroundColor Yellow
$headers.Keys | ForEach-Object { Write-Host "  - $_" -ForegroundColor Cyan }
if ($headers.ContainsKey("x-api-key")) { Write-Host "  x-api-key PRESENT" -ForegroundColor Red }
else { Write-Host "  => NO 'x-api-key' - the client holds no Anthropic credential" -ForegroundColor Green }

Write-Host ""
Write-Host "STEP 3  DIRECT to Anthropic with no key (what the client alone can do):" -ForegroundColor Yellow
try { Invoke-RestMethod -Method Post -Uri "https://api.anthropic.com/v1/messages" -Headers @{ "Content-Type"="application/json"; "anthropic-version"="2023-06-01" } -Body $body | Out-Null }
catch { $c=[int]$_.Exception.Response.StatusCode; $m=($_.ErrorDetails.Message | ConvertFrom-Json).error.message; Write-Host "  HTTP $c  $m" -ForegroundColor Red }

Write-Host ""
Write-Host "STEP 4  SAME request through APIM (still no client key):" -ForegroundColor Yellow
try {
  $r = Invoke-RestMethod -Method Post -Uri "$gateway/anthropic/v1/messages" -Headers $headers -Body $body
  Write-Host "  HTTP 200  Model says: $($r.content[0].text)" -ForegroundColor Green
  Write-Host "  => APIM injected the key; Anthropic authenticated AND had credits." -ForegroundColor DarkGray
} catch {
  $c=[int]$_.Exception.Response.StatusCode; $m=($_.ErrorDetails.Message | ConvertFrom-Json).error.message
  Write-Host "  HTTP $c  $m" -ForegroundColor Cyan
  if ($m -match "credit") { Write-Host "  => BILLING error, not auth. Anthropic ACCEPTED the key APIM injected." -ForegroundColor Green }
}

Write-Host ""
Write-Host "CONCLUSION: identical keyless client request - direct fails auth, gateway passes." -ForegroundColor Yellow
Write-Host "The only difference is APIM adding the stored key in the middle." -ForegroundColor Yellow