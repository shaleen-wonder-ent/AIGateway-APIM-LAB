<#
.SYNOPSIS
    End-to-end deploy/destroy orchestrator for the Enterprise AI Gateway on APIM lab.

.DESCRIPTION
    A single entry point that provisions (or tears down) the complete lab:

      Entra layer (created outside Terraform):
        * "Enterprise AI Gateway" app registration + service principal
          (api://<appId> identifier, access_as_user scope, Azure CLI pre-auth,
           SecurityGroup claims, access-token v2)
        * Three security groups: AIGW-Team-Marketing / -Engineering / -Finance
        * Adds the signed-in user to Marketing + Engineering
          (Finance is left empty on purpose for the revocation demo)

      Infra layer (Terraform in .\infra):
        * Resource group, Log Analytics, Application Insights
        * APIM (system-assigned MI) + logger + diagnostic
        * Microsoft Foundry (Azure OpenAI) with gpt-4o + text-embedding-ada-002
        * Azure AI Content Safety
        * Role assignments, products, subscriptions, APIs, policies, named values

    Everything the script creates is recorded in .\.lab-state.json so that a later
    'destroy' removes exactly those objects (Terraform stack + app registration +
    service principal + the three security groups).

.PARAMETER Action
    'deploy' (alias 'create') or 'destroy'. If omitted, the script asks interactively.

.PARAMETER TenantId
    Entra tenant to deploy into. If omitted (deploy), the script lists and prompts.

.PARAMETER SubscriptionId
    Target subscription. If omitted (deploy), the script lists and prompts.

.PARAMETER Location
    Azure region. Default: eastus2.

.PARAMETER ResourceGroupName
    Resource group name. Default: rg-aigw-demo.

.PARAMETER ApimName
    Globally-unique APIM name. If omitted, a unique name is generated.

.PARAMETER ApimSku
    APIM SKU. Default StandardV2_1. Use Developer_1 for a cheap demo (no SLA).

.PARAMETER AnthropicApiKey
    Optional Anthropic key stored as an APIM secret named value. Placeholder if omitted.

.PARAMETER BedrockBearerToken
    Optional AWS Bedrock token stored as an APIM secret named value. Placeholder if omitted.

.PARAMETER EnablePrivateIpFilter
    Restrict APIM callers to RFC1918 addresses. Off by default (laptop demo friendly).

.PARAMETER Force
    Skip confirmation prompts (use with care, especially for destroy).

.PARAMETER KeepEntra
    On destroy, tear down only the Terraform/Azure stack and leave the app
    registration + service principal + security groups (and .lab-state.json) intact.

.PARAMETER Help
    Show full help. Also triggered by -h, --help, or /?.

.EXAMPLE
    .\Deploy-AIGatewayLab.ps1
    Interactive: asks deploy/destroy, then tenant + subscription.

.EXAMPLE
    .\Deploy-AIGatewayLab.ps1 -Action deploy -TenantId <tid> -SubscriptionId <sid>

.EXAMPLE
    .\Deploy-AIGatewayLab.ps1 -Action destroy -Force

.EXAMPLE
    .\Deploy-AIGatewayLab.ps1 --help
    Show full help (also -h, -Help, or /?).
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('deploy', 'create', 'destroy')]
    [string]$Action,

    [string]$TenantId,
    [string]$SubscriptionId,
    [string]$Location = 'eastus2',
    [string]$ResourceGroupName = 'rg-aigw-demo',
    [string]$ApimName,

    [ValidateSet('StandardV2_1', 'Developer_1', 'Basic_1', 'Premium_1')]
    [string]$ApimSku = 'StandardV2_1',

    [string]$AnthropicApiKey,
    [string]$BedrockBearerToken,

    [switch]$EnablePrivateIpFilter,
    [switch]$Force,
    [switch]$KeepEntra,

    [Alias('h')][switch]$Help,

    # Captures tokens like --help / /? so they can be handled gracefully.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# --- Constants ---
