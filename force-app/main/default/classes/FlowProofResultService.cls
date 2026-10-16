/**
 * Saves investigation results as FlowProof_Investigation__c (with the full result as JSON) and
 * FlowProof_Finding__c rows, and reads them back. All DML and SOQL run in user mode, so users
 * need the FlowProof User or FlowProof Admin permission set. Investigations are private:
 * users see their own unless granted View All.
 *
 * @example
 * FlowProofInvestigationResult saved = new FlowProofResultService().save(result);
 */
public with sharing class FlowProofResultService {
    private static final Integer TEXT_LIMIT = 255;
    private static final Integer OUTCOME_LIMIT = 2000;
    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static final String NOT_FOUND = 'The investigation was not found, or you do not have access to it.';
    private static final String NO_PERMISSION = 'You do not have permission to save FlowProof investigations. Ask an admin for the FlowProof User permission set.';

    /**
     * Saves a result and its findings.
     * @param result an unsaved investigation result
     * @return the same result with investigationId and investigationName set
     * @throws IllegalArgumentException when result or its Flow summary is null
     * @throws FlowProofException when the user lacks permission to save investigations
     */
    public FlowProofInvestigationResult save(FlowProofInvestigationResult result) {
        if (result == null || result.flow == null) {
            throw new IllegalArgumentException('An investigation result with a Flow is required.');
        }
        FlowProof_Investigation__c investigation = new FlowProof_Investigation__c(
            Target_Object__c = result.objectApiName,
            Target_Record_Id__c = result.recordId,
            Flow_Api_Name__c = result.flow.apiName,
            Flow_Label__c = result.flow.label?.left(TEXT_LIMIT),
            Flow_Version_Id__c = result.evaluatedVersionId,
            Expected_Outcome__c = result.expectedOutcome?.left(OUTCOME_LIMIT),
            Overall_Result__c = result.evaluation?.overall?.name() ?? 'NOT_EVALUATED',
            Conditions_Read__c = result.conditionsRead == true,
            Top_Finding__c = result.findings.isEmpty() ? null : result.findings[0].title?.left(TEXT_LIMIT),
            Result_JSON__c = JSON.serialize(result)
        );
        try {
            Database.insert(investigation, AccessLevel.USER_MODE);
            Database.insert(toFindingRows(investigation.Id, result.findings), AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw new FlowProofException(NO_PERMISSION, e);
        } catch (SecurityException e) {
            throw new FlowProofException(NO_PERMISSION, e);
        }
        result.investigationId = investigation.Id;
        result.investigationName = [
            SELECT Name
            FROM FlowProof_Investigation__c
            WHERE Id = :investigation.Id
            WITH USER_MODE
        ]
        .Name;
        return result;
    }

    /**
     * Reads a saved result.
     * @param investigationId FlowProof_Investigation__c Id
     * @return the stored result, with investigationId and investigationName set
     * @throws FlowProofException when the investigation is not found, not visible, or unreadable
     */
    public FlowProofInvestigationResult load(Id investigationId) {
        List<FlowProof_Investigation__c> rows = [
            SELECT Id, Name, Result_JSON__c, AI_Explanation__c
            FROM FlowProof_Investigation__c
            WHERE Id = :investigationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Result_JSON__c)) {
            throw new FlowProofException(NOT_FOUND);
        }
        FlowProofInvestigationResult result;
        try {
            result = (FlowProofInvestigationResult) JSON.deserialize(
                rows[0].Result_JSON__c,
                FlowProofInvestigationResult.class
            );
        } catch (JSONException e) {
            throw new FlowProofException('The saved result of ' + rows[0].Name + ' could not be read.', e);
        }
        result.investigationId = rows[0].Id;
        result.investigationName = rows[0].Name;
        // Results saved before health checks existed (schema version 1) have no health fields.
        result.healthChecked = result.healthChecked == true;
        result.healthFindings = result.healthFindings ?? new List<FlowProofFinding>();
        result.aiExplanation = readAiExplanation(rows[0].AI_Explanation__c);
        return result;
    }

    /**
     * Stores an AI explanation on a saved investigation, replacing any earlier one. The deterministic
     * result is not changed.
     *
     * Users cannot edit investigations, so the evidence they hold cannot be changed by hand. After the
     * user-mode read confirms the user can see the investigation, only the AI field is written in
     * system mode. Sharing still applies (this class is with sharing), so the user must be able to
     * edit the record through sharing, which owners can.
     * @param investigationId FlowProof_Investigation__c Id
     * @param explanation the explanation
     * @throws FlowProofException when the investigation is not visible or cannot be updated
     */
    public void saveAiExplanation(Id investigationId, FlowProofAiExplanation explanation) {
        List<FlowProof_Investigation__c> rows = [
            SELECT Id
            FROM FlowProof_Investigation__c
            WHERE Id = :investigationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new FlowProofException(NOT_FOUND);
        }
        try {
            Database.update(
                new FlowProof_Investigation__c(Id = rows[0].Id, AI_Explanation__c = JSON.serialize(explanation)),
                AccessLevel.SYSTEM_MODE
            );
        } catch (DmlException e) {
            throw new FlowProofException(
                'FlowProof could not store the AI explanation. Explanations can be stored on investigations you own.',
                e
            );
        }
    }

    private static FlowProofAiExplanation readAiExplanation(String explanationJson) {
        if (String.isBlank(explanationJson)) {
            return null;
        }
        try {
            return (FlowProofAiExplanation) JSON.deserialize(explanationJson, FlowProofAiExplanation.class);
        } catch (JSONException e) {
            // An unreadable explanation is treated as missing; the user can generate a new one.
            return null;
        }
    }

    /**
     * Lists the most recent investigations the user can see.
     * @param limitSize number of rows (1-200; defaults to 20)
     * @return summaries, newest first
     */
    public List<FlowProofInvestigationSummary> listRecent(Integer limitSize) {
        Integer size = (limitSize == null || limitSize < 1) ? DEFAULT_PAGE_SIZE : Math.min(limitSize, MAX_PAGE_SIZE);
        List<FlowProofInvestigationSummary> summaries = new List<FlowProofInvestigationSummary>();
        // Queried into a list first: a SOQL for-loop with WITH USER_MODE and a bind fails with "Variable does not exist".
        List<FlowProof_Investigation__c> rows = [
            SELECT
                Id,
                Name,
                Target_Object__c,
                Target_Record_Id__c,
                Flow_Label__c,
                Overall_Result__c,
                Top_Finding__c,
                Finding_Count__c,
                CreatedDate
            FROM FlowProof_Investigation__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Name DESC
            LIMIT :size
        ];
        for (FlowProof_Investigation__c row : rows) {
            FlowProofInvestigationSummary summary = new FlowProofInvestigationSummary();
            summary.investigationId = row.Id;
            summary.name = row.Name;
            summary.objectApiName = row.Target_Object__c;
            summary.recordId = row.Target_Record_Id__c;
            summary.flowLabel = row.Flow_Label__c;
            summary.overallResult = row.Overall_Result__c;
            summary.topFinding = row.Top_Finding__c;
            summary.findingCount = row.Finding_Count__c == null ? 0 : row.Finding_Count__c.intValue();
            summary.createdDate = row.CreatedDate;
            summaries.add(summary);
        }
        return summaries;
    }

    private static List<FlowProof_Finding__c> toFindingRows(Id investigationId, List<FlowProofFinding> findings) {
        List<FlowProof_Finding__c> rows = new List<FlowProof_Finding__c>();
        for (Integer i = 0; i < findings.size(); i++) {
            FlowProofFinding finding = findings[i];
            rows.add(
                new FlowProof_Finding__c(
                    Investigation__c = investigationId,
                    Rule_Code__c = finding.ruleCode,
                    Category__c = finding.category?.name(),
                    Severity__c = finding.severity?.name(),
                    Title__c = finding.title?.left(TEXT_LIMIT),
                    Detail__c = finding.detail,
                    Recommendation__c = finding.recommendation,
                    Sort_Order__c = i
                )
            );
        }
        return rows;
    }
}
