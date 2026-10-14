# Development

## Branching

- `main` is always deployable and protected on GitHub (PR + review once the remote exists).
- Work happens on short-lived branches: `feature/<topic>`, `fix/<topic>`, `chore/<topic>`, `docs/<topic>`.
- One logical change per PR. CI must pass before merge.

## Everyday commands

| Task                           | Command                                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------------------- |
| LWC lint                       | `npm run lint`                                                                                |
| LWC unit tests                 | `npm test`                                                                                    |
| LWC tests with coverage        | `npm run test:unit:coverage`                                                                  |
| Format check                   | `npm run prettier:verify`                                                                     |
| Apex tests (org)               | `sf apex run test --target-org flowproof-dev --code-coverage --result-format human --wait 10` |
| Static analysis                | `sf code-analyzer run --workspace force-app`                                                  |
| Validate a deploy (no changes) | `sf project deploy start --dry-run --source-dir force-app --target-org flowproof-dev`         |
| Retrieve a Flow                | `sf project retrieve start --metadata Flow:<ApiName> --target-org flowproof-dev`              |

A Husky pre-commit hook runs `lint-staged`: Prettier on staged files, ESLint on LWC JS, and related Jest tests for changed LWC.

## Rules for working on the org

1. Target only `flowproof-dev`. Never pass a different `--target-org`.
2. **No deploys, data writes, or destructive changes without explicit approval.** `.claude/settings.json` forces a prompt for these commands.
3. Don't change org-wide security settings (OWD, profiles, session settings) without approval.
4. Retrieve before editing anything that already exists in the org.

## Status vocabulary

Progress reports use these words precisely:

| Word        | Meaning                                         |
| ----------- | ----------------------------------------------- |
| Implemented | Code written locally                            |
| Tested      | Local tests (Jest / Apex in org) ran and passed |
| Deployed    | Salesforce confirmed the deploy succeeded       |
| Verified    | Behavior was checked end-to-end in the org      |
| Blocked     | Can't proceed; reason stated                    |
| Planned     | Not started                                     |

## Code conventions

- **Apex:** thin `@AuraEnabled` controllers; logic lives in services. Use `WITH USER_MODE` / `AccessLevel.USER_MODE` for data access, and bind variables (never string concatenation) in dynamic SOQL. No SOQL or DML in loops.
- **LWC:** Lightning base components and SLDS first; no third-party UI libraries. Every data-loading component has loading, empty, and error states.
- **Naming:** Apex classes use the `FlowProof` prefix; LWC bundles use the `flowProof` prefix; custom objects and fields use the `FlowProof_` prefix where needed.
- **Tests:** Apex tests never make real callouts (`HttpCalloutMock` only). Jest tests mock all Apex imports.
