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

## 6. Gemini API key (Phase 4)

Covered in Phase 4. The key will live only in a Salesforce External Credential principal. It never goes in this repo, `.env` files, or chat.

## Optional: Salesforce Development plugin for Claude Code

Salesforce's official plugin ([source](https://github.com/forcedotcom/sf-skills/tree/main/plugins/builder/salesforce-development)) is Apache-2.0 licensed and doesn't list any Salesforce edition or paid-license requirement, so it works with a Developer Edition org.

- **Adds:** an Apex/SOQL language-server MCP (diagnostics before deploy), a production deploy-safety hook, and session-start org context.
- **Requires:** Claude Code ≥ 2.1.222, Node, sf CLI, and **Python 3.8+**.
- **Overlap:** its skills duplicate the ones already in `.claude/skills/`.
- **Telemetry:** it has a telemetry hook (see `/salesforce-development:telemetry`).
- **Install:** in Claude Code, run `/plugin install salesforce-development@claude-plugins-official`.

It is optional and not required by this project.