$RepoRoot     = $PSScriptRoot
$InfraDir     = Join-Path $RepoRoot 'infra'
$TfvarsPath   = Join-Path $InfraDir 'terraform.tfvars'
$ManifestPath = Join-Path $RepoRoot '.lab-state.json'
$GraphBase    = 'https://graph.microsoft.com/v1.0'
$CliAppId     = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'   # Azure CLI public client (the caller)
$AppDisplay   = 'Enterprise AI Gateway'

$Groups = @(
    @{ Key = 'marketing';   Display = 'AIGW-Team-Marketing';   Nickname = 'aigw-team-marketing';   AddMember = $true  }
    @{ Key = 'engineering'; Display = 'AIGW-Team-Engineering'; Nickname = 'aigw-team-engineering'; AddMember = $true  }
    @{ Key = 'finance';     Display = 'AIGW-Team-Finance';     Nickname = 'aigw-team-finance';     AddMember = $false }
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  ($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Info  ($m) { Write-Host "  $m" -ForegroundColor Gray }
function Write-Ok    ($m) { Write-Host "  $m" -ForegroundColor Green }
function Write-Warn2 ($m) { Write-Host "  $m" -ForegroundColor Yellow }

function Assert-Tooling {
    foreach ($tool in 'az', 'terraform') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "'$tool' is not on PATH. Install it before running this script."
        }
    }
}

function Invoke-Az {
    # Wrapper that runs az, throws on failure, returns stdout trimmed.
    param([Parameter(Mandatory)][string[]]$AzArgs)
    $out = az @AzArgs 2>$null
    if ($LASTEXITCODE -ne 0) { throw "az $($AzArgs -join ' ') failed (exit $LASTEXITCODE)." }
    return ($out | Out-String).Trim()
}

function Get-GraphHeaders {
    $token = Invoke-Az @('account', 'get-access-token', '--resource', 'https://graph.microsoft.com/', '--query', 'accessToken', '-o', 'tsv')
    return @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
}

function Select-Tenant {
    if ($TenantId) { return $TenantId }
    Write-Step 'Select tenant'
    $tenants = Invoke-Az @('account', 'list', '--query', '[].{name:name, tenantId:tenantId}', '-o', 'json') | ConvertFrom-Json
    $tenants = $tenants | Sort-Object tenantId -Unique
    if (-not $tenants) { throw 'No tenants found. Run "az login" first.' }
    for ($i = 0; $i -lt $tenants.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f $i, $tenants[$i].tenantId, $tenants[$i].name)
    }
    $sel = Read-Host 'Choose tenant number (or paste a tenant id)'
    if ($sel -match '^[0-9]+$' -and [int]$sel -lt $tenants.Count) { return $tenants[[int]$sel].tenantId }
    return $sel
}

function Select-Subscription {
    param([string]$Tenant)
    if ($SubscriptionId) { return $SubscriptionId }
    Write-Step 'Select subscription'
    $subs = Invoke-Az @('account', 'list', '--query', "[?tenantId=='$Tenant'].{name:name, id:id}", '-o', 'json') | ConvertFrom-Json
    if (-not $subs) {
        Write-Warn2 'No cached subscriptions for that tenant. Signing in...'
        az login --tenant $Tenant --only-show-errors | Out-Null
        $subs = Invoke-Az @('account', 'list', '--query', "[?tenantId=='$Tenant'].{name:name, id:id}", '-o', 'json') | ConvertFrom-Json
    }
    if (-not $subs) { throw 'No subscriptions available in that tenant.' }
    for ($i = 0; $i -lt $subs.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f $i, $subs[$i].id, $subs[$i].name)
    }
    $sel = Read-Host 'Choose subscription number (or paste a subscription id)'
    if ($sel -match '^[0-9]+$' -and [int]$sel -lt $subs.Count) { return $subs[[int]$sel].id }
    return $sel
}

