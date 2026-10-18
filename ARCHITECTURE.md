# Architecture

Status: **Proposed (Phase 1)**. Facts about Salesforce and Gemini behavior were checked against official docs on 2026-10-15 and are cited in [§10](#10-verified-platform-facts). Anything not confirmed is marked _unverified_ and has a test planned.

## 1. Goals and non-goals

**Goals**

- Answer "why didn't my record-triggered Flow do what I expected?" for one record and one Flow.
- Produce deterministic, evidence-labelled findings that work without AI.
- Respect the running user's sharing, CRUD, FLS, and metadata permissions.
- Provide a clear path from a developer MVP to an installable 2GP managed package.

**Non-goals for the MVP**

- Proving historical execution. No supported API links a record-triggered Flow interview to the record that triggered it (§10.4). FlowProof says so instead of guessing.
- Formula entry conditions, custom filter logic, relationship-field conditions, `IsChanged`.
- Apex triggers, validation rules, and other automation types (Phase 8).
- Changing records, Flows, or any metadata. FlowProof is read-only toward the user's org, except for its own investigation records.

## 2. Layers

```text
LWC (flowProof*)                       UI only: input, display, loading/empty/error states
  │  @AuraEnabled
FlowProofInvestigationController       thin: validate input, call service, map errors
  │
FlowProofInvestigationService          orchestrates one investigation
  ├─ FlowProofFlowCatalogService       SOQL on FlowDefinitionView: candidate flows per object
  ├─ FlowProofFlowDefinitionSource     «interface» get the Flow's start element
  │    ├─ FlowProofToolingFlowSource   Tooling API callout (Named Credential, per-user OAuth)
  │    └─ FlowProofSnapshotFlowSource  fallback: CLI-generated snapshot (static resource)
  ├─ FlowProofFlowParser               Tooling/metadata JSON → FlowProofFlowModel (pure)
  ├─ FlowProofRecordService            user-mode SOQL for referenced fields; inaccessible-field report
  ├─ FlowProofConditionEvaluator       conditions × values → per-condition results (pure)
  ├─ FlowProofDiagnosticEngine         rules → findings with evidence categories (pure)
  └─ FlowProofResultService            persists Investigation + Findings
FlowProofAiService                     optional, separate transaction
  ├─ FlowProofAiSanitizer              data minimization (pure)
  ├─ FlowProofPromptBuilder            structured prompt + JSON schema (pure)
  └─ FlowProofGeminiClient             callout:Gemini_API, parsing, validation
```

**Design rules**

- **Pure classes take no org dependencies.** The parser, evaluator, diagnostic engine, sanitizer, and prompt builder have no SOQL, DML, or callouts, so they're unit-tested with plain inputs. That's where most of the logic and risk is.
- **Interfaces only where an implementation will change.** `FlowProofFlowDefinitionSource` has a Tooling implementation, a snapshot implementation, and a test stub. `FlowProofAiProvider` is the Gemini seam. There's no other abstraction layer, selector framework, or fflib.
- **The controller holds no logic.** It translates exceptions into `AuraHandledException` with safe messages.

## 3. Investigation flow

**Transaction 1: `runInvestigation(request)`**

1. Validate the input: the object API name exists and is accessible, the record ID is the right type, and the Flow API name exists.
2. **Catalog** (SOQL `FlowDefinitionView`): active? trigger object? trigger type (before/after save)? record trigger type (create/update)? trigger order? active version ID?
3. **Definition** (callout): Tooling `SELECT Metadata FROM Flow WHERE Id = :activeVersionId`, then parse `start`.
4. **Record**: one user-mode SOQL for exactly the fields that the conditions reference.
5. **Evaluate** each condition, then the filter logic.
6. **Diagnose**: rules produce findings, each labelled with an evidence category.
7. **Persist** the Investigation, Findings, and result snapshot. DML comes last, after every callout.
8. Return the result DTO.

Step 3 also keeps the full Flow metadata, and the **Flow health checks** (§3.3) run on it. Health findings are stored in `healthFindings`, apart from the diagnosis.

**Transaction 2 (optional): `requestAiExplanation(investigationId, regenerate)`**

1. Load the stored result in user mode. A stored explanation is returned unless `regenerate` is true.
2. Build the prompt with record values hidden (§8.2, [SECURITY.md](SECURITY.md#external-ai-google-gemini)), call Gemini, then parse and ground the answer.
3. Save the explanation in `AI_Explanation__c`, never mixed into `Result_JSON__c`.

Splitting the work into two transactions keeps the deterministic result independent of Gemini latency and failures. It also respects Apex's "no callout after uncommitted DML" rule.

### 3.1 Check all Flows: `checkAllFlows(objectApiName, recordId)`

One click checks every record-triggered Flow on the record's object. Nothing is saved; each row has **Investigate** to run and save the full investigation for that Flow.

1. Read the record once (no fields) to fail fast, before any callout, if the user can't see it.
2. List the object's record-triggered Flows, active ones first.
3. Read each Flow's definition (one callout each) and run its health checks. The run stops at 30 Flows or after 90 seconds of callouts, well inside Salesforce's 100-callout and 120-second limits; skipped Flows are listed.
4. Read the record once more, with the union of every Flow's condition fields.
5. Evaluate and diagnose each Flow against that one snapshot, and return one `FlowProofSweepRow` per Flow.

**What if** (`simulateAllFlows(objectApiName, recordId, values)`): the same check, but after the record is read, the typed-in values replace the real ones in the in-memory snapshot (`FlowProofRecordService.applyWhatIfValues`). Each value is converted to the field's type (`FlowProofWhatIfField.parse`), so it is compared exactly like a real value. The record is never updated. Only fields the checked Flows' conditions use, and that the user can read, can be simulated; the result lists the changes and is marked `simulated`.

**On record pages**, `flowProofRecordCheck` (record page component and screen quick action) runs this check for the current record when the user clicks **Check automation**, never on page load, because each check reads every Flow definition. Apex derives the object from the record Id when a quick action doesn't pass it.

### 3.2 Record a test save (`FlowProofSaveTraceService`)

Turns a guess into proof for one save. All calls go through `FlowProof_Org_API` as the user (`FlowProofToolingClient`), so only users allowed to manage debug logs can use it.

1. **Start:** create (once) the debug level `FlowProof_Trace` (Workflow FINER, Validation INFO, Database INFO, everything else NONE) and a `USER_DEBUG` trace flag on the user for 30 minutes. If the user already has an active trace flag, FlowProof switches it to its debug level and restores the old level afterwards.
2. **The user saves the record** in the normal UI. FlowProof never saves it.
3. **Read:** list the user's `ApexLog` rows since the start (newest 25). One save can write several logs (before-save, after-save, …), so FlowProof combines every log that started 5 s before to 10 s after the record's `LastModifiedDate` (when the user made that save). `FlowProofDebugLogParser` reads Flow interviews (`FLOW_CREATE_INTERVIEW_*` gives the version Id, `FLOW_VALUE_ASSIGNMENT …|$Record|{Id=…}` ties an interview to the record, `FLOW_ELEMENT_BEGIN` lists elements, `FLOW_RULE_DETAIL … true` decision outcomes, `*ERROR*`/`*FAULT*` errors, `FLOW_INTERVIEW_FINISHED`) and `VALIDATION_FAIL`/`VALIDATION_ERROR`. If nothing matches around the save time, the newest log in which a Flow ran for the record is used.
4. **Result:** Flows that ran (Ran / Failed / Started), active record-triggered Flows on the object whose version did not run ("did not start": no interview was created on that save), and failed validation rules. Then the trace flag is deleted or restored.

Only names, element names, outcomes, errors and validation messages are kept. The log also contains the record's field values (the `$Record` snapshot); FlowProof never stores or shows them. Scheduled and asynchronous paths run in later transactions and are not included.

Verified 2026-10-18 on flowproof-dev: a REST save of the demo Acme Opportunity wrote three logs over two seconds; the combined read showed Opportunity Onboarding ran and created its Task, matching the Task's creation time.

### 3.3 Flow health checks (`FlowProofFlowHealthAnalyzer`)

Best-practice checks on the full Flow metadata. They hold whichever record is saved, and they only suggest: FlowProof never changes a Flow. Each finding names the elements it's based on.

| Rule                            | Evidence             | Severity                        | Fires when                                                                                                                                          |
| ------------------------------- | -------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DATA_OPERATION_IN_LOOP`        | Confirmed            | High                            | Get/Create/Update/Delete Records is reachable from a loop's "for each" path before it returns to the loop (fault paths not followed)                |
| `SAME_RECORD_UPDATE_AFTER_SAVE` | Confirmed            | Medium                          | An after-save Flow updates `$Record`, or its own object filtered by `Id = $Record.Id`                                                               |
| `NO_ENTRY_CONDITIONS`           | Confirmed            | Medium (Low if it only assigns) | No filters and no formula; names the first Decision as a candidate entry condition                                                                  |
| `REPEATED_WORK_ON_EVERY_UPDATE` | Supported hypothesis | Medium                          | Runs on update with conditions, without "only when updated to meet" / Is Changed / `ISCHANGED` / `PRIORVALUE`, and creates records or calls actions |
| `POSSIBLE_HARDCODED_IDS`        | Supported hypothesis | Medium                          | A value (not a name, label or description) contains a 15-character Id-shaped token, or an 18-character one with a valid checksum                    |
| `MISSING_FAULT_PATHS`           | Confirmed            | Low                             | Record operations or actions have no fault connector                                                                                                |
| `TRIGGER_ORDER_NOT_SET`         | Confirmed            | Low                             | The Flow is active, has no Trigger Order, and other active Flows run at the same point (same object, before or after save)                          |

## 4. Evidence model

Every finding carries exactly one category:

| Category                | Used when                                      | Example                                                                                                                                     |
| ----------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `CONFIRMED`             | Metadata or data shows it directly             | "Flow `Opportunity_Onboarding` has no active version."                                                                                      |
| `SUPPORTED_HYPOTHESIS`  | Consistent with the evidence, not proven       | "Current Region is blank, which fails `Region = North America`. If it was blank when the record was saved, the Flow wouldn't have started." |
| `INSUFFICIENT_EVIDENCE` | The data needed is unavailable                 | "No execution history is available for record-triggered Flows."                                                                             |
| `UNSUPPORTED`           | The construct is outside the evaluator's scope | "Entry condition uses a formula; not evaluated."                                                                                            |

**Fixed rules**

- Current-value condition failures are never stronger than `SUPPORTED_HYPOTHESIS`.
- Every result includes a "Historical execution: NOT CONFIRMED" statement unless real execution evidence exists.
- When an unsupported construct can change the overall outcome, the overall result is `INDETERMINATE`, never `SATISFIED` or `NOT_SATISFIED`.

## 5. Condition evaluator (MVP scope)

**Inputs**

- `start.filters[]`: `field`, `operator`, `value`
- `start.filterLogic`
- `start.filterFormula`
- `start.doesRequireRecordChangedToMeetCriteria`
- The record's values, plus FLS status per field

**Per-condition result:** `MATCH`, `NO_MATCH`, `UNSUPPORTED`, `INACCESSIBLE` (user can't read the field), or `MISSING` (field doesn't exist).

**Overall result:** `SATISFIED`, `NOT_SATISFIED`, or `INDETERMINATE`.

| Supported in MVP                                                       | Reported as UNSUPPORTED                                                           |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `EqualTo`, `NotEqualTo`                                                | `filterFormula` (formula entry conditions)                                        |
| `GreaterThan`, `LessThan`, `GreaterThanOrEqualTo`, `LessThanOrEqualTo` | Custom logic beyond pure `and` / `or` (e.g. `1 AND (2 OR 3)`)                     |
| `IsNull` (true/false)                                                  | `IsChanged` and any prior-value reference (needs pre-save values)                 |
| `filterLogic` = `and` (or absent), `or`                                | `StartsWith`, `EndsWith`, `Contains`, and unknown operators (planned next)        |
| Value types: string, number, boolean, date, dateTime                   | Relationship fields (`Account.Industry`), `elementReference`, `formulaExpression` |

**Semantics**

- Short-circuiting doesn't hide anything: every condition is evaluated and shown.
- With `and` logic, any `NO_MATCH` gives `NOT_SATISFIED`, even if other conditions are unsupported. Otherwise, any unsupported or inaccessible condition gives `INDETERMINATE`.
- With `or` logic the reverse applies: any `MATCH` gives `SATISFIED`.
- Picklist values compare on the API value.

_Unverified_ (needs tests against the platform):

- Whether text equality in entry conditions is case-sensitive. Until it's confirmed, treat a case-only difference as `INDETERMINATE`.
- How nulls behave with `GreaterThan` and similar operators. A null compared with a number is treated as `NO_MATCH` and labelled as an assumption.

`doesRequireRecordChangedToMeetCriteria = true` ("only when a record is updated to meet the condition requirements") adds a finding. Even when current values satisfy the conditions, the Flow won't fire on a later update unless the record previously didn't meet them. This is a `SUPPORTED_HYPOTHESIS`.

## 6. Data model

| Object                                                  | Purpose                              | Key fields                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FlowProof_Investigation__c` (OWD **Private**)          | One run                              | `Target_Object__c`, `Target_Record_Id__c`, `Flow_Api_Name__c`, `Flow_Label__c`, `Flow_Version_Id__c`, `Expected_Outcome__c`, `Overall_Result__c`, `Conditions_Read__c`, `Top_Finding__c`, `Result_JSON__c` (versioned snapshot: conditions, values, findings, health findings; schema version 2), `AI_Explanation__c` (optional Gemini explanation as JSON, kept apart), `Finding_Count__c` |
| `FlowProof_Finding__c` (master-detail to Investigation) | Queryable findings for the dashboard | `Category__c`, `Severity__c`, `Rule_Code__c`, `Title__c`, `Detail__c`, `Recommendation__c`, `Sort_Order__c`                                                                                                                                                                                                                                                                                 |
| `FlowProof_Setting__mdt`                                | App configuration                    | `AI_Enabled__c` (default false), `AI_Model__c` (`gemini-3.8-flash`), `AI_Send_Field_Values__c` (default false)                                                                                                                                                                                                                                                                              |

**Why there's no Evidence object yet.** Evidence is always read together with its investigation, and nothing queries it on its own. It lives in `Result_JSON__c`, which keeps the MVP at two custom objects. Feature 2 (investigation history and evidence references) can promote it to an object if needed.

**Record values in the snapshot.** The snapshot stores only the referenced fields' values. Because the Investigation's OWD is Private, it doesn't widen access. Retention settings come with Feature 2.

## 7. Security

- **Data access:** all Apex is `with sharing`, and record reads use `WITH USER_MODE`. Object and field names come from Flow metadata, are validated through `Schema` describes, and are never concatenated from user input. Values are bound.
- **Inaccessible fields:** these are reported as `INACCESSIBLE`, never fetched in system mode.
- **Metadata access:** the Tooling callout runs as the **user's own** identity (per-user OAuth principal), so Salesforce enforces their metadata permissions. Which permission is needed to read `Flow.Metadata` is _unverified_ (likely View Setup and Configuration). It will be tested with a minimal permission set in Phase 3.
- **Permission sets**
  - `FlowProof_User`: app, tabs, Apex classes, object access to their own investigations, and principal access for the org-API and Gemini credentials.
  - `FlowProof_Admin`: the user set, plus settings and View All on investigations.
- **AI:** off by default. The sanitizer sends condition structure and match results. Field values are replaced with type placeholders unless an admin opts in. No IDs, names, emails, or phone numbers are sent. Gemini terms are covered in [SECURITY.md](SECURITY.md).

## 8. Integrations

### 8.1 Flow metadata: same-org Tooling API (decided: A, verified 2026-10-15)

Apex can't read entry conditions with SOQL, and the Apex `Metadata` namespace can't retrieve Flows (§10.1–10.3). Lightning session IDs can't call the API. The supported route is a **Named Credential to the org's own API**.

|                           | **A. Tooling API via Named Credential (recommended)**                                                                                                                       | **B. CLI snapshot**                                                               |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| How                       | An External Client App plus External Credential (OAuth 2.0 browser flow, **per-user** principal) and a Named Credential `FlowProof_Org_API` pointing at the org's My Domain | `sf project retrieve` of Flows, then a script builds JSON, then a static resource |
| Freshness                 | Live                                                                                                                                                                        | Stale until regenerated and redeployed                                            |
| Respects user permissions | Yes, through the per-user principal                                                                                                                                         | No, it's whatever the snapshot contains                                           |
| One-time setup            | Admin creates the ECA and enters its key and secret; each user clicks "Authenticate" once                                                                                   | None in the org                                                                   |
| Customer-viable           | Yes. 2GP can package the NC, EC, External Auth Identity Provider, and permission set                                                                                        | No                                                                                |

**Recommendation:** build A as the primary source and keep B as a test fixture and offline fallback behind the same interface.

**Status:** A is deployed from `org-config/` (see [SETUP.md](SETUP.md) §6) and verified. An anonymous Apex callout to `callout:FlowProof_Org_API/services/data/v68.0/tooling/query` returned the demo Flow's entry conditions with HTTP 200.

Two details were learned from the org and aren't in the public docs:

- The identity provider needs PKCE (`IdentityProviderOptions` / `PkceEnabled = true`). Without it, the authorize endpoint rejects the login with "missing required code challenge".
- It needs `ClientAuthentication = ClientSecretPost`.

If A isn't authorized for a user, FlowProof still lists candidate Flows from `FlowDefinitionView` and reports the conditions as `INSUFFICIENT_EVIDENCE`, with instructions to click **Allow Access**.

### 8.2 Gemini

- **Model:** `gemini-3.8-flash`, configurable in `FlowProof_Setting__mdt`.
- **Endpoint:** `callout:Gemini_API/v1beta/models/{model}:generateContent`.
- **Credentials:**
  - External Credential `Gemini_API`, protocol Custom, Named Principal, with a custom header `x-goog-api-key: {!$Credential.Gemini_API.ApiKey}`.
  - Named Credential `Gemini_API`: Generate Authorization Header off, Allow Formulas in HTTP Header on.
  - The key itself is entered in Setup and can't be deployed.
- **Request** (`FlowProofGeminiClient`):
  - `systemInstruction` (fixed rules in `FlowProofAiPromptBuilder`), one user `contents` entry with the facts as JSON.
  - `generationConfig.responseMimeType = "application/json"` and `responseSchema` (Gemini Schema, uppercase types): `summary`, `keyPoints[{text, basedOn[]}]`, `nextSteps[]`, `caveats[]`. These are the keys in the `generateContent` reference examples (checked 2026-10-17).
  - `thinkingConfig.thinkingLevel = "low"`, `maxOutputTokens = 4096`.
  - No `temperature`; it's ignored on 3.6+ and may return 400 on future models. No `tools`.
- **Response handling:**
  - Join the non-thought text parts.
  - Require `finishReason = STOP` (or absent) and no `promptFeedback.blockReason`.
  - Parse the JSON (`FlowProofAiExplanation.fromModelJson`): require a summary, trim and cap every list and text, keep only key points that cite known rule codes or condition refs (`C1`, `C2`, ...). Failures are shown to the user and nothing is stored.
- **Errors:** 400 with "API key" or 401/403 → key problem with the Setup path; 404 → unknown model; 429 → quota; 5xx → try again. No retries inside the transaction.
- **Connection test:** `GET models/{model}` reads the model's details without generating.
- **Timeout:** `setTimeout(60000)`.

## 9. Error handling

- Typed exceptions: `FlowProofException`, with `ValidationException`, `MetadataUnavailableException`, `AccessException`, and `AiException`.
- **Partial results beat failures.** If one source fails (metadata callout, record access, AI), the investigation still completes. The failure becomes an `INSUFFICIENT_EVIDENCE` finding naming the cause.
- The UI shows safe messages. Details go to the investigation's result JSON, never stack traces to the user.

## 10. Verified platform facts

Docs read 2026-10-15. They document API 68.0, and the project uses 68.0.

1. **`FlowDefinitionView` supports `query()`.** It has `ApiName`, `IsActive`, `ActiveVersionId`, `LatestVersionId`, `ProcessType`, `TriggerType`, `RecordTriggerType`, `TriggerOrder`, `TriggerObjectOrEventId/Label`, and `ManageableState`. Neither it nor `FlowVersionView` exposes entry conditions. `FlowVersionView` must be filtered by `DurableId` or `FlowDefinitionViewId`. _Apex (not API) SOQL access is unverified; there's a smoke test in Phase 3._
2. **Tooling API `Flow`:** `Metadata` returns the full Flow including `start.filters`, `filterLogic`, `filterFormula`, `recordTriggerType`, `triggerType`, `object`, and `doesRequireRecordChangedToMeetCriteria`. You can query `Metadata` only when the result has **at most one row**. It's **null for managed-package Flows** (except templates).
3. **Apex `Metadata.MetadataType` supports only `CustomMetadata` and `Layout`.** Session IDs from Lightning contexts aren't API-enabled; the docs point to Named Credentials.
4. **No supported source ties a record-triggered Flow interview to a record.**
   - `FlowInterview`: has no triggering-record field.
   - `FlowInterviewLog`: screen flows only.
   - `FlowExecutionErrorEvent`: screen flows only.
   - EventLogFile `FlowExecution`: aggregates only.
   - Debug logs with a TraceFlag (under 24h, Workflow category) are the only per-run source, and only while a trace flag is set. That's the basis for a future "capture mode."
5. **Packaging:** 2GP can package the Named Credential, External Credential, External Auth Identity Provider, and permission set. Secrets and tokens are never packaged. 2GP can't package the External Credential → Auth. Provider reference, so use an External Auth Identity Provider. New connected apps are disabled by default since Spring '26, so use External Client Apps.
6. **Gemini:**
   - `gemini-3.8-flash` is stable, with no shutdown date announced.
   - Auth uses the `x-goog-api-key` header.
   - `responseSchema` is deprecated in favor of `responseFormat`.
   - The free tier allows training use and human review; paid doesn't ([terms](https://ai.google.dev/gemini-api/terms)).
7. **Apex callouts:** at most 100 per transaction, 120 s maximum timeout and 120 s cumulative, and none after uncommitted DML.

## 11. Testing strategy

| Layer                                                           | How                                                                                                                                        |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Parser, evaluator, diagnostic engine, sanitizer, prompt builder | Pure Apex unit tests, table-driven: every operator × type × null, plus unsupported constructs                                              |
| Tooling source, Gemini client                                   | `HttpCalloutMock`: success, 400/403/429/500/503, timeout, malformed JSON, blocked response, MAX_TOKENS                                     |
| Record service                                                  | `System.runAs` users with a minimal permission set: no FLS on a referenced field means `INACCESSIBLE`; no record access means a safe error |
| Investigation service                                           | Stubbed definition source, end to end through persistence                                                                                  |
| LWC                                                             | Jest: rendering, input validation, loading/empty/error states, condition table, AI-disabled path                                           |
| Platform behavior                                               | Demo Flow in `flowproof-dev` (Phase 5), checking evaluator assumptions against real runs                                                   |
| Static analysis                                                 | Salesforce Code Analyzer (PMD, ESLint, Flow, SFGE) in CI                                                                                   |

## 12. Path to an installable product

1. 2GP managed package with a namespace, holding the objects, CMDT, Apex, LWC, permission sets, the Named/External Credentials, and the External Auth Identity Provider.
2. A post-install **Setup** page in the app walks the admin through four steps: create the External Client App, enter its key and secret, authorize, and (optionally) enter the Gemini key.
3. Per-user principal authorization, done from the app.
4. Security review prep: Code Analyzer and SFGE clean, CRUD/FLS proof, data-flow documentation for Gemini, and the paid-tier requirement for customer data.

## 13. Known limitations

- Historical execution can't be confirmed from supported APIs (§10.4).
- Entry conditions are evaluated against **current** values. Prior values (field history, `OpportunityHistory`) are a planned enhancement.
- Managed-package Flows return no metadata and get reported as `INSUFFICIENT_EVIDENCE`.
- The `@salesforce/mcp` dev tool reaches end of life on 2026-11-02. It's a development convenience only; the product doesn't depend on it.
