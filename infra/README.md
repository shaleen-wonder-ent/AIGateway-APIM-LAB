# Enterprise AI Gateway — Terraform

Provisions the entire demo: APIM, App Insights, backends, Key Vault-backed
Named Values, policy fragments, four vendor APIs, three team Products,
and applies every XML policy from [../policies](../policies) verbatim.

## Layout

| File | Contents |
|------|----------|
| [providers.tf](providers.tf) | `azurerm` + `azuread` provider config |
| [variables.tf](variables.tf) | All input variables |
| [main.tf](main.tf) | RG, Log Analytics, App Insights, APIM (system-assigned MI), RBAC on Foundry / Content Safety / Key Vault |
| [foundation.tf](foundation.tf) | **Azure OpenAI (Foundry)** with `gpt-4o` + `text-embedding-ada-002` deployments, **Content Safety** account, **Key Vault** (RBAC) with the two vendor secrets |
| [named_values.tf](named_values.tf) | Plain + Key Vault-backed Named Values |
| [backends.tf](backends.tf) | `foundry-backend`, `embeddings-backend`, `contentsafety-backend` |
| [fragments.tf](fragments.tf) | 3 policy fragments (`file(...)` from `../policies`) |
| [apis.tf](apis.tf) | 4 APIs plus explicit provider operations: `foundry`, `anthropic`, `bedrock`, `vertex` |
| [policies.tf](policies.tf) | Global policy + per-API policies |
| [products.tf](products.tf) | 3 Products, team subscriptions, API attachments, and team quota policies |
| [outputs.tf](outputs.tf) | Gateway URL, APIM principalId, App Insights ID |
| [terraform.tfvars.example](terraform.tfvars.example) | Fill this in and rename to `terraform.tfvars` |

## Prerequisites

1. Terraform ≥ 1.6, Azure CLI ≥ 2.60.
2. `az login` with permissions to create RGs, Cognitive Services accounts, Key Vault, APIM, and assign roles.
3. Entra ID app registration exposing `api://enterprise-ai-gateway` and three security groups (`AIGW-Team-Marketing`, `-Engineering`, `-Finance`) — pass their GUIDs as variables.
4. Vendor secrets ready to paste in (Anthropic API key, Bedrock bearer token). Prefer `TF_VAR_anthropic_api_key` / `TF_VAR_bedrock_bearer_token` env vars over the tfvars file.

## Deploy

```powershell
cd infra
Copy-Item terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your values (leave secrets blank)
$env:TF_VAR_anthropic_api_key    = "sk-ant-..."
$env:TF_VAR_bedrock_bearer_token = "..."
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

## Notes

- APIM `StandardV2_1` provisions in ~10-15 minutes on first `apply`.
- `azurerm_api_management_policy_fragment` requires **AzureRM provider ≥ 3.71**; the pinned `~> 4.0` is fine.
- Policy files are read from disk with `file(...)`; editing the XML in `../policies/` and re-running `terraform apply` will update APIM.
- If you need private-only ingress, add `virtual_network_type = "Internal"` and `virtual_network_configuration { subnet_id = ... }` to `azurerm_api_management.apim` (requires Premium or StandardV2 with VNet).

## Destroy

```powershell
terraform destroy
```
