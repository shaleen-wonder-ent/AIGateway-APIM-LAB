# Enterprise AI Gateway on Azure API Management — Solution Overview

*A single, governed front door for all enterprise AI.*

---

## The story

Enterprises are adopting AI fast — many teams, many model vendors (Microsoft Foundry /
Azure OpenAI, Anthropic, AWS Bedrock, Google Vertex). But without a control point, every
team wires models **directly**, and the problems pile up:

- **Keys everywhere** — model API keys copied into apps, laptops, and config files.
- **Runaway spend** — no per‑team budget; one workload can burn the whole quota.
- **No revocation** — access is tied to long‑lived keys that outlive employees and projects.
- **Inconsistent safety** — each app writes its own guardrails, if any.
- **No chargeback** — finance can't tell which team spent what.
- **Vendor sprawl** — four vendors, four SDKs, four auth models, four request formats.

The result is **ungoverned, risky, and expensive** AI adoption.

---

## Why an AI Gateway — and why Azure API Management

Put **one governed front door** between your apps and every AI model. Instead of each app
holding keys and rules, they all call a single endpoint that enforces policy centrally.

**Azure API Management (APIM)** is the natural choice:

- It's a **mature, enterprise‑grade gateway** you may already use for your APIs.
- It adds **identity, quotas, safety, and observability** to AI **without custom middleware**.
- It works across **every model vendor** — apps don't change code per vendor.
- Policy changes are made **once, at the edge**, and every app inherits them instantly.

---

## What we are doing

Apps call **one Entra‑authenticated, key‑less endpoint**. For every request, APIM:

1. **Verifies the user** (Microsoft Entra identity + team membership).
2. **Enforces the team's limits** (tokens, requests, daily budget).
3. **Screens content** (harmful content + prompt‑injection shield).
4. **Injects the vendor key** from secure storage — the app never sees it.
5. **Translates the request** to each vendor's format (same request shape for all).
6. **Records usage** (team, cost center, tokens) for chargeback and audit.

```text
   Apps (Entra identity, team key, NO model key)
                     │
                     ▼
     ┌──────────────────────────────────────┐
     │   Azure API Management — AI Gateway   │
     │  identity · quotas · content safety   │
     │  key injection · translation · audit  │
     └──────────────────────────────────────┘
                     │  (managed identity / stored vendor keys)
                     ▼
     Foundry (GPT‑4o) · Anthropic · Bedrock · Vertex
```

---

## How APIM helps — problem → capability

| Business problem | How the AI Gateway solves it |
|---|---|
| Keys on laptops and in code | Apps hold **no model key**; APIM injects it (managed identity / secure named values) |
| Access never revoked | Access is an **Entra token + team membership** — leaving a team revokes it on the next token |
| Runaway spend | **Per‑team token, request, and daily quotas**; over‑limit returns `429` |
| One team spending another's budget | **Team key + identity must agree**, or the request is refused |
| Inconsistent, missing safety | **One shared content‑safety + jailbreak policy** applied to every vendor |
| No cost attribution | Every call **tagged with team + cost center**; feeds chargeback and audit |
| Vendor sprawl | **One request shape**; APIM translates per vendor and manages each vendor's key |
| Inconsistent AI behavior | **Enterprise system prompt injected centrally** on every request |
| Public exposure of models | **Private ingress + identity + subscription** required — never the raw model API |

---

## Demo line‑up

| # | Demo | In one line |
|---|---|---|
| 1 | **Keyless access** | Apps use GPT‑4o with their Entra identity and **no model key** — the gateway holds the credential. |
| 2 | **Cross‑team authorization** | A team's subscription works **only** for members of that team; using another team's plan is refused. |
| 3 | **Per‑team spend limits** | Each team has an enforced token budget; exceeding it returns `429`, protecting spend and the shared model. |
| 4 | **Content safety & jailbreak shield** | One shared policy screens every vendor; harmful and prompt‑injection requests are blocked **before** the model. |
| 5 | **Chargeback & audit** | Every call is tagged with team and cost center, so finance can attribute **spend** and security can audit every **attempt**. |
| 6 | **Multi‑vendor** | The **same** request works against Anthropic (or Bedrock/Vertex) — the gateway injects the vendor key and translates the payload; no app change. |
| 7 | **Enterprise system‑prompt injection** | The gateway enforces company rules (on‑brand, no legal advice, no competitors) on **every** request, centrally. |

> Operational note: the gateway is reached privately in production (VNet/VPN). For a
> portable laptop demo we temporarily open public access, then restore private‑only.

---

## The bottom line

> **One key‑less, governed endpoint for all AI — secure, cost‑controlled, compliant, and
> vendor‑agnostic — with no app rewrites.**

Set the policy once at the gateway, and every app and every model vendor inherits it
instantly. Apps stay simple; the enterprise stays in control.
