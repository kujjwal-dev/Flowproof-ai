/**
 * Unit tests for FlowProofDiagnosticEngine: one scenario per rule, plus ordering and the
 * always-present "execution not confirmed" statement. Pure logic: no records.
 */
@IsTest
private class FlowProofDiagnosticEngineTest {
    private static final String ACTIVE_ID = '301' + '0'.repeat(11) + '1AAA';
    private static final String NEWER_ID = '301' + '0'.repeat(11) + '2AAA';

    @IsTest
    static void shouldAlwaysStateExecutionNotConfirmed() {
        FlowProofFinding finding = find(
            diagnose(contextWith(conditionsResult('NOT_SATISFIED', 'AND'))),
            'EXECUTION_NOT_CONFIRMED'
        );
        Assert.areEqual(
            FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
            finding.category,
            'Execution is never confirmed'
        );
    }

    @IsTest
    static void shouldReportConditionsNotMetAsHypothesis() {
        FlowProofFinding finding = find(
            diagnose(contextWith(conditionsResult('NOT_SATISFIED', 'AND'))),
            'CONDITIONS_NOT_MET'
        );
        Assert.areEqual(
            FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
            finding.category,
            'Current values are not proof'
        );
        Assert.areEqual(FlowProofFinding.Severity.HIGH, finding.severity, 'Failing conditions matter most');
        Assert.isTrue(
            finding.detail.contains('#2 Type equals New Customer'),
            'Detail should name the failing condition: ' + finding.detail
        );
        Assert.isTrue(finding.detail.contains('not proof'), 'Detail should state the evidence limit');
    }

    @IsTest
    static void shouldExposeCategoryAndSeverityCodesForLightning() {
        FlowProofFinding finding = find(
            diagnose(contextWith(conditionsResult('NOT_SATISFIED', 'AND'))),
            'CONDITIONS_NOT_MET'
        );
        // Apex enums arrive empty in Lightning components, so the String codes must be set.
        Assert.areEqual('SUPPORTED_HYPOTHESIS', finding.categoryCode, 'Category code must mirror the enum');
        Assert.areEqual('HIGH', finding.severityCode, 'Severity code must mirror the enum');
    }

    @IsTest
    static void shouldListHighSeverityFindingsFirst() {
        List<FlowProofFinding> findings = diagnose(contextWith(conditionsResult('NOT_SATISFIED', 'AND')));
        Assert.areEqual('CONDITIONS_NOT_MET', findings[0].ruleCode, 'The failing conditions come first');
        Assert.areEqual(
            'EXECUTION_NOT_CONFIRMED',
            findings[findings.size() - 1].ruleCode,
            'The informational note comes last'
        );
    }

