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

## 4. Token usage per team (from the usage trace)

Each Foundry response logs an `aigw-usage` trace with the team and `total_tokens`.
(APIM custom metrics only reach **Metrics explorer**, not the Logs `customMetrics` table —
so we read tokens from traces, which are queryable here.)

```kql
traces
| where timestamp > ago(24h)
| where message has "token-usage"
| extend d = parse_json(message)
| where tostring(d.type) == "token-usage"
| summarize Tokens = sum(toint(d.totalTokens)) by Team = tostring(d.team), CostCenter = tostring(d.costCenter)
| order by Tokens desc
```

> Workspace variant: `traces` → `AppTraces`, `message` → `Message`, `timestamp` → `TimeGenerated`.

## 5. Chargeback ($) per cost center — combine tokens with a price map

Uses the same usage trace as Query 4; update the rates to your negotiated pricing.

```kql
let rates = datatable(Vendor:string, PricePerKTokens:real)
[
    "foundry",   0.005,
    "anthropic", 0.015,
    "bedrock",   0.008,
    "vertex",    0.007
];
traces
| where timestamp > ago(30d)
| where message has "token-usage"
| extend d = parse_json(message)
| where tostring(d.type) == "token-usage"
| extend Team = tostring(d.team), CostCenter = tostring(d.costCenter), Vendor = tostring(d.vendor)
| summarize Tokens = sum(toint(d.totalTokens)) by CostCenter, Team, Vendor
| join kind=inner rates on Vendor
| extend CostUsd = (Tokens / 1000.0) * PricePerKTokens
| summarize TotalUsd = sum(CostUsd) by CostCenter, Team
| order by TotalUsd desc
```

> Workspace variant: `traces` → `AppTraces`, `message` → `Message`, `timestamp` → `TimeGenerated`.
> Note: the token-usage trace is emitted by the **Foundry** API; add the same `<trace>` to
> the other vendor APIs' outbound if you want their tokens in this view too.
