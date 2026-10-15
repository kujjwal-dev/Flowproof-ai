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

        public FlowProofFlowModel.FlowStart getStart(Id flowVersionId) {
            requestedVersionId = flowVersionId;
            if (failure != null) {
                throw failure;
            }
            return start;
        }
    }
}
