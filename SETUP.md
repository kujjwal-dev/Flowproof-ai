# Setup

## Prerequisites

| Tool           | Version verified     | Notes                                                                                    |
| -------------- | -------------------- | ---------------------------------------------------------------------------------------- |
| Node.js        | 24.12.0              |                                                                                          |
| npm            | 10.8.0               |                                                                                          |
| Git            | 2.44.0               | Git Credential Manager 2.4.1 included                                                    |
| Salesforce CLI | 2.153.5 (npm global) | See the PATH warning below                                                               |
| Java           | 17.0.12              | Needed by Code Analyzer's PMD engine                                                     |
| Python         | **not installed**    | Needed by some skill validator scripts and by the optional Salesforce Development plugin |

### Salesforce CLI PATH warning (Windows)

This machine has two `sf` installs:

- `C:\Program Files\sf\bin` — **2.56.7**, outdated, and first on PATH
- `%APPDATA%\npm` — **2.153.5**, current

Until the old one is removed, `sf` in a new terminal runs 2.56.7. Fix it with one of:

- Uninstall "Salesforce CLI" from _Settings → Apps_ (keeps the npm one), or
- Run `sf update` from an elevated terminal, or
- Move `%APPDATA%\npm` above `C:\Program Files\sf\bin` in your user PATH.

## 1. Install project dependencies

```sh
npm install
```

## 2. Connect the Developer Edition org

The project targets one org, aliased `flowproof-dev`:

```sh
sf org login web --alias flowproof-dev --set-default --instance-url https://login.salesforce.com
sf org display --target-org flowproof-dev
```

`--set-default` writes the default to `.sf/config.json` inside this project only (gitignored).

## 3. Claude Code: Salesforce skills

