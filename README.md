# FlowProof AI

**Find out why a Salesforce Flow did (or didn't) run on a record, with proof.**

FlowProof AI is an app that lives inside Salesforce. Pick a record, and it tells you which of your record-triggered Flows should run for it, which ones won't, and exactly which condition stops them. It never guesses: every answer says how strong its evidence is. It is **read-only**, so it never changes your records or your Flows.

## What it does

| Feature                              | What you get                                                                                                                                                            |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Investigate**                      | Pick a record and a Flow. FlowProof checks every entry condition against the record and shows which one fails, and why.                                                 |
| **Check all Flows**                  | One click checks every record-triggered Flow on that object against the record.                                                                                         |
| **What if**                          | Change a few values in a form (for example Region = North America) and see which Flows would run. Nothing is saved.                                                     |
| **Record a test save**               | FlowProof turns on a debug log for you, you save the record once, and it shows which Flows really ran, what they did, and which didn't start. Real proof for that save. |
| **Flow health**                      | Best-practice tips for each Flow: records saved inside loops, missing fault paths, hard-coded Ids, and more. Tips only; FlowProof never edits a Flow.                   |
| **AI explanation** (optional)        | Google Gemini rewrites the findings in plain words. Record values are hidden from it by default.                                                                        |
| **Automation check on record pages** | A button or component on any record page that runs the check for that record.                                                                                           |
| **History**                          | Every investigation is saved so you can open it again later.                                                                                                            |

### How sure is each answer?

Every finding carries one of these labels:

| Label                     | Meaning                                                                            |
| ------------------------- | ---------------------------------------------------------------------------------- |
| **Confirmed by evidence** | Shown directly by the Flow's setup, the record's data or a debug log.              |
| **Supported hypothesis**  | Fits the evidence but isn't proven (for example, today's values fail a condition). |
| **Insufficient evidence** | FlowProof can't see the data it would need.                                        |
| **Unsupported analysis**  | Something FlowProof can't evaluate yet, such as a formula condition.               |

Salesforce keeps no history of past Flow runs. So unless you use **Record a test save**, FlowProof works from the record's **current** values, which may differ from the values at the time of an older save.

## Install it in your org

You need to be a **System Administrator** in the org.

1. **Log in** to the org where you want FlowProof.
2. **Open the install link** in the same browser:
   - Production or Developer Edition: <https://login.salesforce.com/packaging/installPackage.apexp?p0=04tbm000000qMndAAE>
   - Sandbox: <https://test.salesforce.com/packaging/installPackage.apexp?p0=04tbm000000qMndAAE>
3. Choose **Install for Admins Only**, then click **Install**. It takes a few minutes. Salesforce shows a confirmation, or emails you if the install takes longer.
4. **Check:** Setup → **Installed Packages** now lists **FlowProof AI** (version 0.2.0).

Using the Salesforce CLI instead: `sf package install --package 04tbm000000qMndAAE --target-org <your-org-alias> --wait 20`

## After installing: one-time setup

### 1. Give yourself access (2 minutes)

Setup → **Users** → your name → **Permission Set Assignments** → **Edit Assignments** → add **FlowProof Admin** → **Save**.

Give other users **FlowProof User** instead. They see only their own investigations; admins see everyone's.

### 2. Connect FlowProof to your org (one time, about 15 minutes)

FlowProof reads your Flows' settings through Salesforce's own API, logged in **as each user**. So it only ever shows what that user is allowed to see. This connection depends on your org's address, so it isn't inside the package. You add it once with the Salesforce CLI:

1. Install the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) and download this project (GitHub → **Code** → **Download ZIP**, or `git clone`).
2. Open a terminal in the project folder and log in to your org:

   ```bash
   sf org login web --alias my-org
   ```

   For a sandbox, add `--instance-url https://test.salesforce.com`.

3. Find your org's address: Setup → **My Domain** → **Current My Domain URL** (it looks like `https://yourcompany.my.salesforce.com`).
4. Deploy the connection, using your address:

   **Windows (PowerShell)**

   ```powershell
   $env:FLOWPROOF_ORG_URL = "https://yourcompany.my.salesforce.com"
   sf project deploy start --source-dir org-config/main/default/externalAuthIdentityProviders --target-org my-org
   sf project deploy start --source-dir org-config --target-org my-org
   ```

   **Mac or Linux**

   ```bash
   export FLOWPROOF_ORG_URL="https://yourcompany.my.salesforce.com"
   sf project deploy start --source-dir org-config/main/default/externalAuthIdentityProviders --target-org my-org
   sf project deploy start --source-dir org-config --target-org my-org
   ```

