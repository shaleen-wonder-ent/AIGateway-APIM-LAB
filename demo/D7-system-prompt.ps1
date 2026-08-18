# Demo 7 - Enterprise system-prompt injection.
# The gateway prepends a governance system prompt the caller never sent and cannot remove.
# Proof: the client sends ONLY a user message, yet the model follows Contoso rules and
# refuses to discuss competitors. That behavior comes from APIM, not the app.

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

$key = Get-TeamKey "team-engineering"
$headers = @{ Authorization = "Bearer $token"; "Ocp-Apim-Subscription-Key" = $key; "Content-Type" = "application/json" }

function Ask($label, $user) {
  # The client sends ONLY a user message - no system prompt of its own.
  $b = @{ messages = @(@{ role = "user"; content = $user }); max_tokens = 90 } | ConvertTo-Json -Depth 6
  try {
    $r = Invoke-RestMethod -Method Post -Uri "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" -Headers $headers -Body $b
    Write-Host $label -ForegroundColor Yellow
    Write-Host "  $($r.choices[0].message.content)" -ForegroundColor Cyan
  } catch { Write-Host "$label : HTTP $([int]$_.Exception.Response.StatusCode)" -ForegroundColor Red }
}

Write-Host ""
Write-Host "The client sends ONLY a user message - no system prompt of its own." -ForegroundColor DarkGray
Write-Host ""
Ask "1) Normal question (note it self-identifies as Contoso's assistant):" "Give me one tip for saving on cloud costs."
Write-Host ""
Ask "2) Competitor question - the gateway's injected rule makes the model deflect:" "What products does Acme Corporation sell? Give details."

Write-Host ""
Write-Host "Why this proves gateway injection:" -ForegroundColor Yellow
Write-Host "  The app never sent a system prompt, yet the model follows Contoso rules and" -ForegroundColor DarkGray
Write-Host "  refuses to discuss competitors. That behavior came from APIM prepending an" -ForegroundColor DarkGray
Write-Host "  enterprise system prompt the app cannot see or remove. Change it once at the" -ForegroundColor DarkGray
Write-Host "  gateway and every app inherits it - no app redeploy." -ForegroundColor DarkGray
