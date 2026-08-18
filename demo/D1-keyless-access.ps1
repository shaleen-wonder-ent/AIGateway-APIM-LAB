# Demo 1 - Keyless, identity-controlled access to Foundry.
# Shows: gateway URL, caller identity, no api-key on the client, a real GPT-4o answer,
# and the two controls (missing key / invalid token) that both block.

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
$body = @{
  messages = @(
    @{ role = "system"; content = "You are a concise enterprise cloud assistant." },
    @{ role = "user";   content = "Explain the value of an AI Gateway in exactly three bullets." }
  )
  max_tokens = 150
} | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "STEP 1  The endpoint is the gateway, not the model" -ForegroundColor Yellow
Write-Host "  $gateway/foundry/openai/deployments/gpt-4o/chat/completions" -ForegroundColor Cyan

Write-Host ""
Write-Host "STEP 2  Who is the caller? (identity claims from the Entra token)" -ForegroundColor Yellow
$p = $token.Split('.')[1].Replace('-','+').Replace('_','/'); while ($p.Length % 4) { $p += '=' }
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
[pscustomobject]@{ User = $claims.name; UPN = $claims.preferred_username; ClientApp = $claims.azp; Scope = $claims.scp; TeamGroups = @($claims.groups).Count } | Format-List

Write-Host "STEP 3  What credentials does the client send? (header NAMES only)" -ForegroundColor Yellow
$headers.Keys | ForEach-Object { Write-Host "  - $_" -ForegroundColor Cyan }
Write-Host "  => NO 'api-key' - the client holds no Foundry credential" -ForegroundColor Green

Write-Host ""
Write-Host "STEP 4  Call GPT-4o through the gateway:" -ForegroundColor Yellow
$r = Invoke-RestMethod -Method Post -Uri "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" -Headers $headers -Body $body
Write-Host $r.choices[0].message.content -ForegroundColor Cyan
Write-Host ("  tokens: prompt={0} completion={1} total={2}" -f $r.usage.prompt_tokens, $r.usage.completion_tokens, $r.usage.total_tokens) -ForegroundColor DarkGray

Write-Host ""
Write-Host "STEP 5  The controls - access needs BOTH a team key AND a valid identity:" -ForegroundColor Yellow
function Show-Block($label, $hdrs) {
  try {
    Invoke-RestMethod -Method Post -Uri "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" -Headers $hdrs -Body $body | Out-Null
    Write-Host "  $label : UNEXPECTED SUCCESS" -ForegroundColor Red
  } catch {
    $resp = $_.Exception.Response
    Write-Host ("  {0} : HTTP {1} {2}" -f $label, [int]$resp.StatusCode, $resp.ReasonPhrase) -ForegroundColor Green
  }
}
Show-Block "A) Missing subscription key" @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
Show-Block "B) Invalid identity token  " @{ Authorization = "Bearer not.a.real.token"; "Ocp-Apim-Subscription-Key" = $key; "Content-Type" = "application/json" }
