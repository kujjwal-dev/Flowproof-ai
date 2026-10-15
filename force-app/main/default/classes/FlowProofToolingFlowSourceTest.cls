/**
 * Unit tests for FlowProofToolingFlowSource. All callouts are mocked; the success fixture is
 * the real Flow.Metadata of the demo Opportunity_Onboarding Flow (static resource).
 */
@IsTest
private class FlowProofToolingFlowSourceTest {
    // Built at runtime: a syntactically valid Flow version Id that exists in no org.
    private static final Id VERSION_ID = Id.valueOf('301' + '0'.repeat(11) + '1');

    @IsTest
    static void shouldParseStartElementFromToolingResponse() {
        Test.setMock(HttpCalloutMock.class, new RecordingMock(200, queryResponse(fixtureJson())));

        Test.startTest();
        FlowProofFlowModel.FlowStart start = new FlowProofToolingFlowSource().getStart(VERSION_ID);
        Test.stopTest();

        Assert.areEqual('Opportunity', start.objectApiName, 'Trigger object should be parsed');
        Assert.areEqual(3, start.filters.size(), 'All three entry conditions should be parsed');
    }

    @IsTest
    static void shouldQuerySingleVersionThroughNamedCredential() {
        RecordingMock mock = new RecordingMock(200, queryResponse(fixtureJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FlowProofToolingFlowSource().getStart(VERSION_ID);
        Test.stopTest();

        String endpoint = mock.lastRequest.getEndpoint();
        Assert.isTrue(
            endpoint.startsWith(FlowProofToolingFlowSource.QUERY_PATH),
            'Must call through the named credential: ' + endpoint
        );
        String soql = EncodingUtil.urlDecode(endpoint.substringAfter('?q='), 'UTF-8');
        Assert.isTrue(
            soql.contains('FROM Flow WHERE Id = \'' + String.valueOf(VERSION_ID).left(15)),
            'Must filter by the single version Id: ' + soql
        );
        Assert.areEqual('GET', mock.lastRequest.getMethod(), 'Query must be a GET');
    }

    @IsTest
    static void shouldReportNotAuthorizedWhenTokenRejected() {
        Assert.areEqual(
            FlowProofMetadataException.Reason.NOT_AUTHORIZED,
            failureReason(401, '[{"errorCode":"INVALID_SESSION_ID"}]'),
            'A rejected token means the user must authorize again'
        );
    }

    @IsTest
    static void shouldReportNotAuthorizedWhenPermissionMissing() {
        Assert.areEqual(
            FlowProofMetadataException.Reason.NOT_AUTHORIZED,
            failureReason(403, '[{"errorCode":"INSUFFICIENT_ACCESS"}]'),
            'A forbidden response means a missing permission'
        );
    }

    @IsTest
    static void shouldReportUnavailableOnServerError() {
        Assert.areEqual(
            FlowProofMetadataException.Reason.UNAVAILABLE,
            failureReason(500, '[{"errorCode":"UNKNOWN_EXCEPTION"}]'),
            'Server errors are reported as unavailable'
        );
    }

    @IsTest
    static void shouldReportNotFoundWhenNoRecords() {
        Assert.areEqual(
            FlowProofMetadataException.Reason.NOT_FOUND,
            failureReason(200, '{"size":0,"totalSize":0,"done":true,"records":[]}'),
            'An empty result means the version does not exist'
        );
    }

    @IsTest
    static void shouldReportNoMetadataWhenDefinitionHidden() {
        Assert.areEqual(
            FlowProofMetadataException.Reason.NO_METADATA,
            failureReason(200, queryResponse('null')),
            'Null metadata means the definition is hidden'
        );
    }

    @IsTest
    static void shouldReportInvalidResponseWhenBodyMalformed() {
        Assert.areEqual(
            FlowProofMetadataException.Reason.INVALID_RESPONSE,
            failureReason(200, '<html>Service unavailable</html>'),
            'Unparseable bodies are invalid responses'
        );
    }

    @IsTest
    static void shouldReportConnectionFailedWhenCalloutFails() {
        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        try {
            new FlowProofToolingFlowSource().getStart(VERSION_ID);
            Assert.fail('Expected FlowProofMetadataException');
        } catch (FlowProofMetadataException e) {
            Assert.areEqual(
                FlowProofMetadataException.Reason.CONNECTION_FAILED,
                e.reason,
                'Callout failures are connection failures'
            );
            Assert.isTrue(e.getMessage().contains('Allow Access'), 'Message should tell the user how to authorize');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldRejectIdThatIsNotFlowVersion() {
        try {
            new FlowProofToolingFlowSource().getStart(UserInfo.getUserId());
            Assert.fail('Expected IllegalArgumentException for a non-Flow Id');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('301'), 'Message should name the expected Id prefix');
        }
    }

    @IsTest
    static void shouldRejectNullId() {
        try {
            new FlowProofToolingFlowSource().getStart(null);
            Assert.fail('Expected IllegalArgumentException for a null Id');
        } catch (IllegalArgumentException e) {
            Assert.isNotNull(e.getMessage(), 'Message should explain the problem');
        }
    }

    @IsTest
    static void shouldReportNotConfiguredWhenConnectionTestCalloutFails() {
        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        FlowProofConnectionStatus status = new FlowProofToolingFlowSource().testConnection();
        Test.stopTest();

        Assert.areEqual('NOT_CONFIGURED', status.status, 'A failed callout means the setup is incomplete');
        Assert.isFalse(status.connected, 'Not connected');
    }

    @IsTest
    static void shouldReportUnavailableWhenConnectionTestGetsServerError() {
        Test.setMock(HttpCalloutMock.class, new RecordingMock(503, 'Service Unavailable'));

        Test.startTest();
        FlowProofConnectionStatus status = new FlowProofToolingFlowSource().testConnection();
        Test.stopTest();

        Assert.areEqual('UNAVAILABLE', status.status, 'Server errors mean temporarily unavailable');
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    /**
     * Runs getStart against a mocked response and returns the failure reason.
     * @param status HTTP status to return
     * @param body response body to return
     * @return the reason of the FlowProofMetadataException, or null when none was thrown
     */
    private static FlowProofMetadataException.Reason failureReason(Integer status, String body) {
        Test.setMock(HttpCalloutMock.class, new RecordingMock(status, body));
        FlowProofMetadataException.Reason reason;
        Test.startTest();
        try {
            new FlowProofToolingFlowSource().getStart(VERSION_ID);
        } catch (FlowProofMetadataException e) {
            reason = e.reason;
        }
        Test.stopTest();
        return reason;
    }

    /**
     * Wraps a Flow.Metadata JSON value in a Tooling API query response.
     * @param metadataJson JSON for the Metadata field ("null" for hidden metadata)
     * @return the response body
     */
    private static String queryResponse(String metadataJson) {
        return '{"size":1,"totalSize":1,"done":true,"records":[{"attributes":{"type":"Flow"},"Metadata":' +
            metadataJson +
            '}]}';
    }

    /**
     * Loads the real Flow.Metadata fixture of the demo Opportunity_Onboarding Flow.
     * @return the metadata JSON
     */
    private static String fixtureJson() {
        StaticResource fixture = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'FlowProofTestOnboardingFlow'
            WITH USER_MODE
            LIMIT 1
        ];
        return fixture.Body.toString();
    }

    private class RecordingMock implements HttpCalloutMock {
        private final Integer status;
        private final String body;
        HttpRequest lastRequest;

        RecordingMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            lastRequest = request;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody(body);
            return response;
        }
    }

    private class FailingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Unable to complete the callout');
        }
    }
}
