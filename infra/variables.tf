variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "eastus2"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that will hold the AI Gateway."
  default     = "rg-aigw-demo"
}

variable "apim_name" {
  type        = string
  description = "APIM instance name (must be globally unique)."
}

variable "apim_sku" {
  type        = string
  description = "APIM SKU. StandardV2 or Premium recommended for AI Gateway + VNet."
  default     = "StandardV2_1"
}

variable "publisher_name" {
  type    = string
  default = "Enterprise Platform"
}

variable "publisher_email" {
  type    = string
  default = "aigw-admin@example.com"
}

# ---------------- Entra ID / Team groups ----------------

variable "entra_tenant_id" {
  type = string
}

variable "aigw_client_app_id" {
  type        = string
  description = "Entra ID app registration exposed as api://enterprise-ai-gateway."
}

variable "group_team_marketing" {
  type        = string
  description = "Entra ID group objectId for AIGW-Team-Marketing."
}

variable "group_team_engineering" {
  type        = string
  description = "Entra ID group objectId for AIGW-Team-Engineering."
}

variable "group_team_finance" {
  type        = string
  description = "Entra ID group objectId for AIGW-Team-Finance."
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vertex_region" {
  type    = string
  default = "us-central1"
}

variable "vertex_token_broker_url" {
  type        = string
  description = "URL of the Function/API that exchanges the GCP service-account JWT for an OAuth token."
  default     = "https://placeholder.invalid/vertex-token"
}

# ---------------- Vendor secrets (seeded into Key Vault) ----------------

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key. Stored in Key Vault; never exposed to callers."
  sensitive   = true
}

variable "bedrock_bearer_token" {
  type        = string
  description = "AWS Bedrock bearer token or temporary credential. Stored in Key Vault."
  sensitive   = true
}
