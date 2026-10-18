# Roadmap

## Phase 0 — Environment setup

- [x] Salesforce DX project (`flowproof-ai`, API 68.0), Git on `main`
- [x] Salesforce skills installed for Claude Code (31 skills, pinned in `skills-lock.json`)
- [x] Salesforce DX MCP configured (`@salesforce/mcp@0.30.15`, locked to `flowproof-dev`)
- [x] `flowproof-dev` Developer Edition org authenticated (org 00Dbm000014j2CXEAY, API 68.0)
- [x] MCP server verified against the org (handshake, 41 GA tools, read-only SOQL)
- [ ] GitHub private repo created and pushed (owner does this in the GitHub UI)

## Phase 1 — Architecture

- [x] ARCHITECTURE.md: layers, data model, security, metadata access, AI integration, testing (proposed)
- [x] Flow metadata access: Tooling API via the per-user `FlowProof_Org_API` named credential (option A), verified end to end from Apex

## Phase 2 — Application foundation

- [x] Custom objects: Investigation, Finding (evidence kept in Result_JSON__c)
- [x] Custom Metadata: FlowProof_Setting__mdt (AI off by default, model)
- [x] Permission sets: FlowProof User, FlowProof Admin (tested with the real set)
- [x] Lightning app: New investigation, Results, History, Settings (38 Jest tests)

## Phase 3 — Investigation engine (works without AI)

- [x] Flow metadata service: catalog (FlowDefinitionView: activation, trigger object/type/order) + Tooling API source for entry conditions (tested, mocked callouts)
- [x] Record service: user-mode field retrieval and inaccessible-field reporting (tested with a Minimum Access user)
- [x] Condition evaluator, MVP operators: EqualTo, NotEqualTo, GreaterThan, LessThan, GreaterThanOrEqualTo, LessThanOrEqualTo, IsNull; AND / OR logic (tested, 74 tests)
- [x] Explicit _Unsupported_ results for formulas, custom logic, relationships, and other operators
- [x] Flow metadata parser (Tooling `Flow.Metadata` JSON), tested against real metadata from the org
- [x] Findings with evidence categories, plus recommended next steps (diagnostic engine + investigation service, tested)

## Phase 4 — Gemini integration (optional layer)

- [x] `Gemini_API` External Credential + Named Credential, principal access in the FlowProof permission sets
- [x] Prompt builder with record values hidden by default, structured JSON response, grounding of key points
- [x] Callout mocks; failure modes: bad key, 403, 404 model, 429, 5xx, blocked, cut off, malformed response, unreachable credential
- [x] Results screen "Explain with Gemini" / Regenerate; Settings "Test Gemini connection"
- [x] Manual: admin stores the API key in Setup and turns AI on (see SETUP.md §8). Verified 2026-10-17: connection test Connected; a real explanation of INV-0009 cited only FlowProof findings (C1–C3, CONDITIONS_NOT_MET, EXECUTION_NOT_CONFIRMED) with record values hidden

## Phase 4b — Check all Flows and Flow health

- [x] "All Flows on this object" in New investigation: every record-triggered Flow checked against one record, with Investigate per Flow
- [x] Flow health checks on full metadata (7 rules, suggest-only), shown on Results and summarized per Flow in Check all Flows

## Phase 4c — Record pages, what-if and packaging

- [x] `flowProofRecordCheck`: Automation check on record pages and as a quick action (demo: Opportunity **Check automation**)
- [x] What-if: simulate field values and re-check every Flow; nothing is saved
- [x] `org-config` made org-independent (`FLOWPROOF_ORG_URL` replacement)
- [x] Unlocked package **FlowProof AI** (0Ho…WkHCAU): version 0.1.0-1 built (04tbm000000qKM1AAM, 95% coverage)
- [x] Record a test save: debug log of a real save shows which Flows ran, what they did, and which did not start (verified on flowproof-dev 2026-10-18)
- [ ] Promote a version so it can be installed in production and Developer Edition orgs (beta versions install only in sandboxes and scratch orgs)

## Phase 5 — MVP demo

- [x] Demo Flow `Opportunity_Onboarding` (Closed Won → Task) plus synthetic Opportunities: deployed and verified (Globex gets a Task, Acme does not)
- [x] End-to-end investigation against real org metadata: deployed (0Afbm00000jh49jCAA) and verified on Acme (conditions not met: Region blank) and Globex (conditions met)

## Phase 6 — Quality

- [ ] Apex tests for all branches listed in the brief
- [ ] Jest tests for every LWC
- [ ] Code Analyzer clean of material issues
- [ ] Triage npm dev-dependency advisories (44 in the template toolchain)

## Phase 7 — CI/CD

- [ ] GitHub Actions: lint, Jest, Code Analyzer, deploy validation, and Apex tests against an authorized validation org

## Phase 8 — Future (after MVP)

- Automation dependency explorer (objects ↔ fields ↔ flows ↔ triggers ↔ validation rules)
- Investigation history with evidence references
- AI test-scenario recommendations
- GitHub issue / fix proposals from findings
- Automation health dashboard built from collected evidence
- AppExchange readiness: managed packaging, security review, API usage
