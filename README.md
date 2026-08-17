# Enterprise AI Gateway on Azure API Management

A hands-on lab that turns Azure API Management (APIM) into a governed **AI Gateway** in front of Microsoft Foundry (Azure OpenAI) and vendor-hosted models — Anthropic, AWS Bedrock, and Google Vertex AI — so an enterprise can consume LLMs through one Entra-authenticated, quota-limited, audited, key-less endpoint instead of exposing model APIs or keys directly to app teams.

- **Repo**: [shaleen-wonder-ent/AIGateway-APIM-LAB](https://github.com/shaleen-wonder-ent/AIGateway-APIM-LAB)
- **Tech**: Azure APIM (StandardV2), Azure OpenAI, Azure AI Content Safety, Entra ID, Application Insights, Terraform (`azurerm ~> 4.0`)
- **Language**: XML policies + HCL for infra

---

## 1. What this is

A production-shaped reference implementation of an "AI Gateway" pattern:

```
                +--------------------+
Client apps --> |  Azure APIM        | --> Azure OpenAI (Foundry)
(Entra ID JWT)  |  (single endpoint) | --> Anthropic
                |  policies          | --> AWS Bedrock
                +--------------------+ --> Google Vertex AI
                    |         |
              App Insights   Key Vault (optional)
              (audit + KQL)  (vendor secrets)
```

Everything a caller sees is `https://<apim>.azure-api.net/{vendor}/...`. APIM handles auth, quota, key injection, content safety, and telemetry.

---

## 2. Why we're doing it

The seven concrete problems this lab solves:

| # | Problem | Feature that solves it |
|---|---|---|
| 1 | **Access revocation** — an employee leaves a team; API keys stay valid for months | Entra ID token + group-claim check → membership change revokes on next token refresh |
| 2 | **Runaway spend** — no per-team cap on tokens or requests | `azure-openai-token-limit` + `quota-by-key` per Product |
| 3 | **Vendor API keys everywhere** — copied into env files, source, laptops | Managed identity to Foundry, KV-/APIM-hosted named values for vendor keys — never returned to the caller |
| 4 | **Vendor sprawl** — four SDKs, four auth models, four request shapes | One OpenAI-shaped API; APIM translates payloads for Anthropic / Bedrock / Vertex |
| 5 | **No chargeback** — finance can't attribute spend to teams | `azure-openai-emit-token-metric` + `emit-metric` with `Team` / `CostCenter` dimensions, plus `<trace>` to App Insights |
| 6 | **Leaked-key blast radius** — a leaked key can be used from anywhere | Private ingress + IP allow-list; VNet-injected APIM in production |
| 7 | **Inconsistent governance** — every team writes its own middleware | Policy fragments reused across all vendor APIs |

---

## 3. Repository layout

```
policies/
  global.xml                     Global (All APIs) — Entra auth, team extraction, IP filter, trace
  fragment-content-safety.xml    Reusable LLM content safety + jailbreak detection
  api-foundry.xml                Azure OpenAI / Foundry — MI auth, semantic cache, token metrics
  api-anthropic.xml              Anthropic — OpenAI → Anthropic payload translation
  api-bedrock.xml                AWS Bedrock — OpenAI → Bedrock Messages translation
  api-vertex.xml                 Vertex AI — OAuth broker + OpenAI → Gemini translation
  product-team-marketing.xml     50K TPM / 500 RPM / 5M tokens/day
  product-team-engineering.xml   500K TPM / 5K RPM / 50M tokens/day
  product-team-finance.xml       20K TPM / 200 RPM / 2M tokens/day

infra/                           Terraform stack (see infra/README.md)
demo/
  test-requests.http             REST Client requests for the demo
  kql-queries.md                 Chargeback + audit KQL for Application Insights
```

---

## 4. Prerequisites

- Azure subscription + Owner (or Contributor + User Access Administrator) on the target RG
- Terraform ≥ 1.6, Azure CLI ≥ 2.60, VS Code with the *REST Client* extension (for the demo)
- Ability to create Entra ID app registrations and security groups (or someone who can)
- Foundry / Azure OpenAI quota — at least `gpt-4o 50K TPM GlobalStandard` and `text-embedding-ada-002 30K TPM` in your region

Cost note: APIM `StandardV2_1` is ~$700/mo. Use `Developer_1` (~$50/mo, no SLA) for pure demo runs.

---

## 5. Step-by-step lab

### Step 1 — Clone

```powershell
git clone https://github.com/shaleen-wonder-ent/AIGateway-APIM-LAB.git
cd AIGateway-APIM-LAB
```

### Step 2 — Set subscription

```powershell
az login
az account set --subscription <your-subscription-id>
```

### Step 3 — Create Entra ID objects

```powershell
# Three team groups
$g1 = az ad group create --display-name "AIGW-Team-Marketing"   --mail-nickname "aigw-team-marketing"   --query id -o tsv
$g2 = az ad group create --display-name "AIGW-Team-Engineering" --mail-nickname "aigw-team-engineering" --query id -o tsv
$g3 = az ad group create --display-name "AIGW-Team-Finance"     --mail-nickname "aigw-team-finance"     --query id -o tsv

# Add yourself to two of them (leave Finance empty for the revocation demo)
$me = az ad signed-in-user show --query id -o tsv
az ad group member add --group "AIGW-Team-Marketing"   --member-id $me
az ad group member add --group "AIGW-Team-Engineering" --member-id $me

# App registration whose audience is enforced by APIM
$appId = az ad app create --display-name "Enterprise AI Gateway" --sign-in-audience AzureADMyOrg --query appId -o tsv
az ad app update --id $appId --identifier-uris "api://$appId"

Write-Host "Save these: appId=$appId, groups: $g1 / $g2 / $g3"
```

In **Entra admin center → App registrations → Enterprise AI Gateway → Expose an API**:

1. Add delegated scope `access_as_user` for admins and users.
2. Under **Authorized client applications**, add Azure CLI client ID
  `04b07795-8ddb-461a-bbee-02f9e1bf7b46` and select `access_as_user`.

This pre-authorizes the CLI used by the demo. Use a dedicated client app instead of
Azure CLI for production callers.

### Step 4 — Fill in `terraform.tfvars`

```powershell
cd infra
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — paste the appId, group IDs, tenant ID, apim name.
```

Key values:

```hcl
apim_name              = "apim-aigw-<yourname>-001"
entra_tenant_id        = "<your-tenant-id>"
aigw_client_app_id     = "<appId from step 3>"
aigw_caller_client_app_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
aigw_audience          = "api://<appId>"
group_team_marketing   = "<g1>"
group_team_engineering = "<g2>"
group_team_finance     = "<g3>"
enable_private_ip_filter = false             # controlled public demo only
anthropic_api_key      = "placeholder"       # replace with real key when ready
bedrock_bearer_token   = "placeholder"
```

### Step 5 — Deploy

```powershell
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Total time: 3–5 minutes (APIM StandardV2 is ~2 min, everything else parallelizes). Outputs include `apim_gateway_url`.

### Step 6 — Verify the resources

```powershell
az resource list -g rg-aigw-demo --query "[].{name:name, type:type}" -o table
```

You should see:
- 1 APIM instance, 3 backends, 4 APIs, 3 products, 12 product/API attachments
- 1 Foundry account with `gpt-4o` + `text-embedding-ada-002` deployments
- 1 Content Safety account
- 1 App Insights + Log Analytics workspace
- 1 policy fragment (`fragment-content-safety`), 1 global policy, 4 API policies, 3 product policies
- 11 named values (2 secret, 9 plain)

### Step 7 — Smoke test with your own token

```powershell
$appId   = "<the appId>"
$tenant  = "<tenant-id>"
$gateway = "https://apim-aigw-<yourname>-001.azure-api.net"

# First run requires an interactive sign-in for the delegated scope.
az login --tenant $tenant --scope "api://$appId/access_as_user"
$token = az account get-access-token --scope "api://$appId/access_as_user" --query accessToken -o tsv

$subscriptionId = az account show --query id -o tsv
$secretsUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/rg-aigw-demo/providers/Microsoft.ApiManagement/service/apim-aigw-<yourname>-001/subscriptions/team-marketing/listSecrets?api-version=2024-05-01"
$subKey = az rest --method post --url $secretsUrl --query primaryKey -o tsv

curl -Method POST "$gateway/foundry/openai/deployments/gpt-4o/chat/completions?api-version=2024-08-01-preview" `
  -Headers @{
    "Authorization"           = "Bearer $token";
    "Ocp-Apim-Subscription-Key" = $subKey;
    "Content-Type"            = "application/json"
  } `
  -Body '{"messages":[{"role":"user","content":"Say hello in 5 words"}], "max_tokens":30}'
```

Expected: a JSON response with `choices[0].message.content` and headers `x-tokens-consumed` + `x-tokens-remaining`.

### Step 8 — Run the seven scenarios

The demo file [demo/test-requests.http](demo/test-requests.http) has ready-to-run requests. Open it in VS Code with the *REST Client* extension, paste your gateway URL + token, and click **Send Request** above each block.

| Scenario | How to demo |
|---|---|
| 1. Revocation | Call `/foundry/...` → 200. Remove yourself from `AIGW-Team-Marketing`. Get a new token (`az account get-access-token`). Call again → 401 with `access_revoked` body. |
| 2. Team quotas | From Marketing subscription, hammer with 4000-token requests until `429 Token Limit Exceeded`. Switch to Engineering sub → still 200 (higher tier). |
| 3. No key exposure | Show the request payload: no `api-key` header. APIM injects the MI token (Foundry) or the KV-backed named value (Anthropic/Bedrock). Show that a caller sending an `api-key` header sees it stripped. |
| 4. Multi-vendor | Same OpenAI-shaped payload; change only the path (`/foundry`, `/anthropic`, `/bedrock`, `/vertex`) — all return `choices` in OpenAI shape. |
| 5. Chargeback | Open App Insights → Logs → paste queries from [demo/kql-queries.md](demo/kql-queries.md). Show tokens/$ per team and per cost centre. |
| 6. Private-only | Call from your public IP → 403 `private_only`. Then either add your IP to the global policy's `ip-filter` or call from a VNet-connected host. |
| 7. Consistent governance | Open [policies/fragment-content-safety.xml](policies/fragment-content-safety.xml) and show `<include-fragment fragment-id="fragment-content-safety" />` in every `api-*.xml`. One change, four APIs updated. |

### Step 9 — Explore the policies

For each policy file:

- [policies/global.xml](policies/global.xml) — Scenarios 1, 5, 6
- [policies/api-foundry.xml](policies/api-foundry.xml) — MI auth, semantic cache, token metrics
- [policies/api-anthropic.xml](policies/api-anthropic.xml), [api-bedrock.xml](policies/api-bedrock.xml), [api-vertex.xml](policies/api-vertex.xml) — payload translation + vendor key injection
- [policies/product-team-*.xml](policies/) — token/RPM/daily quotas per Product

### Step 10 — Clean up

```powershell
cd infra
terraform destroy
# Also delete the Entra objects if you don't want to keep them:
az ad app delete --id <appId>
az ad group delete --group "AIGW-Team-Marketing"
az ad group delete --group "AIGW-Team-Engineering"
az ad group delete --group "AIGW-Team-Finance"
```

For a public demo, set `enable_private_ip_filter = false` only for the demo window.
Restore it to `true` and run `terraform apply` afterward.

---

## 6. Design decisions worth calling out

- **Vendor key storage.** The lab defaults to APIM secret named values with plain string inputs, because MCAPS-style subscriptions may block public Key Vault access. Migration path: create a KV, add the two secrets, and swap the `azurerm_api_management_named_value` blocks from `value = var.x` to a `value_from_key_vault { secret_id = ... }` block.
- **Content Safety only.** Only `fragment-content-safety` is deployed as an APIM policy fragment. Team-membership checks are inlined in `global.xml`; audit logging uses inline `<trace>` to Application Insights (no Event Hub required).
- **APIM's Razor validator.** APIM's `@{ ... }` expressions require **braced** control-flow bodies — `if (x) { return y; }`, not `if (x) return y;`. All policies in this lab follow that rule.
- **`<base />` at global scope is not allowed** — the global policy has no parent. Only API/Product/Operation policies use `<base />`.
- **Private ingress.** For real deployments, put APIM on **StandardV2 with VNet integration** or **Premium** and use a private endpoint. The current `ip-filter` in `global.xml` is a backstop only.

---

## 7. Repository files

- [infra/README.md](infra/README.md) — Terraform stack details
- [demo/test-requests.http](demo/test-requests.http) — REST Client test suite
- [demo/kql-queries.md](demo/kql-queries.md) — Chargeback / audit KQL queries
- [policies/](policies/) — Every XML policy applied by the stack
