/**
 * Unit tests for FlowProofInvestigationService. The Flow catalog and definition source are
 * stubbed; the record is a real synthetic Opportunity read through the real record service.
 * Conditions use standard fields only, so these tests do not depend on demo metadata.
 */
@IsTest
private class FlowProofInvestigationServiceTest {
    private static final String ACTIVE_ID = '301' + '0'.repeat(11) + '1AAA';
    private static final String LATEST_ID = '301' + '0'.repeat(11) + '2AAA';

    @IsTest
    static void shouldFindFailingConditionOnRealRecord() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
            'Acme Expansion',
            'Closed Won',
            25000,
            true
        );
        StubDefinitions definitions = new StubDefinitions(onboardingStart('Opportunity'));

        FlowProofInvestigationResult result = investigate(
            catalogWith(flowView(ACTIVE_ID, ACTIVE_ID, 'RecordAfterSave')),
            definitions,
            opportunity.Id
        );

        Assert.isTrue(result.conditionsRead, 'Conditions should be read');
        Assert.areEqual(ACTIVE_ID, result.evaluatedVersionId, 'The active version should be read');
        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
            result.evaluation.overall,
            'Blank Type fails the Flow'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.evaluation.conditions[2].outcome,
            'Type is the failing condition'
        );
        Assert.areEqual(
            'CONDITIONS_NOT_MET',
            result.findings[0].ruleCode,
            'The failing conditions are the top finding'
        );
        Assert.areEqual('NOT_CONFIRMED', result.historicalExecution, 'Execution is never confirmed');
    }

    @IsTest
    static void shouldKeepInvestigatingWhenDefinitionUnreadable() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Auth Test', 'Closed Won', 25000, true);
        StubDefinitions definitions = new StubDefinitions(null);
        definitions.failure = new FlowProofMetadataException('Refused (HTTP 401).')
            .withReason(FlowProofMetadataException.Reason.NOT_AUTHORIZED);

        FlowProofInvestigationResult result = investigate(
            catalogWith(flowView(ACTIVE_ID, ACTIVE_ID, 'RecordAfterSave')),
            definitions,
            opportunity.Id
        );

        Assert.isFalse(result.conditionsRead, 'Conditions were not read');
        Assert.isNull(result.evaluation, 'Nothing could be evaluated');
        Assert.areEqual(
            'CONDITIONS_UNREADABLE',
            result.findings[0].ruleCode,
            'The unreadable definition is the top finding'
        );
    }

    @IsTest
    static void shouldTreatParserFailureAsUnreadableDefinition() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Parser Test', 'Closed Won', 25000, true);
        StubDefinitions definitions = new StubDefinitions(null);
        definitions.failure = new FlowProofException('Flow metadata has no start element.');

        FlowProofInvestigationResult result = investigate(
            catalogWith(flowView(ACTIVE_ID, ACTIVE_ID, 'RecordAfterSave')),
            definitions,
            opportunity.Id
        );

        Assert.areEqual(
            'CONDITIONS_UNREADABLE',
            result.findings[0].ruleCode,
            'Parser failures are reported, not thrown'
        );
    }

    @IsTest
    static void shouldReadLatestVersionWhenNoneActive() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
            'Inactive Test',
            'Closed Won',
            25000,
            true
        );
        StubDefinitions definitions = new StubDefinitions(onboardingStart('Opportunity'));

        FlowProofInvestigationResult result = investigate(
            catalogWith(flowView(null, LATEST_ID, 'RecordAfterSave')),
            definitions,
            opportunity.Id
        );

        Assert.areEqual(
            LATEST_ID,
            definitions.requestedVersionId,
            'The latest version should be read when none is active'
        );
        Assert.areEqual('NO_ACTIVE_VERSION', result.findings[0].ruleCode, 'The inactive Flow is the top finding');
    }

    @IsTest
    static void shouldNotReadRecordWhenFlowRunsOnOtherObject() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
            'Mismatch Test',
            'Closed Won',
            25000,
            true
        );
        StubDefinitions definitions = new StubDefinitions(onboardingStart('Account'));

        FlowProofInvestigationResult result = investigate(
            catalogWith(flowView(ACTIVE_ID, ACTIVE_ID, 'RecordAfterSave')),
            definitions,
            opportunity.Id
        );

        Assert.isNull(result.evaluation, 'Conditions on another object are not evaluated');
        Assert.areEqual('Account', result.triggerObject, 'The trigger object should be reported');
        Assert.areEqual('OBJECT_MISMATCH', result.findings[0].ruleCode, 'The mismatch is the top finding');
    }

    @IsTest
    static void shouldNotReadDefinitionOfNonRecordTriggeredFlow() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
            'Scheduled Test',
            'Closed Won',
            25000,
            true
        );
        StubDefinitions definitions = new StubDefinitions(onboardingStart('Opportunity'));

        FlowProofInvestigationResult result = investigate(
            catalogWith(flowView(ACTIVE_ID, ACTIVE_ID, 'Scheduled')),
            definitions,
            opportunity.Id
        );

        Assert.isNull(definitions.requestedVersionId, 'The definition is not needed for a non-record-triggered Flow');
        Assert.areEqual('NOT_RECORD_TRIGGERED', result.findings[0].ruleCode, 'The trigger type is the top finding');
    }

    @IsTest
    static void shouldRunHealthChecksWhenFullDefinitionIsRead() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Health Test', 'Closed Won', 25000, true);
        FlowProofTestStubs.CatalogQueries queries = new FlowProofTestStubs.CatalogQueries();
        queries.flows.add(FlowProofTestStubs.activeOpportunityFlow('Opportunity_Onboarding'));
        queries.entities.add(FlowProofTestStubs.entity('Opportunity'));
        FlowProofTestStubs.Definitions definitions = new FlowProofTestStubs.Definitions(
            FlowProofTestStubs.onboardingStart()
        );
        definitions.metadata = FlowProofTestStubs.metadataWithoutFaultPath();

        Test.startTest();
        FlowProofInvestigationResult result = new FlowProofInvestigationService(
                new FlowProofFlowCatalogService(queries),
                definitions,
                new FlowProofRecordService()
            )
            .investigate(new FlowProofInvestigationRequest('Opportunity', opportunity.Id, 'Opportunity_Onboarding'));
        Test.stopTest();

        Assert.isTrue(result.healthChecked, 'Health checks run when the full definition is read');
        Assert.isTrue(ruleCodes(result.healthFindings).contains('MISSING_FAULT_PATHS'), 'Health findings are kept');
        Assert.isFalse(
            ruleCodes(result.findings).contains('MISSING_FAULT_PATHS'),
            'Health findings stay apart from the diagnosis'
        );
    }

    @IsTest
    static void shouldSkipHealthChecksWithoutFullDefinition() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('No Health', 'Closed Won', 25000, true);

        FlowProofInvestigationResult result = investigate(
            catalogWith(flowView(ACTIVE_ID, ACTIVE_ID, 'RecordAfterSave')),
            new StubDefinitions(onboardingStart('Opportunity')),
            opportunity.Id
        );

        Assert.isFalse(result.healthChecked, 'Without full metadata there is nothing to check');
        Assert.isTrue(result.healthFindings.isEmpty(), 'No health findings without full metadata');
    }

    @IsTest
    static void shouldCheckAllFlowsOnObjectAgainstOneRecord() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Sweep Test', 'Closed Won', 25000, true);
        FlowProofTestStubs.CatalogQueries queries = new FlowProofTestStubs.CatalogQueries();
        queries.entities.add(FlowProofTestStubs.entity('Opportunity'));
        queries.flows.add(FlowProofTestStubs.opportunityFlow('Archived_Flow', false));
        queries.flows.add(FlowProofTestStubs.opportunityFlow('Opportunity_Onboarding', true));
        queries.flows.add(FlowProofTestStubs.opportunityFlow('Discount_Approval', true));
        FlowProofTestStubs.Definitions definitions = new FlowProofTestStubs.Definitions(
            FlowProofTestStubs.onboardingStart()
        );

        Test.startTest();
        FlowProofSweepResult sweep = new FlowProofInvestigationService(
                new FlowProofFlowCatalogService(queries),
                definitions,
                new FlowProofRecordService()
            )
            .checkAllFlows('Opportunity', opportunity.Id);
        Test.stopTest();

        Assert.areEqual(3, sweep.flowCount, 'Every Flow on the object is counted');
        Assert.areEqual(3, sweep.rows.size(), 'Every Flow is checked');
        Assert.areEqual(3, definitions.requestedVersionIds.size(), 'Each definition is read once');
        Assert.areEqual('Sweep Test', sweep.recordName, 'The record name is shown');
        Assert.areEqual('Discount Approval', sweep.rows[0].flowLabel, 'Active Flows come first, by label');
        Assert.areEqual('Archived Flow', sweep.rows[2].flowLabel, 'Inactive Flows come last');
        Assert.areEqual('NOT_SATISFIED', sweep.rows[0].overallCode, 'Blank Type fails the conditions');
        Assert.areEqual('Type', sweep.rows[0].unmatchedConditions[0].field, 'The failing condition is listed');
        Assert.areEqual('CONDITIONS_NOT_MET', sweep.rows[0].topFinding.ruleCode, 'The top finding is shown');
        Assert.areEqual('NO_ACTIVE_VERSION', sweep.rows[2].topFinding.ruleCode, 'The inactive Flow says so');
        Assert.areEqual('NOT_CONFIRMED', sweep.historicalExecution, 'Execution is never confirmed');
    }

    @IsTest
    static void shouldStopSweepAtFlowLimit() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Limit Test', 'Closed Won', 25000, true);
        FlowProofTestStubs.CatalogQueries queries = new FlowProofTestStubs.CatalogQueries();
        queries.entities.add(FlowProofTestStubs.entity('Opportunity'));
        Integer total = FlowProofInvestigationService.MAX_SWEEP_FLOWS + 2;
        for (Integer i = 0; i < total; i++) {
            queries.flows.add(FlowProofTestStubs.opportunityFlow('Flow_' + String.valueOf(i).leftPad(2, '0'), true));
        }

        Test.startTest();
        FlowProofSweepResult sweep = new FlowProofInvestigationService(
                new FlowProofFlowCatalogService(queries),
                new FlowProofTestStubs.Definitions(FlowProofTestStubs.onboardingStart()),
                new FlowProofRecordService()
            )
            .checkAllFlows('Opportunity', opportunity.Id);
        Test.stopTest();

        Assert.areEqual(total, sweep.flowCount, 'Every Flow is counted');
        Assert.areEqual(FlowProofInvestigationService.MAX_SWEEP_FLOWS, sweep.rows.size(), 'Checks stop at the limit');
        Assert.areEqual(2, sweep.skippedFlowLabels.size(), 'Skipped Flows are listed');
    }

    @IsTest
    static void shouldRejectIncompleteSweep() {
        try {
            new FlowProofInvestigationService().checkAllFlows('Opportunity', null);
            Assert.fail('Expected IllegalArgumentException for a sweep without a record');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('record'), 'Message should say what is missing');
        }
    }

    @IsTest
    static void shouldRejectIncompleteRequest() {
        try {
            new FlowProofInvestigationService()
                .investigate(new FlowProofInvestigationRequest('Opportunity', null, 'Any_Flow'));
            Assert.fail('Expected IllegalArgumentException for a request without a record');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('record'), 'Message should say what is missing');
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static Set<String> ruleCodes(List<FlowProofFinding> findings) {
        Set<String> codes = new Set<String>();
        for (FlowProofFinding finding : findings) {
            codes.add(finding.ruleCode);
        }
        return codes;
    }

    private static FlowProofInvestigationResult investigate(
        FlowProofFlowCatalogService catalog,
        StubDefinitions definitions,
        Id recordId
    ) {
        FlowProofInvestigationRequest request = new FlowProofInvestigationRequest(
            'Opportunity',
            recordId,
            'Opportunity_Onboarding'
        );
        request.expectedOutcome = 'An onboarding Task should be created';
        Test.startTest();
        FlowProofInvestigationResult result = new FlowProofInvestigationService(
                catalog,
                definitions,
                new FlowProofRecordService()
            )
            .investigate(request);
        Test.stopTest();
        return result;
    }

    /**
     * StageName = Closed Won AND Amount > 10000 AND Type = New Customer, on the given object.
     * @param objectApiName trigger object
     * @return the start element
     */
    private static FlowProofFlowModel.FlowStart onboardingStart(String objectApiName) {
        FlowProofFlowModel.FlowStart start = new FlowProofFlowModel.FlowStart();
        start.objectApiName = objectApiName;
        start.triggerType = 'RecordAfterSave';
        start.recordTriggerType = 'CreateAndUpdate';
        start.filterLogic = 'and';
        start.filters.add(
            new FlowProofFlowModel.Condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won'))
        );
        start.filters.add(
            new FlowProofFlowModel.Condition(2, 'Amount', 'GreaterThan', FlowProofFlowModel.numberValue(10000))
        );
        start.filters.add(
            new FlowProofFlowModel.Condition(3, 'Type', 'EqualTo', FlowProofFlowModel.stringValue('New Customer'))
        );
        return start;
    }

    private static FlowDefinitionView flowView(String activeVersionId, String latestVersionId, String triggerType) {
        return (FlowDefinitionView) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'FlowDefinitionView' },
                    'ApiName' => 'Opportunity_Onboarding',
                    'Label' => 'Opportunity Onboarding',
                    'IsActive' => activeVersionId != null,
                    'ActiveVersionId' => activeVersionId,
                    'LatestVersionId' => latestVersionId,
                    'ProcessType' => 'AutoLaunchedFlow',
                    'TriggerType' => triggerType,
                    'RecordTriggerType' => 'CreateAndUpdate',
                    'TriggerObjectOrEventLabel' => 'Opportunity'
                }
            ),
            FlowDefinitionView.class
        );
    }

    private static FlowProofFlowCatalogService catalogWith(FlowDefinitionView view) {
        StubQueries queries = new StubQueries();
        queries.flows = new List<FlowDefinitionView>{ view };
        return new FlowProofFlowCatalogService(queries);
    }

    private class StubQueries extends FlowProofFlowCatalogService.FlowQueries {
        List<FlowDefinitionView> flows = new List<FlowDefinitionView>();

        public override List<FlowDefinitionView> findFlowByApiName(String flowApiName) {
            return flows;
        }
    }

    private class StubDefinitions implements FlowProofFlowDefinitionSource {
        private final FlowProofFlowModel.FlowStart start;
        Exception failure;
        String requestedVersionId;

        StubDefinitions(FlowProofFlowModel.FlowStart start) {
            this.start = start;
        }

        public FlowProofFlowDefinition getDefinition(Id flowVersionId) {
            requestedVersionId = flowVersionId;
            if (failure != null) {
                throw failure;
            }
            return new FlowProofFlowDefinition(start, null);
        }
    }
}