function Connect-Context {
    param([string]$Tenant, [string]$Subscription)
    Write-Step 'Signing in / selecting subscription'
    $acct = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $acct -or $acct.tenantId -ne $Tenant) {
        az login --tenant $Tenant --only-show-errors | Out-Null
    }
    az account set --subscription $Subscription | Out-Null
    $acct = Invoke-Az @('account', 'show', '-o', 'json') | ConvertFrom-Json
    Write-Ok ("Signed in as {0} on sub {1}" -f $acct.user.name, $acct.name)
}

function Get-OrCreateGroup {
    param([hashtable]$G)
    $existing = Invoke-Az @('ad', 'group', 'list', '--filter', "displayName eq '$($G.Display)'", '--query', '[0].id', '-o', 'tsv')
    if ($existing) {
        Write-Info "Group '$($G.Display)' already exists ($existing)"
        return @{ Id = $existing; Created = $false }
    }
    $id = Invoke-Az @('ad', 'group', 'create', '--display-name', $G.Display, '--mail-nickname', $G.Nickname, '--query', 'id', '-o', 'tsv')
    Write-Ok "Created group '$($G.Display)' ($id)"
    return @{ Id = $id; Created = $true }
}

function Add-SelfToGroup {
    param([string]$GroupId, [string]$MeId)
    $isMember = Invoke-Az @('ad', 'group', 'member', 'check', '--group', $GroupId, '--member-id', $MeId, '--query', 'value', '-o', 'tsv')
    if ($isMember -eq 'true') { return }
    try { az ad group member add --group $GroupId --member-id $MeId --only-show-errors | Out-Null }
    catch { Write-Warn2 "Could not add self to group $GroupId ($_)" }
}

function Get-OrCreateApp {
    # Returns @{ AppId; ObjectId; ScopeId; Created }
    $headers = Get-GraphHeaders
    $existingId = Invoke-Az @('ad', 'app', 'list', '--filter', "displayName eq '$AppDisplay'", '--query', '[0].appId', '-o', 'tsv')

    if ($existingId) {
        $obj = Invoke-Az @('ad', 'app', 'show', '--id', $existingId, '-o', 'json') | ConvertFrom-Json
        $scope = $obj.api.oauth2PermissionScopes | Where-Object { $_.value -eq 'access_as_user' } | Select-Object -First 1
        $scopeId = if ($scope) { $scope.id } else { [guid]::NewGuid().ToString() }
        Write-Info "App '$AppDisplay' already exists ($existingId)"
        Set-AppConfiguration -ObjectId $obj.id -AppId $existingId -ScopeId $scopeId -Headers $headers -HasScope:([bool]$scope)
        Ensure-ServicePrincipal -AppId $existingId
        return @{ AppId = $existingId; ObjectId = $obj.id; ScopeId = $scopeId; Created = $false }
    }

    $app = Invoke-Az @('ad', 'app', 'create', '--display-name', $AppDisplay, '--sign-in-audience', 'AzureADMyOrg', '-o', 'json') | ConvertFrom-Json
    Write-Ok "Created app '$AppDisplay' ($($app.appId))"
    $scopeId = [guid]::NewGuid().ToString()
    Set-AppConfiguration -ObjectId $app.id -AppId $app.appId -ScopeId $scopeId -Headers $headers -HasScope:$false
    Ensure-ServicePrincipal -AppId $app.appId
    return @{ AppId = $app.appId; ObjectId = $app.id; ScopeId = $scopeId; Created = $true }
}