    @IsTest
    static void shouldExplainOnlyWhenUpdatedToMeet() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('SATISFIED', 'AND'));
        context.start.requiresRecordChangedToMeetCriteria = true;
        List<FlowProofFinding> findings = diagnose(context);
        Assert.isNotNull(find(findings, 'CONDITIONS_MET'), 'Met conditions should be reported');
        Assert.areEqual(
            FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
            find(findings, 'ONLY_WHEN_UPDATED_TO_MEET').category,
            'The re-trigger rule is a hypothesis about the save'
        );
    }

    @IsTest
    static void shouldSuggestLookingInsideFlowWhenConditionsMet() {
        FlowProofFinding finding = find(
            diagnose(contextWith(conditionsResult('SATISFIED', 'AND'))),
            'LOOK_INSIDE_FLOW'
        );
        Assert.isTrue(finding.recommendation.contains('Debug'), 'Next step should point to Flow debugging');
    }

    @IsTest
    static void shouldReportNoActiveVersion() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('SATISFIED', 'AND'));
        context.flow.activeVersionId = null;
        FlowProofFinding finding = find(diagnose(context), 'NO_ACTIVE_VERSION');
        Assert.areEqual(
            FlowProofFinding.Category.CONFIRMED,
            finding.category,
            'Activation state is confirmed by metadata'
        );
        Assert.areEqual(FlowProofFinding.Severity.HIGH, finding.severity, 'An inactive Flow cannot run');
    }

    @IsTest
    static void shouldReportNewerInactiveVersion() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('SATISFIED', 'AND'));
        context.flow.latestVersionId = NEWER_ID;
        Assert.isNotNull(find(diagnose(context), 'NEWER_VERSION_INACTIVE'), 'A newer draft should be reported');
    }

    @IsTest
    static void shouldReportNotRecordTriggeredAndSkipConditions() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('NOT_SATISFIED', 'AND'));
        context.flow.isRecordTriggered = false;
        List<FlowProofFinding> findings = diagnose(context);
        Assert.areEqual(
            FlowProofFinding.Category.CONFIRMED,
            find(findings, 'NOT_RECORD_TRIGGERED').category,
            'Trigger type is confirmed'
        );
        Assert.isNull(
            find(findings, 'CONDITIONS_NOT_MET'),
            'Conditions are irrelevant when saves never start the Flow'
        );
    }

    @IsTest
    static void shouldGiveAuthorizeStepWhenConditionsUnreadable() {
        FlowProofDiagnosticContext context = contextWith(null);
        context.start = null;
        context.metadataFailure = FlowProofMetadataException.Reason.NOT_AUTHORIZED;
        context.metadataFailureMessage = 'The org API refused the request (HTTP 401).';
        FlowProofFinding finding = find(diagnose(context), 'CONDITIONS_UNREADABLE');
        Assert.areEqual(
            FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
            finding.category,
            'Unread conditions are missing evidence'
        );
        Assert.isTrue(finding.recommendation.contains('Allow Access'), 'Next step should explain how to authorize');
    }

    @IsTest
    static void shouldExplainCalloutAfterDml() {
        FlowProofDiagnosticContext context = contextWith(null);
        context.start = null;
        context.metadataFailure = FlowProofMetadataException.Reason.CALLOUT_AFTER_DML;
        FlowProofFinding finding = find(diagnose(context), 'CONDITIONS_UNREADABLE');
        Assert.isTrue(
            finding.recommendation.contains('before saving'),
            'Next step should explain the transaction order'
        );
        Assert.isFalse(finding.recommendation.contains('Allow Access'), 'Authorizing would not help here');
    }

    @IsTest
    static void shouldExplainHiddenManagedDefinitions() {
        FlowProofDiagnosticContext context = contextWith(null);
        context.start = null;
        context.metadataFailure = FlowProofMetadataException.Reason.NO_METADATA;
        Assert.isTrue(
            find(diagnose(context), 'CONDITIONS_UNREADABLE').title.contains('hides'),
            'Title should say the definition is hidden'
        );
    }

    @IsTest
    static void shouldReportObjectMismatchAndSkipConditions() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('NOT_SATISFIED', 'AND'));
        context.start.objectApiName = 'Account';
        List<FlowProofFinding> findings = diagnose(context);
        Assert.isNotNull(find(findings, 'OBJECT_MISMATCH'), 'A different trigger object should be reported');
        Assert.isNull(find(findings, 'CONDITIONS_NOT_MET'), 'Conditions on another object are not evaluated');
    }

    @IsTest
    static void shouldReportCreateOnlyTrigger() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('SATISFIED', 'AND'));
        context.start.recordTriggerType = 'Create';
        Assert.areEqual(
            FlowProofFinding.Severity.MEDIUM,
            find(diagnose(context), 'RUNS_ON_CREATE_ONLY').severity,
            'Create-only Flows are a common surprise'
        );
    }

    @IsTest
    static void shouldReportBeforeSaveLimitation() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('SATISFIED', 'AND'));
        context.start.triggerType = 'RecordBeforeSave';
        Assert.isTrue(
            find(diagnose(context), 'BEFORE_SAVE_FLOW').detail.contains('cannot create records'),
            'Before-save limits should be explained'
        );
    }

    @IsTest
    static void shouldReportFormulaConditionsAsUnsupported() {
        Assert.areEqual(
            FlowProofFinding.Category.UNSUPPORTED,
            find(diagnose(contextWith(conditionsResult('INDETERMINATE', 'FORMULA'))), 'FORMULA_CONDITIONS').category,
            'Formula conditions are unsupported analysis'
        );
    }

    @IsTest
    static void shouldReportCustomLogicAsUnsupported() {
        FlowProofDiagnosticContext context = contextWith(conditionsResult('INDETERMINATE', 'CUSTOM'));
        context.start.filterLogic = '1 AND (2 OR 3)';
        Assert.isTrue(
            find(diagnose(context), 'CUSTOM_LOGIC').detail.contains('1 AND (2 OR 3)'),
            'Detail should quote the logic'
        );
    }

    @IsTest
    static void shouldReportEachKindOfUnevaluatedCondition() {
        FlowProofEvaluationResult evaluation = conditionsResult('INDETERMINATE', 'AND');
        evaluation.conditions[0].outcome = FlowProofEvaluationResult.ConditionOutcome.INACCESSIBLE;
        evaluation.conditions[1].outcome = FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED;
        evaluation.conditions.add(condition(3, 'Old__c', FlowProofEvaluationResult.ConditionOutcome.MISSING));
        evaluation.conditions.add(condition(4, 'Name', FlowProofEvaluationResult.ConditionOutcome.UNCERTAIN));
        List<FlowProofFinding> findings = diagnose(contextWith(evaluation));
        Assert.areEqual(
            FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
            find(findings, 'INACCESSIBLE_FIELDS').category,
            'Unreadable fields'
        );
        Assert.areEqual(
            FlowProofFinding.Category.UNSUPPORTED,
            find(findings, 'UNSUPPORTED_CONDITIONS').category,
            'Unsupported constructs'
        );
        Assert.areEqual(
            FlowProofFinding.Category.CONFIRMED,
            find(findings, 'MISSING_FIELDS').category,
            'Missing fields are a confirmed defect'
        );
        Assert.isNotNull(find(findings, 'UNCERTAIN_CONDITIONS'), 'Unverified semantics should be reported');
    }

    @IsTest
    static void shouldRejectMissingContext() {
        try {
            new FlowProofDiagnosticEngine().diagnose(null);
            Assert.fail('Expected IllegalArgumentException for a null context');
        } catch (IllegalArgumentException e) {
            Assert.isNotNull(e.getMessage(), 'Message should explain the problem');
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static List<FlowProofFinding> diagnose(FlowProofDiagnosticContext context) {
        Test.startTest();
        List<FlowProofFinding> findings = new FlowProofDiagnosticEngine().diagnose(context);
        Test.stopTest();
        return findings;
    }

    /**
     * An active, record-triggered after-save Flow on Opportunity whose conditions were read.
     * @param evaluation the evaluation to diagnose (may be null)
     * @return the context
     */
    private static FlowProofDiagnosticContext contextWith(FlowProofEvaluationResult evaluation) {
        FlowProofFlowSummary flow = new FlowProofFlowSummary();
        flow.apiName = 'Opportunity_Onboarding';
        flow.label = 'Opportunity Onboarding';
        flow.isActive = true;
        flow.isRecordTriggered = true;
        flow.triggerType = 'RecordAfterSave';
        flow.activeVersionId = ACTIVE_ID;
        flow.latestVersionId = ACTIVE_ID;
        FlowProofDiagnosticContext context = new FlowProofDiagnosticContext('Opportunity', flow);
        context.start = new FlowProofFlowModel.FlowStart();
        context.start.objectApiName = 'Opportunity';
        context.start.triggerType = 'RecordAfterSave';
        context.start.recordTriggerType = 'CreateAndUpdate';
        context.start.filterLogic = 'and';
        context.evaluation = evaluation;
        return context;
    }

    /**
     * Two conditions: #1 StageName matches; #2 Type fails (or matches when overall is SATISFIED).
     * @param overall OverallResult name
     * @param logicType logic type
     * @return the evaluation
     */
    private static FlowProofEvaluationResult conditionsResult(String overall, String logicType) {
        FlowProofEvaluationResult evaluation = new FlowProofEvaluationResult();
        evaluation.overall = FlowProofEvaluationResult.OverallResult.valueOf(overall);
        evaluation.logicType = logicType;
        evaluation.conditions.add(condition(1, 'StageName', FlowProofEvaluationResult.ConditionOutcome.MATCH));
        evaluation.conditions.add(
            condition(
                2,
                'Type',
                overall == 'SATISFIED'
                    ? FlowProofEvaluationResult.ConditionOutcome.MATCH
                    : FlowProofEvaluationResult.ConditionOutcome.NO_MATCH
            )
        );
        return evaluation;
    }

    private static FlowProofEvaluationResult.ConditionResult condition(
        Integer index,
        String field,
        FlowProofEvaluationResult.ConditionOutcome outcome
    ) {
        FlowProofEvaluationResult.ConditionResult result = new FlowProofEvaluationResult.ConditionResult();
        result.index = index;
        result.field = field;
        result.operator = 'EqualTo';
        result.expectedDisplay = field == 'Type' ? 'New Customer' : 'Closed Won';
        result.actualDisplay = '(blank)';
        return result.resolve(outcome, 'test reason');
    }

    private static FlowProofFinding find(List<FlowProofFinding> findings, String ruleCode) {
        for (FlowProofFinding finding : findings) {
            if (finding.ruleCode == ruleCode) {
                return finding;
            }
        }
        return null;
    }
}