Skills come from [forcedotcom/sf-skills](https://github.com/forcedotcom/sf-skills) and install into `.claude/skills/`, which is gitignored. `skills-lock.json` records the set and the content hashes. To restore after cloning:

```sh
npm run skills:install
```

Don't use `npx skills experimental_install`. It restores into `.agents/skills/`, which Claude Code doesn't read.

The installed skills cover Apex, Apex tests, SOQL, Flow, LWC, SLDS, custom objects and fields, Custom Metadata Types, permission sets, Named Credentials, metadata deploy/retrieve, Code Analyzer, and official docs lookup.

## 4. Claude Code: Salesforce DX MCP server

`.mcp.json` configures `@salesforce/mcp`, locked to `flowproof-dev` with the toolsets `orgs,metadata,data,testing,lwc-experts,code-analysis`. Only GA tools are enabled (no `--allow-non-ga-tools`).

> **End of life:** `@salesforce/mcp` reaches end of life on **2026-11-02** ([forcedotcom/mcp#46](https://github.com/forcedotcom/mcp/issues/46)). Salesforce's stated replacement is sf-skills. The config pins the final release, `0.30.15`, which stays installable after EOL. The Salesforce CLI and skills are this project's primary toolchain; MCP is a convenience.

On native Windows, Claude Code launches `npx`-based stdio servers through `cmd /c`; the config already does this. On macOS or Linux, change `"command"` to `"npx"` and drop the `"/c", "npx"` args.

When Claude Code first opens the project it asks you to approve the project MCP server.

## 5. Claude Code: project permission guard

`.claude/settings.json` forces a confirmation prompt before any deploy, destructive org command, data write, anonymous Apex, or `git push`, even in auto mode.

## 6. Org API credential (`FlowProof_Org_API`)

FlowProof reads Flow entry conditions through the org's own Tooling API. Apex can't use the Lightning session for API calls, so it calls back into the org through a Named Credential. That Named Credential uses **per-user OAuth**: each user authorizes once, and every call runs with that user's own permissions.

Steps verified against Salesforce Help (Winter '27) on 2026-10-15. Labels marked † weren't confirmed word-for-word, so look for the closest match.

`<MD>` is the org's My Domain URL. For `flowproof-dev` it is `https://orgfarm-9ef46cef41-dev-ed.develop.my.salesforce.com`. Use this same host everywhere below.

**A. External Auth Identity Provider** (created first so Salesforce generates the callback URL)

1. Setup → Quick Find **Named Credentials** → **External Auth Identity Providers** tab → **New**.
2. Label `FlowProof Org IdP`, Name `FlowProof_Org_IdP`.
   - Authentication Protocol **OAuth 2.0**.
   - Authentication Flow Type **Authorization Code (Browser Flow)**.
3. Client ID and Client Secret: type `tbd` for now.
   - Authorize Endpoint URL `<MD>/services/oauth2/authorize`.
   - Token Endpoint URL `<MD>/services/oauth2/token`.
   - User Info Endpoint URL `<MD>/services/oauth2/userinfo`.
4. Tick **Use Proof Key for Code Exchange (PKCE) Extension** and **Pass client credentials in request body**. **Save**.
5. Copy the **Callback URL** shown on the detail page. Copy it; don't retype it.

**B. External Client App**

6. Setup → **App Manager** → **New External Client App**.
   - Name `FlowProof Org API`, your contact email.
   - Distribution State **Local**.
7. **Enable OAuth**. Callback URL = the URL from step 5. Scopes:
   - **Manage user data via APIs (api)**
   - **Perform requests at any time (refresh_token, offline_access)**
8. Security checkboxes:
   - Turn on **Require Secret for Web Server Flow**, **Require Secret for Refresh Token Flow**, and **Require PKCE**.
   - Leave refresh-token rotation, JWT access tokens, and every other flow off. **Create** / **Save**.
9. Edit the app's **Policies**:
   - Permitted Users: **All users can self-authorize**.
   - Refresh token: **valid until revoked**†.
10. Open the app's OAuth settings → **Consumer Key and Secret**† (you may be asked to verify your identity). Copy both values.
11. Go back to `FlowProof Org IdP` → **Edit**. Paste the Consumer Key as Client ID and the Consumer Secret as Client Secret → **Save**. OAuth changes can take **up to 15 minutes** to take effect.

**C. External Credential**

12. Named Credentials → **External Credentials** tab → **New**:
    - Label `FlowProof Org EC`, Name `FlowProof_Org_EC`.
    - Authentication Protocol **OAuth 2.0**, Flow Type **Browser Flow**.
    - Scope `api refresh_token`.
    - Identity Provider: **External Auth Identity Provider** → `FlowProof_Org_IdP`.
    - **Save**.
13. **Principals** → **New**: Parameter Name `PerUser`, Sequence 1, Identity Type **Per User Principal** → **Save**. The name and type can't be changed later.

**D. Named Credential**

14. **Named Credentials** tab → **New** (not "New Legacy"):
    - Label `FlowProof Org API`, Name `FlowProof_Org_API`.
    - URL `<MD>`.
    - **Enabled for Callouts** on; External Credential `FlowProof_Org_EC`; **Generate Authorization Header** on.
    - Both "Allow Formulas" options off.
    - **Save**.

**E. Permission set**

15. Setup → **Permission Sets** → **New**: Label `FlowProof Org API Access` → Save.
16. **External Credential Principal Access** → Edit → enable `FlowProof_Org_EC - PerUser` → Save.
17. **Object Settings** → **User External Credentials** → Edit → **Read, Create, Edit, Delete** → Save.
18. **Manage Assignments** → assign the set to yourself.

**F. Authorize (each user, once)**

19. Avatar → **Settings** → Quick Find **External Credentials** → `FlowProof Org EC` → **Allow Access** → log in → **Allow**. The status should change to **Configured**.

**If something goes wrong**

- `redirect_uri_mismatch`: the callback URL in step 7 must match step 5 exactly.
- Callouts fail with an access error: both step 16 and step 17 are required.
- `invalid_client` right after setup: wait 15 minutes (step 11).
- Refresh fails after the first hour: turn off **Require Secret for Refresh Token Flow** in step 8. It's unverified whether the identity provider sends the secret when refreshing.

## 7. Gemini API key (Phase 4)

Covered in Phase 4. The key will live only in a Salesforce External Credential principal. It never goes in this repo, `.env` files, or chat.

## Optional: Salesforce Development plugin for Claude Code

Salesforce's official plugin ([source](https://github.com/forcedotcom/sf-skills/tree/main/plugins/builder/salesforce-development)) is Apache-2.0 licensed and doesn't list any Salesforce edition or paid-license requirement, so it works with a Developer Edition org.

- **Adds:** an Apex/SOQL language-server MCP (diagnostics before deploy), a production deploy-safety hook, and session-start org context.
- **Requires:** Claude Code ≥ 2.1.222, Node, sf CLI, and **Python 3.8+**.
- **Overlap:** its skills duplicate the ones already in `.claude/skills/`.
- **Telemetry:** it has a telemetry hook (see `/salesforce-development:telemetry`).
- **Install:** in Claude Code, run `/plugin install salesforce-development@claude-plugins-official`.

It is optional and not required by this project.
