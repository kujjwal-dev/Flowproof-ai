/**
 * Apex entry points for the FlowProof AI Lightning components. Thin: each method delegates to a
 * service and turns errors into AuraHandledExceptions with user-safe messages. FlowProof and
 * input-validation messages are shown as-is; anything unexpected becomes a generic message.
 */
public with sharing class FlowProofInvestigationController {
    private static final String UNEXPECTED = 'FlowProof ran into an unexpected error. Try again, or ask your admin to check the setup.';

    @TestVisible
    private static FlowProofInvestigationService investigationServiceOverride;
    @TestVisible
    private static FlowProofAiService aiServiceOverride;

    /**
     * @return objects that have record-triggered Flows, sorted by label
     */
    @AuraEnabled(cacheable=true)
    public static List<FlowProofObjectOption> getObjectOptions() {
        try {
            return new FlowProofFlowCatalogService().listObjectsWithRecordTriggeredFlows();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @param objectApiName object API name
     * @return the object's record-triggered Flows
     */
    @AuraEnabled(cacheable=true)
    public static List<FlowProofFlowSummary> getFlows(String objectApiName) {
        try {
            return new FlowProofFlowCatalogService().listRecordTriggeredFlows(objectApiName);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * Runs and saves an investigation. Makes a callout to the org API, then saves the result.
     * @param objectApiName API name of the record's object
     * @param recordId the record
     * @param flowApiName API name of the Flow expected to act
     * @param expectedOutcome optional description of the expected outcome
     * @return the saved result
     */
    @AuraEnabled
    public static FlowProofInvestigationResult runInvestigation(
        String objectApiName,
        Id recordId,
        String flowApiName,
        String expectedOutcome
    ) {
        try {
            FlowProofInvestigationRequest request = new FlowProofInvestigationRequest(
                objectApiName,
                recordId,
                flowApiName
            );
            request.expectedOutcome = expectedOutcome;
            FlowProofInvestigationService service = investigationServiceOverride ?? new FlowProofInvestigationService();
            return new FlowProofResultService().save(service.investigate(request));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * Checks every record-triggered Flow on the object against one record. Not saved.
     * @param objectApiName API name of the record's object
     * @param recordId the record
     * @return one row per checked Flow
     */
    @AuraEnabled
    public static FlowProofSweepResult checkAllFlows(String objectApiName, Id recordId) {
        try {
            FlowProofInvestigationService service = investigationServiceOverride ?? new FlowProofInvestigationService();
            return service.checkAllFlows(objectApiName, recordId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * Returns a saved investigation's Gemini explanation, generating it when needed.
     * @param investigationId FlowProof_Investigation__c Id
     * @param regenerate true to replace an existing explanation
     * @return the explanation
     */
    @AuraEnabled
    public static FlowProofAiExplanation requestAiExplanation(Id investigationId, Boolean regenerate) {
        try {
            return (aiServiceOverride ?? new FlowProofAiService()).explain(investigationId, regenerate);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @return whether Gemini is reachable with the configured key and model
     */
    @AuraEnabled
    public static FlowProofConnectionStatus testAiConnection() {
        try {
            return (aiServiceOverride ?? new FlowProofAiService()).testConnection();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @param limitSize number of rows (1-200; defaults to 20)
     * @return the user's most recent investigations
     */
    @AuraEnabled(cacheable=true)
    public static List<FlowProofInvestigationSummary> getRecentInvestigations(Integer limitSize) {
        try {
            return new FlowProofResultService().listRecent(limitSize);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @param investigationId FlowProof_Investigation__c Id
     * @return the saved result
     */
    @AuraEnabled(cacheable=true)
    public static FlowProofInvestigationResult getInvestigation(Id investigationId) {
        try {
            return new FlowProofResultService().load(investigationId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @return whether the current user can read Flow definitions through FlowProof_Org_API
     */
    @AuraEnabled
    public static FlowProofConnectionStatus testConnection() {
        try {
            return new FlowProofToolingFlowSource().testConnection();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @return FlowProof AI settings
     */
    @AuraEnabled(cacheable=true)
    public static FlowProofSettings getSettings() {
        try {
            return FlowProofSettings.load();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static AuraHandledException handled(Exception e) {
        Boolean isSafe = e instanceof FlowProofException || e instanceof IllegalArgumentException;
        String message = isSafe ? e.getMessage() : UNEXPECTED;
        AuraHandledException handledException = new AuraHandledException(message);
        handledException.setMessage(message);
        return handledException;
    }
}