function Set-AppConfiguration {
    param(
        [string]$ObjectId, [string]$AppId, [string]$ScopeId,
        [hashtable]$Headers, [bool]$HasScope
    )
    # PATCH 1: identifier URI + access_as_user scope + token v2 + group claims
    $patch1 = @{
        identifierUris        = @("api://$AppId")
        groupMembershipClaims = 'SecurityGroup'
        api                   = @{ requestedAccessTokenVersion = 2 }
    }
    if (-not $HasScope) {
        $patch1.api.oauth2PermissionScopes = @(@{
                id                      = $ScopeId
                value                   = 'access_as_user'
                type                    = 'User'
                isEnabled               = $true
                adminConsentDisplayName = 'Access the Enterprise AI Gateway'
                adminConsentDescription = 'Allow the application to access the Enterprise AI Gateway on behalf of the signed-in user.'
                userConsentDisplayName  = 'Access the Enterprise AI Gateway'
                userConsentDescription  = 'Allow this application to access the Enterprise AI Gateway on your behalf.'
            })
    }
    Invoke-RestMethod -Method Patch -Uri "$GraphBase/applications/$ObjectId" -Headers $Headers -Body ($patch1 | ConvertTo-Json -Depth 10) | Out-Null

    # PATCH 2: pre-authorize Azure CLI for the scope (separate call required)
    $patch2 = @{ api = @{ preAuthorizedApplications = @(@{ appId = $CliAppId; delegatedPermissionIds = @($ScopeId) }) } }
    Invoke-RestMethod -Method Patch -Uri "$GraphBase/applications/$ObjectId" -Headers $Headers -Body ($patch2 | ConvertTo-Json -Depth 10) | Out-Null
    Write-Ok 'Configured identifier URI, access_as_user scope, token v2, group claims, CLI pre-auth'
}

function Ensure-ServicePrincipal {
    param([string]$AppId)
    $sp = Invoke-Az @('ad', 'sp', 'list', '--filter', "appId eq '$AppId'", '--query', '[0].id', '-o', 'tsv')
    if ($sp) { return }
    try { az ad sp create --id $AppId --only-show-errors | Out-Null; Write-Ok 'Created service principal' }
    catch { Write-Warn2 "Service principal create skipped ($_)" }
}

function Write-Tfvars {
    param([hashtable]$State)
    $anthropic = if ($AnthropicApiKey) { $AnthropicApiKey } else { 'placeholder-anthropic-key' }
    $bedrock   = if ($BedrockBearerToken) { $BedrockBearerToken } else { 'placeholder-bedrock-token' }
    $ipFilter  = $EnablePrivateIpFilter.IsPresent.ToString().ToLower()

    $content = @"
location  = "$Location"
apim_name = "$($State.ApimName)"
apim_sku  = "$ApimSku"

enable_private_ip_filter = $ipFilter

entra_tenant_id           = "$($State.TenantId)"
aigw_client_app_id        = "$($State.AppId)"
aigw_caller_client_app_id = "$CliAppId"
aigw_audience             = "api://$($State.AppId)"
group_team_marketing      = "$($State.Groups.marketing)"
group_team_engineering    = "$($State.Groups.engineering)"
group_team_finance        = "$($State.Groups.finance)"

# Vendor secrets (override with real values via TF_VAR_* env vars in production)
anthropic_api_key    = "$anthropic"
bedrock_bearer_token = "$bedrock"

aws_region              = "us-east-1"
vertex_region           = "us-central1"
vertex_token_broker_url = "https://placeholder.invalid/vertex-token"
"@
    Set-Content -Path $TfvarsPath -Value $content -NoNewline
    Write-Ok "Wrote $TfvarsPath"
}

