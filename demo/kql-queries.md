# Demo KQL Queries — Enterprise AI Gateway

Run these in the Application Insights linked to your APIM instance.

## Total tokens per team (last 24h)

```kql
customMetrics
| where timestamp > ago(24h)
| where name in ("Total Tokens", "TotalTokens")
| extend Team       = tostring(customDimensions["Team"])
| extend CostCenter = tostring(customDimensions["CostCenter"])
| extend Vendor     = tostring(customDimensions["Vendor"])
| summarize Tokens = sum(value) by Team, CostCenter, Vendor
| order by Tokens desc
```

## Chargeback ($) per cost center

Assumes an ingest-side price map. Update rates to your negotiated pricing.

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
| extend Team       = tostring(customDimensions["Team"])
| extend CostCenter = tostring(customDimensions["CostCenter"])
| extend Vendor     = tostring(customDimensions["Vendor"])
| summarize Tokens = sum(value) by CostCenter, Team, Vendor
| join kind=inner rates on Vendor
| extend CostUsd = (Tokens / 1000.0) * PricePerKTokens
| summarize TotalUsd = sum(CostUsd) by CostCenter, Team
| order by TotalUsd desc
```

## Access-revocation audit — who was denied and why

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(7d)
| where ResponseCode in (401, 403)
| project TimeGenerated, CallerIpAddress, Url, ResponseCode, LastErrorReason, LastErrorSection, LastErrorMessage
| order by TimeGenerated desc
```

## Top users by token consumption

```kql
customMetrics
| where timestamp > ago(7d)
| where name in ("Total Tokens", "TotalTokens")
| extend User = tostring(customDimensions["User"])
| extend Team = tostring(customDimensions["Team"])
| summarize Tokens = sum(value) by User, Team
| top 20 by Tokens desc
```

## Content-safety blocks per team

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| where LastErrorSection == "llm-content-safety" or ResponseCode == 400
| extend Team = tostring(parse_json(RequestHeaders)["X-AIGW-Team"])
| summarize Blocks = count() by Team, LastErrorReason
| order by Blocks desc
```
