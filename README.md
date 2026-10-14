# FlowProof AI

**Understand why your Salesforce automation didn't behave as expected.**

FlowProof AI is a Salesforce-native troubleshooting app for admins and developers. Pick a record, pick the automation you expected to fire, and click **Investigate**. FlowProof inspects the automation's metadata and the record's values, evaluates supported conditions deterministically, and explains what the evidence does and does not show. Optionally, Google Gemini rewrites the findings in plain language.

## Core principle: evidence, not guesses

FlowProof never presents a possible cause as a confirmed root cause. Every conclusion carries one of these labels:

| Label                     | Meaning                                                                                    |
| ------------------------- | ------------------------------------------------------------------------------------------ |
| **Confirmed by evidence** | Directly shown by retrieved metadata, logs, or records                                     |
| **Supported hypothesis**  | Consistent with the evidence, but not proven (e.g. current values fail an entry condition) |
| **Insufficient evidence** | The data needed to decide isn't available                                                  |
| **Unsupported analysis**  | The construct (formula, relationship path, etc.) is outside what FlowProof can evaluate    |

Current record values are not necessarily the values present when a Flow ran. A condition that fails today does not prove the Flow failed to run historically.

## Status

| Area                                                         | Status      |
| ------------------------------------------------------------ | ----------- |
| Phase 0 — Environment setup                                  | In progress |
| Phase 1 — Architecture                                       | Planned     |
| Phases 2–7 — Foundation, engine, Gemini, MVP, testing, CI/CD | Planned     |

See [ROADMAP.md](ROADMAP.md) for the backlog.

## Documentation

- [SETUP.md](SETUP.md): tools, org connection, Claude Code skills and MCP
- [DEVELOPMENT.md](DEVELOPMENT.md): branching, commands, tests, deploy rules
- [ARCHITECTURE.md](ARCHITECTURE.md): components, data model, metadata access, AI integration
- [SECURITY.md](SECURITY.md): secrets, CRUD/FLS, AI data minimization
- [ROADMAP.md](ROADMAP.md): phases and backlog

## Tech stack

Salesforce DX (source format, API 68.0) · Apex · Lightning Web Components (SLDS) · Custom Metadata Types · Named/External Credentials · Google Gemini API (optional) · Jest · Salesforce Code Analyzer · GitHub Actions
