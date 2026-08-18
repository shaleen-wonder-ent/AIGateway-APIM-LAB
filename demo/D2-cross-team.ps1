# Demo 2 - Cross-team authorization.
# Your token is in Marketing + Engineering, but NOT Finance. The subscription key selects
# the plan; the token must contain that team's group, or the gateway returns 403 wrong_team.

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

$body = @{ messages = @(@{ role = "user"; content = "ping" }); max_tokens = 5 } | ConvertTo-Json -Depth 5

function Try-Team($label, $team) {
  $h = @{ Authorization = "Bearer $token"; "Ocp-Apim-Subscription-Key" = (Get-TeamKey $team); "Content-Type" = "application/json" }
  try {
    Invoke-RestMethod -Method Post -Uri "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" -Headers $h -Body $body | Out-Null
    Write-Host ("  {0} -> HTTP 200 (allowed)" -f $label) -ForegroundColor Green
  } catch {
    $resp = $_.Exception.Response
    Write-Host ("  {0} -> HTTP {1} {2}" -f $label, [int]$resp.StatusCode, $resp.ReasonPhrase) -ForegroundColor Yellow
    if ($_.ErrorDetails.Message) { Write-Host ("     {0}" -f ($_.ErrorDetails.Message -replace '\s+', ' ')) -ForegroundColor DarkGray }
  }
}

Write-Host ""
Write-Host "Your token: Marketing + Engineering (NOT Finance)." -ForegroundColor Yellow
Write-Host "Key = which plan; token group = who you are. Both must agree." -ForegroundColor DarkGray
Write-Host ""
Try-Team "Marketing key   (you ARE marketing)  " "team-marketing"
Try-Team "Engineering key (you ARE engineering)" "team-engineering"
Try-Team "Finance key     (you are NOT finance)" "team-finance"
