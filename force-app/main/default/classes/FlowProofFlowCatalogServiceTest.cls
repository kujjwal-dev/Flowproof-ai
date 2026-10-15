/**
 * Unit tests for FlowProofFlowCatalogService. Most tests stub the query layer with
 * FlowDefinitionView rows built through JSON (its fields are read-only); the last tests run
 * the real queries to prove they execute in Apex under user mode.
 */
@IsTest
private class FlowProofFlowCatalogServiceTest {
    // Built at runtime: a syntactically valid Flow version Id that exists in no org.
    private static final String FAKE_VERSION_ID = '301' + '0'.repeat(11) + '1AAA';

    @IsTest
    static void shouldListRecordTriggeredFlowsForObject() {
        StubQueries stub = new StubQueries();
        stub.entities = new List<EntityDefinition>{ entity('Opportunity') };
        stub.flows = new List<FlowDefinitionView>{ view('Opportunity_Onboarding', 'RecordAfterSave') };

        Test.startTest();
        List<FlowProofFlowSummary> flows = new FlowProofFlowCatalogService(stub)
            .listRecordTriggeredFlows('Opportunity');
        Test.stopTest();

        Assert.areEqual(1, flows.size(), 'One Flow should be listed');
        Assert.areEqual('Opportunity', stub.lastDurableId, 'Flows should be filtered by the object durable Id');
        Assert.areEqual('Opportunity_Onboarding', flows[0].apiName, 'API name should be mapped');
        Assert.areEqual(FAKE_VERSION_ID, flows[0].activeVersionId, 'Active version should be mapped');
        Assert.areEqual(10, flows[0].triggerOrder, 'Trigger order should be mapped');
        Assert.isTrue(flows[0].isRecordTriggered, 'After-save Flows are record-triggered');
    }

    @IsTest
    static void shouldReturnEmptyListWhenObjectUnknown() {
        StubQueries stub = new StubQueries();

        Test.startTest();
        List<FlowProofFlowSummary> flows = new FlowProofFlowCatalogService(stub).listRecordTriggeredFlows('Unknown__c');
        Test.stopTest();

        Assert.isTrue(flows.isEmpty(), 'Unknown objects have no Flows');
        Assert.isNull(stub.lastDurableId, 'Flows should not be queried for an unknown object');
    }

    @IsTest
    static void shouldReturnSummaryWhenFlowExists() {
        StubQueries stub = new StubQueries();
        stub.flows = new List<FlowDefinitionView>{ view('Opportunity_Onboarding', 'RecordAfterSave') };

        Test.startTest();
        FlowProofFlowSummary summary = new FlowProofFlowCatalogService(stub).getFlow('Opportunity_Onboarding');
        Test.stopTest();

        Assert.areEqual('Opportunity_Onboarding', stub.lastApiName, 'The requested API name should be queried');
        Assert.isTrue(summary.isActive, 'Activation should be mapped');
        Assert.areEqual('CreateAndUpdate', summary.recordTriggerType, 'Record trigger type should be mapped');
    }

    @IsTest
    static void shouldMarkScheduledFlowAsNotRecordTriggered() {
        StubQueries stub = new StubQueries();
        stub.flows = new List<FlowDefinitionView>{ view('Nightly_Cleanup', 'Scheduled') };

        Test.startTest();
        FlowProofFlowSummary summary = new FlowProofFlowCatalogService(stub).getFlow('Nightly_Cleanup');
        Test.stopTest();

        Assert.isFalse(summary.isRecordTriggered, 'Scheduled Flows are not record-triggered');
    }

    @IsTest
    static void shouldThrowWhenFlowNotFound() {
        try {
            new FlowProofFlowCatalogService(new StubQueries()).getFlow('Missing_Flow');
            Assert.fail('Expected FlowProofException for a missing Flow');
        } catch (FlowProofException e) {
            Assert.isTrue(e.getMessage().contains('Missing_Flow'), 'Message should name the Flow');
        }
    }

    @IsTest
    static void shouldExplainPermissionWhenQueryDenied() {
        StubQueries stub = new StubQueries();
        stub.denyAccess = true;
        try {
            new FlowProofFlowCatalogService(stub).getFlow('Opportunity_Onboarding');
            Assert.fail('Expected FlowProofException when the query is denied');
        } catch (FlowProofException e) {
            Assert.isTrue(
                e.getMessage().contains('View Setup and Configuration'),
                'Message should name the permission'
            );
        }
    }

    @IsTest
    static void shouldRejectBlankObjectName() {
        try {
            new FlowProofFlowCatalogService(new StubQueries()).listRecordTriggeredFlows(' ');
            Assert.fail('Expected IllegalArgumentException for a blank object name');
        } catch (IllegalArgumentException e) {
            Assert.isNotNull(e.getMessage(), 'Message should explain the problem');
        }
    }

    @IsTest
    static void shouldRejectBlankFlowName() {
        try {
            new FlowProofFlowCatalogService(new StubQueries()).getFlow(null);
            Assert.fail('Expected IllegalArgumentException for a blank Flow name');
        } catch (IllegalArgumentException e) {
            Assert.isNotNull(e.getMessage(), 'Message should explain the problem');
        }
    }