5. **Copy the app's key and secret** (Salesforce only shows the secret to a person):
   1. Setup → **External Client App Manager** → **FlowProof Org API** → **Settings** → **OAuth Settings** → **Consumer Key and Secret**. Enter the code Salesforce emails you.
   2. Setup → **Named Credentials** → **External Auth Identity Providers** → **FlowProof Org IdP** → **Edit**.
   3. Paste the Consumer Key as **Client ID** and the Consumer Secret as **Client Secret** → **Save**.
6. **Give access to the connection:** assign the permission set **FlowProof Org API Access** to every FlowProof user, yourself included.

### 3. Each user: allow access once (1 minute)

Each user does this once: click your profile picture → **Settings** → Quick Find **External Credentials** → **FlowProof Org EC** → **Allow Access** → log in if asked → **Allow**.

**Check it works:** App Launcher → **FlowProof AI** → **Settings** tab → **Test connection** should say **Connected**.

### 4. Optional: turn on AI explanations

1. Create a Gemini API key at [Google AI Studio](https://aistudio.google.com/apikey). Never paste the key into chat, email or code.
2. Setup → **Named Credentials** → **External Credentials** → **Gemini API** → under **Principals**, **GeminiKey** → **Edit** → **Add** an authentication parameter: Name `ApiKey`, Value = your key → **Save**.
3. FlowProof AI → **Settings** → **Test Gemini connection** should say **Connected**.
4. Setup → **Custom Metadata Types** → **FlowProof Setting** → **Manage Records** → **Default** → **Edit** → tick **AI Explanations Enabled** → **Save**. Leave **Send Field Values to AI** unticked unless your company allows record data to leave Salesforce.

> A free Gemini key lets Google use what you send to improve its products. Use free keys with test data only; for real data, use a key from a Google Cloud project with billing turned on.

### 5. Optional: put the check on record pages

- **As a button:** Setup → **Object Manager** → pick the object (for example Opportunity) → **Buttons, Links, and Actions** → **New Action** → Action Type **Lightning Web Component** → Component **c:flowProofRecordCheck** → Label "Check automation" → **Save**. Then add the action to the page layout under **Salesforce Mobile and Lightning Experience Actions**.
- **As a component:** open a record → gear icon → **Edit Page** → drag **FlowProof Automation Check** onto the page → **Save** and **Activate**.

### 6. Optional: Record a test save

It works only for users allowed to manage debug logs. That usually means admins with **View All Data** or **Manage Users**. FlowProof switches the log on just for you, for at most 30 minutes, and switches it off again when it has read your save.

## Using FlowProof

1. App Launcher → **FlowProof AI**.
2. **New investigation:** pick an **object**, a **record** and a **Flow**, or pick **All Flows on this object**.
3. Click **Investigate** (one Flow) or **Check all Flows**.
4. Read the result:
   - **Findings:** what's wrong, how sure FlowProof is, and the next step.
   - **Entry conditions:** each condition, the record's value and whether it matches.
   - **Flow health:** design tips for the Flow.
5. In **Check all Flows** you can also click **Try different values** (what if) or **Record a test save** (proof).
6. **History** lists every saved investigation.

## Update or remove

- **Update:** install the newer version's link. Your saved investigations stay. Afterwards, check **Settings** → **Test connection** and **Test Gemini connection**, and check that **AI Explanations Enabled** is still ticked (an update can reset the FlowProof Setting).
- **Remove:** Setup → **Installed Packages** → **FlowProof AI** → **Uninstall**. This also deletes the saved investigations. The connection from step 2 lives outside the package, so delete it yourself if you no longer need it.

## Limits

- Formula entry conditions and fields on related records (like `Account.Industry`) are reported as "not evaluated".
- Without **Record a test save**, results use the record's current values.
- Scheduled and asynchronous Flow paths run later and aren't part of a test save.
- Flows from managed packages hide their setup, so FlowProof can't read their conditions.

## For developers

| Document                           | What's inside                                                           |
| ---------------------------------- | ----------------------------------------------------------------------- |
| [SETUP.md](SETUP.md)               | Tools, org connection details, building and installing package versions |
| [DEVELOPMENT.md](DEVELOPMENT.md)   | Branches, commands, tests, deploy rules                                 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How it works inside: evaluation, health checks, test saves, AI          |
| [SECURITY.md](SECURITY.md)         | Permissions, what is sent to Gemini, debug-log handling                 |
| [ROADMAP.md](ROADMAP.md)           | What's done and what's next                                             |

**Project layout:** `force-app` is the app (the **FlowProof AI** unlocked package), `org-config` is the per-org API connection, and `demo` is optional demo data (a Region field, a demo Flow and a quick action for Opportunity).

**Tests:** 226 Apex tests (94–95% coverage) and 74 Lightning component tests. Run `npm test` for the component tests.

**Built with:** Salesforce DX (API 68.0), Apex, Lightning Web Components, Custom Metadata, Named and External Credentials, Google Gemini API (optional), Jest.
