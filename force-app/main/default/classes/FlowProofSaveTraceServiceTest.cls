/**
 * Unit tests for FlowProofSaveTraceService. The org's Tooling API is mocked by URL; the record is a
 * real synthetic Opportunity and the Flow catalog is stubbed.
 */
@IsTest
private class FlowProofSaveTraceServiceTest {
    private static final String DEBUG_LEVEL_ID = '7dl' + '0'.repeat(11) + '1AAA';
    private static final String TRACE_FLAG_ID = '7tf' + '0'.repeat(11) + '1AAA';
    private static final String OWN_LEVEL_ID = '7dl' + '0'.repeat(11) + '2AAA';
    private static final String LOG_ID = '07L' + '0'.repeat(11) + '1';
    private static final String VERSION_15 = FlowProofTestStubs.VERSION_ID.left(15);

    @IsTest
    static void shouldCreateDebugLevelAndTraceFlag() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Trace Start', 'Closed Won', 25000, true);
        FlowProofTestStubs.RoutingMock mock = new FlowProofTestStubs.RoutingMock()
            .route('GET', 'FROM DebugLevel', 200, '{"records":[]}')
            .route('POST', 'sobjects/DebugLevel', 201, '{"id":"' + DEBUG_LEVEL_ID + '"}')
            .route('GET', 'FROM TraceFlag', 200, '{"records":[]}')
            .route('POST', 'sobjects/TraceFlag', 201, '{"id":"' + TRACE_FLAG_ID + '"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        FlowProofSaveTraceSession session = service().start(opportunity.Id);
        Test.stopTest();

        Assert.areEqual('Opportunity', session.objectApiName, 'The object comes from the record');
        Assert.areEqual(TRACE_FLAG_ID, session.traceFlagId, 'The new trace flag is remembered');
        Assert.isTrue(session.createdTraceFlag, 'FlowProof created the trace flag');
        Map<String, Object> debugLevel = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[1].getBody());
        Assert.areEqual('FINER', debugLevel.get('Workflow'), 'Flows are logged at FINER');
        Map<String, Object> traceFlag = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[3].getBody());
        Assert.areEqual(
            String.valueOf(UserInfo.getUserId()),
            traceFlag.get('TracedEntityId'),
            'Only the user is traced'
        );
        Assert.areEqual(DEBUG_LEVEL_ID, traceFlag.get('DebugLevelId'), 'FlowProof debug level is used');
    }

    @IsTest
    static void shouldReuseAndRestoreUsersOwnTraceFlag() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Trace Reuse', 'Closed Won', 25000, true);
        String ownFlag = JSON.serialize(
            new Map<String, Object>{
                'records' => new List<Object>{
                    new Map<String, Object>{
                        'Id' => TRACE_FLAG_ID,
                        'DebugLevelId' => OWN_LEVEL_ID,
                        'ExpirationDate' => '2000-01-01T00:00:00.000+0000'
                    }
                }
            }
        );
        FlowProofTestStubs.RoutingMock mock = new FlowProofTestStubs.RoutingMock()
            .route('GET', 'FROM DebugLevel', 200, '{"records":[{"Id":"' + DEBUG_LEVEL_ID + '"}]}')
            .route('GET', 'FROM TraceFlag', 200, ownFlag)
            .route('POST', 'sobjects/TraceFlag/' + TRACE_FLAG_ID, 204, '');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        FlowProofSaveTraceSession session = service().start(opportunity.Id);
        service().stop(session);
        Test.stopTest();

        Assert.isFalse(session.createdTraceFlag, 'The user\'s own trace flag is reused');
        Assert.areEqual(OWN_LEVEL_ID, session.previousDebugLevelId, 'Its debug level is remembered');
        Assert.isTrue(mock.requests[2].getEndpoint().contains('_HttpMethod=PATCH'), 'It is updated, not replaced');
        Map<String, Object> restored = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[3].getBody());
        Assert.areEqual(OWN_LEVEL_ID, restored.get('DebugLevelId'), 'Stop restores the user\'s debug level');
    }

    @IsTest
    static void shouldShowWhichFlowsRanAndWhichDidNotStart() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Trace Read', 'Closed Won', 25000, true);
        FlowProofTestStubs.RoutingMock mock = new FlowProofTestStubs.RoutingMock()
            .route('GET', 'FROM ApexLog', 200, logList('/aura'))
            .route(
                'GET',
                'sobjects/ApexLog/' + LOG_ID,
                200,
                FlowProofTestStubs.flowSaveLog(opportunity.Id, 'Opportunity Onboarding', VERSION_15)
            )
            .route('DELETE', 'sobjects/TraceFlag/' + TRACE_FLAG_ID, 204, '');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        FlowProofSaveTrace trace = service().read(session(opportunity.Id));
        Test.stopTest();

        Assert.isTrue(trace.logFound, 'The save was found');
        Assert.areEqual('RECORD_ID', trace.matchedBy, 'Matched by the record Id in the log');
        Assert.areEqual('Lightning page', trace.source, 'The save came from a Lightning page');
        Assert.areEqual('Opportunity Onboarding', trace.ran[0].label, 'The Flow that ran is listed');
        Assert.areEqual('FINISHED', trace.ran[0].statusCode, 'It finished');
        Assert.areEqual(
            new List<String>{ 'Discount Approval' },
            trace.notStarted,
            'The other active Flow did not start'
        );
        Assert.isTrue(trace.loggingStopped, 'Logging is switched off again');
    }

    @IsTest
    static void shouldMatchSaveWithoutFlowsByModifiedTime() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Trace Time', 'Closed Won', 25000, true);
        Datetime modifiedAt = [SELECT LastModifiedDate FROM Opportunity WHERE Id = :opportunity.Id].LastModifiedDate;
        String noFlows = '10:00:00.1 (1)|CODE_UNIT_STARTED|[EXTERNAL]|Flow:Opportunity';
        FlowProofTestStubs.RoutingMock mock = new FlowProofTestStubs.RoutingMock()
            .route('GET', 'FROM ApexLog', 200, logList('/services/data/v68.0/sobjects/Opportunity', modifiedAt))
            .route('GET', 'sobjects/ApexLog/' + LOG_ID, 200, noFlows)
            .route('DELETE', 'sobjects/TraceFlag/', 204, '');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        FlowProofSaveTrace trace = service().read(session(opportunity.Id));
        Test.stopTest();

        Assert.areEqual('SAVE_TIME', trace.matchedBy, 'Matched by the save time');
        Assert.areEqual('API', trace.source, 'The save came from the API');
        Assert.isTrue(trace.ran.isEmpty(), 'No Flow ran');
        Assert.areEqual(2, trace.notStarted.size(), 'Both active Flows did not start');
    }

    @IsTest
    static void shouldCombineTheLogsOfOneSave() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Trace Tie', 'Closed Won', 25000, true);
        Datetime modifiedAt = [SELECT LastModifiedDate FROM Opportunity WHERE Id = :opportunity.Id].LastModifiedDate;
        String secondLogId = '07L' + '0'.repeat(11) + '2';
        String bothLogs = JSON.serialize(
            new Map<String, Object>{
                'records' => new List<Object>{
                    logRow(LOG_ID, '/aura', modifiedAt.addSeconds(1)),
                    logRow(secondLogId, '/aura', modifiedAt),
                    logRow('07L' + '0'.repeat(11) + '3', '/aura', modifiedAt.addMinutes(-1))
                }
            }
        );
        Test.setMock(
            HttpCalloutMock.class,
            new FlowProofTestStubs.RoutingMock()
                .route('GET', 'FROM ApexLog', 200, bothLogs)
                .route('GET', 'sobjects/ApexLog/' + LOG_ID, 200, 'x|CODE_UNIT_STARTED|[EXTERNAL]|Flow:Opportunity')
                .route(
                    'GET',
                    'sobjects/ApexLog/' + secondLogId,
                    200,
                    FlowProofTestStubs.flowSaveLog(opportunity.Id, 'Opportunity Onboarding', VERSION_15)
                )
                .route('DELETE', 'sobjects/TraceFlag/', 204, '')
        );

        Test.startTest();
        FlowProofSaveTrace trace = service().read(session(opportunity.Id));
        Test.stopTest();

        Assert.areEqual('RECORD_ID', trace.matchedBy, 'Every log of the save is read, so the Flow that ran is found');
        Assert.areEqual('Opportunity Onboarding', trace.ran[0].label, 'The Flow that ran is shown');
    }

    @IsTest
    static void shouldExplainWhenNoSaveWasLogged() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Trace None', 'Closed Won', 25000, true);
        Test.setMock(
            HttpCalloutMock.class,
            new FlowProofTestStubs.RoutingMock().route('GET', 'FROM ApexLog', 200, '{"records":[]}')
        );

        Test.startTest();
        FlowProofSaveTrace trace = service().read(session(opportunity.Id));
        Test.stopTest();

        Assert.isFalse(trace.logFound, 'Nothing was found');
        Assert.isTrue(trace.message.contains('No save was logged yet'), 'The next step is explained');
        Assert.isFalse(trace.loggingStopped, 'Logging stays on so the user can save');
    }

    @IsTest
    static void shouldIgnoreLogsOfOtherActivity() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Trace Other', 'Closed Won', 25000, true);
        Test.setMock(
            HttpCalloutMock.class,
            new FlowProofTestStubs.RoutingMock()
                .route('GET', 'FROM ApexLog', 200, logList('/aura', Datetime.newInstanceGmt(2000, 1, 1)))
                .route('GET', 'sobjects/ApexLog/' + LOG_ID, 200, '10:00:00.1 (1)|EXECUTION_STARTED')
        );

        Test.startTest();
        FlowProofSaveTrace trace = service().read(session(opportunity.Id));
        Test.stopTest();

        Assert.isFalse(trace.logFound, 'Unrelated logs are not used');
        Assert.isTrue(trace.message.contains('not a save of this record'), 'The message says what to do');
    }

    @IsTest
    static void shouldRejectIncompleteOrForgedSessions() {
        try {
            service().read(new FlowProofSaveTraceSession());
            Assert.fail('Expected IllegalArgumentException for an empty session');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Start'), 'The message says what to do');
        }
        FlowProofSaveTraceSession forged = new FlowProofSaveTraceSession();
        forged.traceFlagId = '001' + '0'.repeat(12);
        forged.createdTraceFlag = true;
        try {
            service().stop(forged);
            Assert.fail('Expected IllegalArgumentException for a non-TraceFlag Id');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('not valid'), 'Forged Ids are refused');
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static FlowProofSaveTraceService service() {
        FlowProofTestStubs.CatalogQueries queries = new FlowProofTestStubs.CatalogQueries();
        queries.entities.add(FlowProofTestStubs.entity('Opportunity'));
        queries.flows.add(FlowProofTestStubs.opportunityFlow('Opportunity_Onboarding', true));
        FlowDefinitionView other = FlowProofTestStubs.opportunityFlow('Discount_Approval', true);
        queries.flows.add(
            (FlowDefinitionView) JSON.deserialize(
                JSON.serialize(other).replace(FlowProofTestStubs.VERSION_ID, '301' + '0'.repeat(11) + '9AAA'),
                FlowDefinitionView.class
            )
        );
        queries.flows.add(FlowProofTestStubs.opportunityFlow('Archived_Flow', false));
        return new FlowProofSaveTraceService(new FlowProofToolingClient(), new FlowProofFlowCatalogService(queries));
    }

    private static FlowProofSaveTraceSession session(Id recordId) {
        FlowProofSaveTraceSession session = new FlowProofSaveTraceSession();
        session.recordId = recordId;
        session.objectApiName = 'Opportunity';
        session.traceFlagId = TRACE_FLAG_ID;
        session.createdTraceFlag = true;
        session.startedAt = Datetime.now().addMinutes(-1);
        return session;
    }

    private static String logList(String operation) {
        return logList(operation, Datetime.now());
    }

    private static String logList(String operation, Datetime startTime) {
        return JSON.serialize(
            new Map<String, Object>{ 'records' => new List<Object>{ logRow(LOG_ID, operation, startTime) } }
        );
    }

    private static Map<String, Object> logRow(String logId, String operation, Datetime startTime) {
        return new Map<String, Object>{
            'Id' => logId,
            'StartTime' => startTime,
            'Operation' => operation,
            'Request' => operation.startsWith('/services') ? 'Api' : 'Application',
            'LogLength' => 6430
        };
    }
}