function Update-DemoScripts {
    param([hashtable]$State)
    $gateway = "https://$($State.ApimName).azure-api.net"
    $map = @{
        '(\$gateway\s*=\s*")[^"]*(")' = "`${1}$gateway`${2}"
        '(\$tenant\s*=\s*")[^"]*(")'  = "`${1}$($State.TenantId)`${2}"
        '(\$appId\s*=\s*")[^"]*(")'   = "`${1}$($State.AppId)`${2}"
        '(\$subId\s*=\s*")[^"]*(")'   = "`${1}$($State.SubscriptionId)`${2}"
        '(\$apim\s*=\s*")[^"]*(")'    = "`${1}$($State.ApimName)`${2}"
        '(\$rg\s*=\s*")[^"]*(")'      = "`${1}$ResourceGroupName`${2}"
    }
    Get-ChildItem (Join-Path $RepoRoot 'demo') -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
        $c = Get-Content $_.FullName -Raw
        $orig = $c
        foreach ($pat in $map.Keys) { $c = [regex]::Replace($c, $pat, $map[$pat]) }
        if ($c -ne $orig) { Set-Content $_.FullName -Value $c -NoNewline; Write-Info "updated demo\$($_.Name)" }
    }
}

function Save-Manifest {
    param([hashtable]$State)
    ($State | ConvertTo-Json -Depth 6) | Set-Content -Path $ManifestPath -NoNewline
    Write-Info "Recorded lab state in $ManifestPath"
}

function Load-Manifest {
    if (Test-Path $ManifestPath) { return (Get-Content $ManifestPath -Raw | ConvertFrom-Json) }
    return $null
}

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
function Invoke-Deploy {
    $tenant = Select-Tenant
    $sub    = Select-Subscription -Tenant $tenant
    if (-not $ApimName) {
        $script:ApimName = "apim-aigw-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    }

    Write-Step 'Deployment plan'
    Write-Host "  Tenant          : $tenant"
    Write-Host "  Subscription    : $sub"
    Write-Host "  Resource group  : $ResourceGroupName"
    Write-Host "  Location        : $Location"
    Write-Host "  APIM name       : $ApimName  ($ApimSku)"
    Write-Host "  Private IP filt : $($EnablePrivateIpFilter.IsPresent)"
    Write-Host "  Entra app       : $AppDisplay (+ SP)"
    Write-Host "  Security groups : $(( $Groups | ForEach-Object { $_.Display }) -join ', ')"
    if (-not $Force) {
        if ((Read-Host "`nProceed with deploy? (y/N)") -ne 'y') { Write-Warn2 'Aborted.'; return }
    }

    Connect-Context -Tenant $tenant -Subscription $sub

    Write-Step 'Entra ID objects'
    $meId = Invoke-Az @('ad', 'signed-in-user', 'show', '--query', 'id', '-o', 'tsv')
    $groupState = @{}
    $groupCreated = @{}
    foreach ($g in $Groups) {
        $res = Get-OrCreateGroup -G $g
        $groupState[$g.Key]   = $res.Id
        $groupCreated[$g.Key] = $res.Created
        if ($g.AddMember) { Add-SelfToGroup -GroupId $res.Id -MeId $meId }
    }
    $app = Get-OrCreateApp

    $state = @{
        SchemaVersion  = 1
        TenantId       = $tenant
        SubscriptionId = $sub
        ResourceGroup  = $ResourceGroupName
        Location       = $Location
        ApimName       = $ApimName
        ApimSku        = $ApimSku
        AppId          = $app.AppId
        AppObjectId    = $app.ObjectId
        AppCreated     = $app.Created
        Groups         = $groupState
        GroupsCreated  = $groupCreated
    }

    Write-Step 'Terraform apply'
    Write-Tfvars -State $state
    Save-Manifest -State $state   # save before apply so a failed apply is still cleanable
    Update-DemoScripts -State $state

    Push-Location $InfraDir
    try {
        terraform init -input=false | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'terraform init failed.' }
        terraform apply -auto-approve -input=false | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'terraform apply failed.' }
        $gwUrl = (terraform output -raw apim_gateway_url 2>$null)
    }
    finally { Pop-Location }

    Write-Step 'Done'
    Write-Ok "Gateway URL : $gwUrl"
    Write-Host ''
    Write-Host 'Next steps:' -ForegroundColor Cyan
    Write-Host "  1) az login --tenant $tenant --scope `"api://$($app.AppId)/access_as_user`"" -ForegroundColor Yellow
    Write-Host "  2) cd demo ; .\D1-keyless-access.ps1" -ForegroundColor Yellow
    Write-Host ''
    Write-Info "State saved to $ManifestPath (used by 'destroy')."
}

