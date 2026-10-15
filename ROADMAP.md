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

- [ ] Custom objects: Investigation, Finding (and Evidence if justified)
- [ ] Custom Metadata: app settings (AI on/off, model, limits)
- [ ] Permission sets: FlowProof User, FlowProof Admin
- [ ] Lightning app with Dashboard, New Investigation, Results, and Settings

## Phase 3 — Investigation engine (works without AI)

- [ ] Flow metadata service: active version, trigger object/type, entry conditions
- [ ] Record service: user-mode field retrieval and inaccessible-field reporting
- [x] Condition evaluator, MVP operators: EqualTo, NotEqualTo, GreaterThan, LessThan, GreaterThanOrEqualTo, LessThanOrEqualTo, IsNull; AND / OR logic (tested, 74 tests)
- [x] Explicit _Unsupported_ results for formulas, custom logic, relationships, and other operators
- [x] Flow metadata parser (Tooling `Flow.Metadata` JSON), tested against real metadata from the org
- [ ] Findings with evidence categories, plus recommended next steps

## Phase 4 — Gemini integration (optional layer)

- [ ] `Gemini_API` External Credential + Named Credential
- [ ] Sanitizer, prompt builder, structured JSON response, validation
- [ ] Callout mocks; failure modes: timeout, 429, malformed response

## Phase 5 — MVP demo

- [x] Demo Flow `Opportunity_Onboarding` (Closed Won → Task) plus synthetic Opportunities: deployed and verified (Globex gets a Task, Acme does not)
- [ ] End-to-end investigation against real org metadata

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
