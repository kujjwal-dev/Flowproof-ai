# Security

## Secrets

- No secrets in this repository: no API keys, Salesforce tokens, auth URLs, or passwords.
- Salesforce CLI auth stays in the CLI's own store (`~/.sfdx`), never in the project.
- The Gemini API key lives only in a Salesforce **External Credential** principal, entered in Setup. Apex reaches it through the `Gemini_API` Named Credential and never reads the key.
- CI secrets (e.g. an SFDX auth URL for a validation org) are GitHub encrypted secrets, never files.
- `.gitignore` blocks common secret file patterns (`.env*`, `*.key`, `*.pem`, auth-URL files).

## Salesforce data access

FlowProof runs as the signed-in user and must never reveal anything that user can't already see.

- **Sharing:** classes are declared `with sharing`.
- **CRUD/FLS:** record queries run in user mode (`WITH USER_MODE` / `AccessLevel.USER_MODE`). Fields the user can't read are reported as **inaccessible**, not fetched and hidden.
- **Dynamic SOQL:** object and field names are validated against `Schema` describe results before use, and values are always bind variables.
- **Metadata access:** reading Flow definitions needs extra permissions. The exact requirement is documented in [ARCHITECTURE.md](ARCHITECTURE.md) once verified. If a user lacks it, FlowProof reports _Insufficient evidence_ and doesn't fail silently.
- **Permission sets:** access to the app is granted only through FlowProof permission sets, never profiles.

## Debug logs ("Record a test save")

- FlowProof switches on a debug log **only for the signed-in user**, only when they click **Record a test save**, for at most 30 minutes, and switches it off (or restores the user's own debug level) when it has read the save.
- It creates one debug level, `FlowProof_Trace`, in the org on first use. Creating trace flags and reading logs needs debug-log permissions; the API refuses users without them, and FlowProof shows that message.
- Debug logs contain field values of saved records (Salesforce writes the `$Record` snapshot). FlowProof reads only Flow names, element names, decision outcomes, errors and validation messages, never stores the log, and never sends it to Gemini. The logs themselves stay in the org under Salesforce's normal retention.

## External AI (Google Gemini)

AI explanations are **optional** and **off by default**. Deterministic investigation results never depend on Gemini.

**What is sent** (`FlowProofAiPromptBuilder`), only when a user clicks **Explain with Gemini** on a saved investigation:

- The Flow's label, API name, trigger settings and entry conditions (field names, operators, and the Flow's own comparison values). This is metadata.
- Each condition's outcome code (match, no match, ...), and FlowProof's findings and Flow health findings.
- The user's "expected outcome" text, cut to 500 characters and marked as user text, not instructions.

**What is never sent:** the record's Id or name, the investigation's Id, the user's identity, or any field the conditions don't reference. The record's **current field values** are replaced by `[hidden]`, both in the condition list and inside finding text, unless an admin turns on `AI_Send_Field_Values__c`.

**What Gemini can do:** nothing but return text. FlowProof sends no tools, never executes model output, never changes records or Flows, and shows the answer as plain text labelled "not evidence".

**Grounding:** every key point must cite the rule codes or condition refs it relies on. Points that cite nothing FlowProof found are dropped and counted (`FlowProofAiExplanation`). The deterministic result is never modified.

**Storage:** the explanation is stored in `AI_Explanation__c`, separate from `Result_JSON__c`. Users have create and read access to investigations, not edit, so stored evidence can't be changed by hand. To store the explanation, `FlowProofResultService.saveAiExplanation` first confirms in user mode that the user can read the investigation, then writes only `AI_Explanation__c` in system mode. The class is `with sharing`, so the user must still have edit access through sharing (owners do).

### Gemini tier and data use

Source: [Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms), effective 2026-03-23, checked 2026-10-15.

|                                                       | Free tier ("Unpaid Services")                                    | Paid ("Paid Services")                                             |
| ----------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------ |
| When it applies                                       | Any API key without billing                                      | Only via a Google Cloud project with an **active billing account** |
| Prompts and responses used to improve Google products | **Yes**                                                          | No                                                                 |
| Human review of inputs and outputs                    | **May happen**                                                   | No (only short-term abuse-detection logging)                       |
| Google's guidance                                     | "Do not submit sensitive, confidential, or personal information" | Data Processing Addendum applies                                   |

**FlowProof rules that follow:**

1. **Free tier is for development with synthetic data only.** Demo records are invented, and no real customer org connects to a free-tier key.
2. **Real customer orgs need a billed Google Cloud project.**
3. **EEA, Switzerland, and UK:** the terms allow only Paid Services when an app is offered to users there.
4. Record values stay hidden regardless of tier unless an admin deliberately turns on `AI_Send_Field_Values__c`; with a free-tier key, leave it off.

## Reporting a vulnerability

This is a private project. Report issues to the repository owner directly; do not open public issues for security problems.
