# Security Policy

## Supported versions

Classic Games is pre-1.0 and has no tagged releases yet. Security fixes land on the `main` branch only; there are no maintained release branches and no backports.

| Version | Supported |
|---|---|
| `main` (latest commit) | Yes |
| Any older commit or fork | No |

## Reporting a vulnerability

Please do not open a public issue, pull request or discussion for a suspected vulnerability.

Report it through GitHub private vulnerability reporting: open <https://github.com/yldm-tech/classic-games/security/advisories/new>, or go to the repository's **Security** tab and choose **Report a vulnerability**. The report is visible only to you and the maintainers.

A useful report includes:

- the affected component (`apps/client`, `apps/server`, `apps/web`, `apps/cli`, `apps/mcp`, `packages/dsl`, `packages/sdk`, `packages/schemas`) and the commit you tested;
- the steps, request, prompt or DSL document that reproduces the problem;
- what an attacker gains (data read, data changed, cost incurred, check bypassed);
- any suggested fix, if you have one.

## What to expect

Classic Games is maintained by a small team on a best-effort basis, so the windows below are targets, not guarantees.

- Acknowledgement of your report: within 7 days.
- A first assessment (accepted, need more information, or not a vulnerability): within 14 days of the acknowledgement.
- Fix timing depends on severity and complexity. We will keep you informed through the private advisory thread and agree on a disclosure date with you before publishing.

We credit reporters in the advisory unless you ask us not to. There is no bug bounty programme.

## Scope

The design rule that matters most for security is that the AI never produces executable code: a model may only emit an RFC 6902 patch against a Mod DSL document, and the server applies the patch and validates the result against the JSON Schema of the runtime before anything is stored, previewed or published. Reports that break this rule are the ones we most want to hear about.

In scope, with examples:

- **DSL and schema escape.** A prompt, a hand-written patch or a stored mod that makes the server accept, or the client load, a document that the schema in `packages/schemas` should reject; a patch that reaches outside the DSL document; differences between the Go patch implementation (`packages/dsl`) and the GDScript one (`apps/client/runtime/json_patch.gd`) that let a document pass server validation and behave differently on the client; DSL migration paths that turn a rejected document into an accepted one.
- **Prompt injection with a security effect.** Input that makes the AI pipeline skip validation, leak the system prompt together with secrets, forge or strip the AI provenance marker on a mod, or spend another user's quota.
- **Authentication and tokens.** Session and refresh token handling, guest sessions, SMS code verification and its rate limits, the OAuth verification gateways, admin identification (`CLASSIC_GAMES_ADMIN_IDS`, `CLASSIC_GAMES_DEV_ADMIN`), privilege escalation between users, and client IP spoofing through `CLASSIC_GAMES_TRUSTED_PROXIES`.
- **Payment and SMS gateways.** Webhook signature verification (`PAYMENT_WEBHOOK_SECRET`), replayed or forged payment callbacks, entitlement or points granted without payment, and abuse of the SMS sender to send messages at the operator's expense.
- **User-generated content.** Stored content (titles, descriptions, comments, messages, mod patches) that bypasses moderation, executes or injects markup in a client, or exposes another user's private data; path traversal through runtime, schema or asset identifiers.
- **Secrets and data exposure.** Any endpoint, log line, error message or client build that reveals API keys, gateway tokens, signing secrets or personal data such as phone numbers.
- **Tooling.** The `classic-games` CLI, the `classic-games-mcp` server and `packages/sdk` mishandling credentials, or an MCP tool that lets a connected model act beyond what the backend API permits for the authenticated user.

Out of scope:

- Behaviour that requires `CLASSIC_GAMES_ENV=development`, the stub AI provider, `CLASSIC_GAMES_DEV_ADMIN=true` or other development-only switches, unless it can be triggered in a production configuration.
- Vulnerabilities in third-party dependencies with no demonstrated impact on Classic Games. Report those upstream; we still welcome a note so the dependency can be updated.
- Game balance issues: a schema-valid DSL document that is unfair or unplayable is a product bug, not a vulnerability. Use a regular issue.
- Denial of service that needs volumetric traffic, and findings from automated scanners with no working reproduction.
- Deployments operated by third parties. This policy covers the code in this repository.

## Deployment notes for operators

- Set `CLASSIC_GAMES_SECRET` to at least 32 random characters. The server refuses to start in production with a shorter value.
- Keep `CLASSIC_GAMES_DEV_ADMIN=false` outside local development. The server refuses to start in production with it enabled.
- List only the real reverse proxy addresses in `CLASSIC_GAMES_TRUSTED_PROXIES`. Trusting `0.0.0.0/0` lets clients forge their source IP and bypass login and AI quota limits.
- Keep model, SMS, OAuth and payment credentials in the server environment. They must never be committed or shipped in a client build. `.env.example` lists the variable names with empty values.
