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

## External AI (Google Gemini)

AI explanations are **optional** and **off by default**. Deterministic investigation results never depend on Gemini.

Before any request leaves Salesforce, a sanitization layer:

1. Sends only the fields referenced by evaluated conditions. No other record fields are sent.
2. Replaces record IDs, names, emails, and phone numbers with placeholders.
3. Sends condition results and metadata summaries, not raw records.
4. Logs what was sent, as field names only, so admins can audit it.

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
4. The sanitization layer runs regardless of tier.

## Reporting a vulnerability

This is a private project. Report issues to the repository owner directly; do not open public issues for security problems.
