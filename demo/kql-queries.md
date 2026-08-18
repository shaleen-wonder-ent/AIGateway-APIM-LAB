# Demo KQL Queries — Enterprise AI Gateway

**Where to run:** open Application Insights **`appi-apim-aigw-shaleent-001`** → **Logs**.
The classic table names used below (`traces`, `requests`, `customMetrics`) resolve there.

> If you run these from the **Log Analytics workspace** instead, the tables are renamed —
> use the workspace names shown under each query (`AppTraces`, `AppRequests`, `AppMetrics`)
> and `TimeGenerated` instead of `timestamp`. This is why `customMetrics` returned
> *"failed to resolve table"* in the workspace query editor.

**Data lag:** telemetry appears ~2–5 minutes after traffic. Run a few Demo 1 calls first.
Telemetry only flows because the APIM **Application Insights diagnostic** is enabled
(`azurerm_api_management_diagnostic` in [../infra/main.tf](../infra/main.tf)).

---

## 1. Activity & chargeback by team (from the audit trace) — the reliable one

Every request writes an `aigw-audit` trace tagged with team, user, and cost center.

```kql
traces
| where timestamp > ago(24h)
| where message has "correlationId"
| extend d = parse_json(message)
| extend Team = tostring(d.team), CostCenter = tostring(d.costCenter), Api = tostring(d.apiName)
| summarize Requests = count() by Team, CostCenter, Api
| order by Requests desc
```

> Workspace variant: `traces` → `AppTraces`, `message` → `Message`, `timestamp` → `TimeGenerated`.

## 2. Top users by activity

```kql
traces
| where timestamp > ago(7d)
| where message has "correlationId"
| extend d = parse_json(message)
| extend User = tostring(d.user), Team = tostring(d.team)
| summarize Requests = count() by User, Team
| top 20 by Requests desc
```

## 3. Denied / blocked requests audit (who was refused, and why)

```kql
requests
| where timestamp > ago(7d)
| where resultCode in ("401", "403", "429", "400")
| summarize Count = count() by resultCode, name
| order by Count desc
```

> Reading the codes: `401` = bad/expired token or missing subscription key,
> `403` = wrong team / private-only, `429` = team quota exceeded, `400` = content filtered.
> Workspace variant: `requests` → `AppRequests`, `resultCode` → `ResultCode`,
> `timestamp` → `TimeGenerated`.

## 4. Token usage per team (custom metric)

The gateway emits a `TotalTokens` custom metric tagged with Team / CostCenter / Vendor.

```kql
customMetrics
| where timestamp > ago(24h)
| where name in ("Total Tokens", "TotalTokens")
| extend Team = tostring(customDimensions["Team"]), CostCenter = tostring(customDimensions["CostCenter"]), Vendor = tostring(customDimensions["Vendor"])
| summarize Tokens = sum(valueSum) by Team, CostCenter, Vendor
| order by Tokens desc
```

> If this returns nothing, the metric is still visible in **Metrics explorer** (open the
> App Insights resource → **Metrics** → metric `TotalTokens`, split by `Team`). Preserving
> custom-metric **dimensions** in Logs requires "custom metrics with dimensions" enabled on
> the App Insights resource; Query 1 (trace-based) is the dependable chargeback view for the
> demo. Workspace variant: `customMetrics` → `AppMetrics`, `customDimensions` → `Properties`,
> `valueSum` → `Sum`.

## 5. Chargeback ($) per cost center — combine tokens with a price map

Uses the same custom metric as Query 4; update the rates to your negotiated pricing.

```kql
let rates = datatable(Vendor:string, PricePerKTokens:real)
[
    "foundry",   0.005,
    "anthropic", 0.015,
    "bedrock",   0.008,
    "vertex",    0.007
];
customMetrics
| where timestamp > ago(30d)
| where name in ("Total Tokens", "TotalTokens")
| extend Team = tostring(customDimensions["Team"]), CostCenter = tostring(customDimensions["CostCenter"]), Vendor = tostring(customDimensions["Vendor"])
| summarize Tokens = sum(valueSum) by CostCenter, Team, Vendor
| join kind=inner rates on Vendor
| extend CostUsd = (Tokens / 1000.0) * PricePerKTokens
| summarize TotalUsd = sum(CostUsd) by CostCenter, Team
| order by TotalUsd desc
```