    @IsTest
    static void shouldListObjectsWithFlowCounts() {
        FlowProofTestStubs.CatalogQueries queries = new FlowProofTestStubs.CatalogQueries();
        queries.flows.add(FlowProofTestStubs.activeOpportunityFlow('Opportunity_Onboarding'));
        queries.flows.add(FlowProofTestStubs.activeOpportunityFlow('Opportunity_Renewal'));
        queries.entities.add(entity('Opportunity'));

        Test.startTest();
        List<FlowProofObjectOption> options = new FlowProofFlowCatalogService(queries)
            .listObjectsWithRecordTriggeredFlows();
        Test.stopTest();

        Assert.areEqual(1, options.size(), 'Both Flows are on one object');
        Assert.areEqual('Opportunity', options[0].apiName, 'The object API name comes from EntityDefinition');
        Assert.areEqual(2, options[0].flowCount, 'Flows should be counted per object');
    }

    @IsTest
    static void shouldListNoObjectsWhenNoFlows() {
        Test.startTest();
        List<FlowProofObjectOption> options = new FlowProofFlowCatalogService(new FlowProofTestStubs.CatalogQueries())
            .listObjectsWithRecordTriggeredFlows();
        Test.stopTest();

        Assert.isTrue(options.isEmpty(), 'No Flows means no objects');
    }

    // ─── Real queries (no stub) ──────────────────────────────────────────

    @IsTest
    static void shouldRunRealObjectListQuery() {
        Test.startTest();
        List<FlowProofObjectOption> options = new FlowProofFlowCatalogService().listObjectsWithRecordTriggeredFlows();
        Test.stopTest();

        for (FlowProofObjectOption option : options) {
            Assert.isNotNull(option.apiName, 'Every option needs an API name');
        }
    }

    @IsTest
    static void shouldRunRealQueriesForExistingObject() {
        Test.startTest();
        List<FlowProofFlowSummary> flows = new FlowProofFlowCatalogService().listRecordTriggeredFlows('Opportunity');
        Test.stopTest();

        for (FlowProofFlowSummary flow : flows) {
            Assert.isTrue(flow.isRecordTriggered, 'Only record-triggered Flows should be listed: ' + flow.apiName);
        }
    }

    @IsTest
    static void shouldReturnEmptyListFromRealQueryForUnknownObject() {
        Test.startTest();
        List<FlowProofFlowSummary> flows = new FlowProofFlowCatalogService()
            .listRecordTriggeredFlows('FlowProof_No_Such_Object__c');
        Test.stopTest();

        Assert.isTrue(flows.isEmpty(), 'A nonexistent object has no Flows');
    }

    @IsTest
    static void shouldThrowFromRealQueryForUnknownFlow() {
        try {
            new FlowProofFlowCatalogService().getFlow('FlowProof_No_Such_Flow');
            Assert.fail('Expected FlowProofException for a nonexistent Flow');
        } catch (FlowProofException e) {
            Assert.isTrue(e.getMessage().contains('FlowProof_No_Such_Flow'), 'Message should name the Flow');
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static EntityDefinition entity(String apiName) {
        return (EntityDefinition) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'EntityDefinition' },
                    'DurableId' => apiName,
                    'QualifiedApiName' => apiName
                }
            ),
            EntityDefinition.class
        );
    }

    private static FlowDefinitionView view(String apiName, String triggerType) {
        return (FlowDefinitionView) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'FlowDefinitionView' },
                    'ApiName' => apiName,
                    'Label' => apiName.replace('_', ' '),
                    'IsActive' => true,
                    'ActiveVersionId' => FAKE_VERSION_ID,
                    'LatestVersionId' => FAKE_VERSION_ID,
                    'ProcessType' => 'AutoLaunchedFlow',
                    'TriggerType' => triggerType,
                    'RecordTriggerType' => 'CreateAndUpdate',
                    'TriggerOrder' => 10,
                    'TriggerObjectOrEventLabel' => 'Opportunity'
                }
            ),
            FlowDefinitionView.class
        );
    }

    private class StubQueries extends FlowProofFlowCatalogService.FlowQueries {
        List<EntityDefinition> entities = new List<EntityDefinition>();
        List<FlowDefinitionView> flows = new List<FlowDefinitionView>();
        Boolean denyAccess = false;
        String lastDurableId;
        String lastApiName;

        public override List<EntityDefinition> findEntity(String objectApiName) {
            denyIfRequested();
            return entities;
        }

        public override List<FlowDefinitionView> findRecordTriggeredFlows(String triggerObjectDurableId) {
            denyIfRequested();
            lastDurableId = triggerObjectDurableId;
            return flows;
        }

        public override List<FlowDefinitionView> findFlowByApiName(String flowApiName) {
            denyIfRequested();
            lastApiName = flowApiName;
            return flows;
        }

        private void denyIfRequested() {
            if (denyAccess) {
                throw new QueryException('Insufficient permissions: secure query included inaccessible field');
            }
        }
    }
}
