# Demo 3 - Per-team spend limits (quotas).
# Marketing (1,000 TPM) trips a 429 quickly; Engineering (higher tier) still works.
# Unique prompts bypass the semantic cache so real tokens are consumed.

# --- Setup ---
$gateway = "https://apim-aigw-shaleent-001.azure-api.net"
$tenant  = "16b3c013-d300-468d-ac64-7eda0820b6d3"
$appId   = "246e2a64-1f33-4479-b7b6-3b2cb348ab1f"
$subId   = "09e7c1cb-53ca-4d05-bcf0-8881c42e680e"
$apim    = "apim-aigw-shaleent-001"
$rg      = "rg-aigw-demo"

$token = az account get-access-token --tenant $tenant --scope "api://$appId/access_as_user" --query accessToken -o tsv
function Get-TeamKey($team) {
  az rest --method post --url "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apim/subscriptions/$team/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
}

$key = Get-TeamKey "team-marketing"
$headers = @{ Authorization = "Bearer $token"; "Ocp-Apim-Subscription-Key" = $key; "Content-Type" = "application/json" }

Write-Host ""
Write-Host "Marketing tier = 1,000 TPM. Firing unique prompts until 429..." -ForegroundColor Yellow
$hit = $false
for ($i = 1; $i -le 15 -and -not $hit; $i++) {
  $uniq = [guid]::NewGuid().ToString()
  $b = @{ messages = @(@{ role = "user"; content = "Write a detailed 1800-word essay on cloud governance. Unique id $uniq." }); max_tokens = 2000 } | ConvertTo-Json -Depth 10
  try {
    $r = Invoke-WebRequest -Method Post -Uri "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" -Headers $headers -Body $b
    $content = ($r.Content | ConvertFrom-Json).choices[0].message.content
    $snip = $content.Substring(0, [Math]::Min(180, $content.Length))
    Write-Host ("Call {0}: HTTP 200  team-remaining={1}" -f $i, ($r.Headers['x-team-tokens-remaining'] -join '')) -ForegroundColor Green
    Write-Host "   Model says: $snip..." -ForegroundColor Cyan
  } catch {
    $c = [int]$_.Exception.Response.StatusCode
    if ($c -eq 429) { $hit = $true; Write-Host ("Call {0}: HTTP 429  TOKEN LIMIT EXCEEDED - team quota enforced" -f $i) -ForegroundColor Red }
    else { Write-Host ("Call {0}: HTTP {1}" -f $i, $c) -ForegroundColor Yellow }
  }
}

Write-Host ""
Write-Host "Contrast - Engineering (higher tier) still works:" -ForegroundColor Yellow
$ek = Get-TeamKey "team-engineering"
$eh = @{ Authorization = "Bearer $token"; "Ocp-Apim-Subscription-Key" = $ek; "Content-Type" = "application/json" }
$uniq = [guid]::NewGuid().ToString()
$eb = @{ messages = @(@{ role = "user"; content = "One sentence on AI governance. id $uniq" }); max_tokens = 30 } | ConvertTo-Json -Depth 10
$er = Invoke-WebRequest -Method Post -Uri "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" -Headers $eh -Body $eb
Write-Host ("Engineering: HTTP {0}  team-remaining={1}" -f [int]$er.StatusCode, ($er.Headers['x-team-tokens-remaining'] -join '')) -ForegroundColor Green
Write-Host "   Model says: $((($er.Content | ConvertFrom-Json).choices[0].message.content))" -ForegroundColor Cyan

Write-Host ""
Write-Host "Note: the cap is a per-minute sliding window - wait ~60s before re-running." -ForegroundColor DarkGray