# ---------------------------------------------------------------------------
# Destroy
# ---------------------------------------------------------------------------
function Invoke-Destroy {
    $m = Load-Manifest
    if ($m) {
        $tenant = if ($TenantId) { $TenantId } else { $m.TenantId }
        $sub    = if ($SubscriptionId) { $SubscriptionId } else { $m.SubscriptionId }
        $apim   = $m.ApimName
        $rg     = if ($m.ResourceGroup) { $m.ResourceGroup } else { $ResourceGroupName }
    }
    else {
        Write-Warn2 "No $ManifestPath found - discovering objects by name."
        $tenant = Select-Tenant
        $sub    = Select-Subscription -Tenant $tenant
        $apim   = $ApimName
        $rg     = $ResourceGroupName
    }

    # Connect first so the plan can list the exact resources that will be deleted.
    Connect-Context -Tenant $tenant -Subscription $sub
    $subName = Invoke-Az @('account', 'show', '--query', 'name', '-o', 'tsv')

    # Resolve the Azure resources living in the group.
    $rgExists  = (Invoke-Az @('group', 'exists', '--name', $rg)) -eq 'true'
    $resources = @()
    if ($rgExists) {
        $resources = Invoke-Az @('resource', 'list', '-g', $rg, '--query', '[].{name:name,type:type}', '-o', 'json') | ConvertFrom-Json
        if (-not $apim) {
            $apim = ($resources | Where-Object { $_.type -eq 'Microsoft.ApiManagement/service' } | Select-Object -First 1).name
        }
    }

    # Resolve the Entra objects (reused later for the actual deletes).
    $appId = if ($m -and $m.AppId) { $m.AppId } else {
        Invoke-Az @('ad', 'app', 'list', '--filter', "displayName eq '$AppDisplay'", '--query', '[0].appId', '-o', 'tsv')
    }
    $groupIds = @{}
    foreach ($g in $Groups) {
        $gid = if ($m -and $m.Groups.$($g.Key)) { $m.Groups.$($g.Key) } else {
            Invoke-Az @('ad', 'group', 'list', '--filter', "displayName eq '$($g.Display)'", '--query', '[0].id', '-o', 'tsv')
        }
        $groupIds[$g.Key] = $gid
    }

    # ---- Plan ----
    Write-Step 'Destroy plan'
    Write-Host 'Context - NOT deleted:' -ForegroundColor DarkCyan
    Write-Host "  Tenant          : $tenant"
    Write-Host "  Subscription    : $subName ($sub)"

    Write-Host ''
    Write-Host 'Azure resources that WILL be deleted:' -ForegroundColor Yellow
    if ($rgExists) {
        Write-Host "  Resource group  : $rg  (and the resource group itself)" -ForegroundColor Yellow
        if ($apim) { Write-Host "  APIM instance   : $apim" }
        if ($resources.Count -gt 0) {
            Write-Host "  Resources ($($resources.Count)):"
            $resources | Sort-Object type, name | ForEach-Object {
                Write-Host ("    - {0,-52} {1}" -f $_.type, $_.name)
            }
        }
        else { Write-Host '  (resource group is currently empty)' }
    }
    else {
        Write-Host "  Resource group '$rg' not found - nothing to delete in Azure." -ForegroundColor DarkGray
    }

    Write-Host ''
    if ($KeepEntra) {
        Write-Host 'Entra ID objects: KEPT (-KeepEntra) - nothing deleted here.' -ForegroundColor DarkCyan
    }
    else {
        Write-Host 'Entra ID objects that WILL be deleted:' -ForegroundColor Yellow
        if ($appId) { Write-Host "  - App registration '$AppDisplay' ($appId) + its service principal" }
        else { Write-Host "  - App registration '$AppDisplay' (not found)" -ForegroundColor DarkGray }
        foreach ($g in $Groups) {
            if ($groupIds[$g.Key]) { Write-Host "  - Security group $($g.Display) ($($groupIds[$g.Key]))" }
            else { Write-Host "  - Security group $($g.Display) (not found)" -ForegroundColor DarkGray }
        }
        Write-Host '  (group memberships are removed with the groups; user accounts are not touched)' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Warn2 'The tenant and subscription above are NOT deleted - only the resources listed are removed.'
    if (-not $Force) {
        $confirm = Read-Host "`nType 'destroy' to confirm"
        if ($confirm -ne 'destroy') { Write-Warn2 'Aborted.'; return }
    }

    # 1) Terraform destroy (RG + all Azure resources)
    Write-Step 'Terraform destroy'
    if (Test-Path (Join-Path $InfraDir 'terraform.tfstate')) {
        Push-Location $InfraDir
        try {
            terraform destroy -auto-approve -input=false | Out-Host
            if ($LASTEXITCODE -ne 0) { Write-Warn2 'terraform destroy reported errors - continuing with Entra cleanup.' }
        }
        finally { Pop-Location }
    }
    else {
        Write-Warn2 'No terraform.tfstate found - skipping Terraform destroy.'
    }

    # 2) Delete the app registration (also removes its service principal)
    Write-Step 'Entra cleanup'
    if ($KeepEntra) {
        Write-Info 'Skipping Entra cleanup (-KeepEntra): app registration and groups are preserved.'
        Write-Step 'Destroy complete'
        Write-Ok 'Terraform stack removed. Entra objects kept.'
        return
    }
    if ($appId) {
        try {
            az ad app delete --id $appId --only-show-errors | Out-Null
            Write-Ok "Deleted app registration $appId (and its service principal)"
        }
        catch { Write-Warn2 "Could not delete app $appId ($_)" }
    }
    else { Write-Info 'No app registration found to delete.' }

    # 3) Delete the three security groups
    foreach ($g in $Groups) {
        $gid = $groupIds[$g.Key]
        if ($gid) {
            try { az ad group delete --group $gid --only-show-errors | Out-Null; Write-Ok "Deleted group $($g.Display)" }
            catch { Write-Warn2 "Could not delete group $($g.Display) ($_)" }
        }
        else { Write-Info "Group $($g.Display) not found." }
    }

    # 4) Remove the manifest
    if (Test-Path $ManifestPath) { Remove-Item $ManifestPath -Force; Write-Info "Removed $ManifestPath" }

    Write-Step 'Destroy complete'
    Write-Ok 'Terraform stack and Entra objects removed.'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if ($Help -or ($Rest | Where-Object { $_ -match '^(--?help|-h|/\?|help)$' })) {
    Get-Help $PSCommandPath -Full
    return
}

Assert-Tooling

if (-not $Action) {
    Write-Host 'What would you like to do?' -ForegroundColor Cyan
    Write-Host '  [1] create   - create the resources + complete lab'
    Write-Host '  [2] destroy  - tear everything down (Azure + Entra)'
    $c = Read-Host 'Choose (create/destroy)'
    $Action = switch ($c.Trim().ToLower()) {
        '1'       { 'deploy' }
        'create'  { 'deploy' }
        'deploy'  { 'deploy' }
        '2'       { 'destroy' }
        'destroy' { 'destroy' }
        default   { throw "Unknown choice '$c'. Expected create or destroy." }
    }
}

if ($Action -eq 'create') { $Action = 'deploy' }

switch ($Action) {
    'deploy'  { Invoke-Deploy }
    'destroy' { Invoke-Destroy }
}
