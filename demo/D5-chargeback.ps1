# Demo 5 - Chargeback and audit.
# Generates mixed traffic, then queries per-team requests and token totals from App Insights.
# Telemetry lags ~2-5 minutes, so freshly generated calls may not appear immediately.

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

$mk = Get-TeamKey "team-marketing"
$ek = Get-TeamKey "team-engineering"

Write-Host ""
Write-Host "Generating mixed traffic (1 marketing + 2 engineering)..." -ForegroundColor Yellow
foreach ($k in @($mk, $ek, $ek)) {
  $uniq = [guid]::NewGuid().ToString()
  $h = @{ Authorization = "Bearer $token"; "Ocp-Apim-Subscription-Key" = $k; "Content-Type" = "application/json" }
  $b = @{ messages = @(@{ role = "user"; content = "One line cloud tip. id $uniq" }); max_tokens = 30 } | ConvertTo-Json
  try { Invoke-RestMethod -Method Post -Uri "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" -Headers $h -Body $b | Out-Null; Write-Host "  call ok" -ForegroundColor DarkGray }
  catch { Write-Host "  call HTTP $([int]$_.Exception.Response.StatusCode)" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "Querying App Insights (last 30 min)..." -ForegroundColor Yellow
$customerId = az resource show -g $rg -n "law-$apim" --resource-type Microsoft.OperationalInsights/workspaces --query properties.customerId -o tsv
$laToken = az account get-access-token --resource "https://api.loganalytics.io" --query accessToken -o tsv
$lah = @{ Authorization = "Bearer $laToken"; "Content-Type" = "application/json" }

function Run-KQL($title, $kql) {
  Write-Host ""
  Write-Host $title -ForegroundColor Yellow
  $qb = @{ query = $kql } | ConvertTo-Json
  try {
    $res = Invoke-RestMethod -Method Post -Uri "https://api.loganalytics.io/v1/workspaces/$customerId/query" -Headers $lah -Body $qb
    if ($res.tables[0].rows.Count -eq 0) { Write-Host "  (no data yet - telemetry lags 2-5 min)" -ForegroundColor DarkGray }
    else {
      $cols = $res.tables[0].columns.name
      $res.tables[0].rows | ForEach-Object { $row = $_; $o = [ordered]@{}; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }; [pscustomobject]$o } | Format-Table -AutoSize
    }
  } catch { Write-Host "  query error: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

Run-KQL "Requests by team:" 'AppTraces | where TimeGenerated > ago(30m) | where Message has "correlationId" | extend d=parse_json(Message) | summarize Requests=count() by Team=tostring(d.team), CostCenter=tostring(d.costCenter) | order by Team asc'
Run-KQL "Tokens by team:"   'AppTraces | where TimeGenerated > ago(30m) | where Message has "token-usage" | extend d=parse_json(Message) | summarize Tokens=sum(toint(d.totalTokens)) by Team=tostring(d.team), CostCenter=tostring(d.costCenter) | order by Tokens desc'

Write-Host ""
Write-Host "For the portal view: App Insights 'appi-$apim' -> Logs. Full query set in kql-queries.md." -ForegroundColor DarkGray
