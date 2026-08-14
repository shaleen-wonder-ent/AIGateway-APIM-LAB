# Enterprise AI Gateway Demo — Azure API Management

This repository contains Azure API Management (APIM) policies that showcase how an enterprise can govern LLM access using APIM as a central **AI Gateway** across Microsoft Foundry (Azure OpenAI) and vendor-hosted models (Anthropic, AWS Bedrock, Google Vertex AI).

## Demo Scenarios

| # | Scenario | Policy File | APIM Feature |
|---|----------|-------------|--------------|
| 1 | User access revocation (Entra ID group / employment status) | `policies/global.xml` | `validate-azure-ad-token`, JWT group claims |
| 2 | Team-wise token quota & budget controls | `policies/product-team-*.xml` | `azure-openai-token-limit`, `quota-by-key` |
| 3 | No direct Foundry / vendor API key exposure | `policies/api-*.xml` | `authentication-managed-identity`, Named Values in Key Vault |
| 4 | Central gateway for Foundry, Anthropic, Bedrock, Vertex | `policies/api-*.xml` | Multiple backends, unified OpenAI-shaped API |
| 5 | Centralized monitoring — tokens, audit, chargeback | `policies/global.xml` | `azure-openai-emit-token-metric`, App Insights logs |
| 6 | Private-only access (leaked-key mitigation) | `policies/global.xml` | Client IP filter + private-endpoint reminder |
| 7 | Consistent governance across all vendors | `policies/fragment-*.xml` | Reusable policy fragments |

## Repository Layout

```
policies/
  global.xml                     # Applied at "All APIs" scope
  fragment-auth-entra.xml        # Reusable: Entra ID validation + team extraction
  fragment-content-safety.xml    # Reusable: LLM content safety + jailbreak detection
  fragment-audit-log.xml         # Reusable: chargeback logging to App Insights
  api-foundry.xml                # Azure OpenAI / Foundry API-level policy
  api-anthropic.xml              # Anthropic (api.anthropic.com) API-level policy
  api-bedrock.xml                # AWS Bedrock API-level policy (SigV4)
  api-vertex.xml                 # Google Vertex AI API-level policy (OAuth JWT)
  product-team-marketing.xml     # Team "Marketing" — 50K TPM, $500/day
  product-team-engineering.xml   # Team "Engineering" — 500K TPM, $5000/day
  product-team-finance.xml       # Team "Finance" — 20K TPM, $200/day
```

## Prerequisites

- APIM instance (Standard v2 or Premium recommended for AI Gateway features and VNet)
- APIM system-assigned managed identity enabled
- Entra ID: security groups `AIGW-Team-Marketing`, `AIGW-Team-Engineering`, `AIGW-Team-Finance`
- Azure OpenAI / Foundry resource with deployments (e.g. `gpt-4o`, `text-embedding-ada-002`)
- Azure AI Content Safety resource
- Azure Key Vault storing vendor API keys as Named Values:
  - `anthropic-api-key`
  - `bedrock-access-key`, `bedrock-secret-key`
  - `vertex-service-account-json`
- Application Insights linked to APIM for logs & metrics

## Demo Flow (Aug 20)

1. **Setup slide** — show APIM as the only ingress; models are behind private endpoints.
2. **Scenario 1** — Call gateway with a valid team member's token → succeeds. Revoke by removing user from `AIGW-Team-Marketing` group → next call returns `401`.
3. **Scenario 2** — Blast the same endpoint from a Marketing subscription until `429 Token Limit Exceeded`; switch to Engineering subscription → succeeds.
4. **Scenario 3** — Show a request without any API key header — APIM injects the vendor key via managed identity / Named Values. Rotate the Named Value; no client change required.
5. **Scenario 4** — Same client, same OpenAI-shaped payload, only the URL path changes: `/foundry/...`, `/anthropic/...`, `/bedrock/...`, `/vertex/...`.
6. **Scenario 5** — Open App Insights → KQL: tokens by team, cost per team, top users.
7. **Scenario 6** — Call from an unlisted public IP → blocked. Call from corp VNet / private endpoint → allowed.
8. **Scenario 7** — Show the same fragments (`fragment-auth-entra`, `fragment-content-safety`, `fragment-audit-log`) referenced by every API — one control plane.

## Apply the Policies

```bash
# All-APIs (global) scope
az apim policy create --resource-group <rg> --service-name <apim> \
  --value @policies/global.xml --format xml

# API-level (repeat per API)
az apim api policy create --resource-group <rg> --service-name <apim> \
  --api-id foundry --value @policies/api-foundry.xml --format xml

# Product-level
az apim product policy create --resource-group <rg> --service-name <apim> \
  --product-id team-marketing --value @policies/product-team-marketing.xml --format xml
```

Policy fragments must be created via the portal or ARM/Bicep — see `bicep/fragments.bicep` (optional, not included in this scaffold).
