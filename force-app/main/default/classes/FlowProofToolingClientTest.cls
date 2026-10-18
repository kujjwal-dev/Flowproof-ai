/**
 * Unit tests for FlowProofToolingClient: requests through the FlowProof_Org_API named credential
 * and user-safe messages for refused or failed calls.
 */
@IsTest
private class FlowProofToolingClientTest {
    private static final String TRACE_FLAG_ID = '7tf' + '0'.repeat(11) + '1AAA';

    @IsTest
    static void shouldCallToolingApiThroughNamedCredential() {
        FlowProofTestStubs.RoutingMock mock = new FlowProofTestStubs.RoutingMock()
            .route('GET', 'FROM DebugLevel', 200, '{"records":[{"Id":"7dl1"}]}')
            .route('POST', 'sobjects/DebugLevel', 201, '{"id":"7dl2"}')
            .route('POST', 'sobjects/TraceFlag/' + TRACE_FLAG_ID, 204, '')
            .route('DELETE', 'sobjects/TraceFlag/' + TRACE_FLAG_ID, 204, '')
            .route('GET', '/Body', 200, 'log text');
        Test.setMock(HttpCalloutMock.class, mock);
        FlowProofToolingClient client = new FlowProofToolingClient();

        Test.startTest();
        List<Map<String, Object>> rows = client.query('SELECT Id FROM DebugLevel');
        String createdId = client.create('DebugLevel', new Map<String, Object>{ 'DeveloperName' => 'X' });
        client.updateRecord('TraceFlag', TRACE_FLAG_ID, new Map<String, Object>{ 'LogType' => 'USER_DEBUG' });
        client.deleteRecord('TraceFlag', TRACE_FLAG_ID);
        String body = client.getLogBody('07L' + '0'.repeat(11) + '1');
        Test.stopTest();

        Assert.areEqual('7dl1', rows[0].get('Id'), 'Query rows are returned');
        Assert.areEqual('7dl2', createdId, 'The new Id is returned');
        Assert.areEqual('log text', body, 'The log body is returned');
        Assert.isTrue(
            mock.requests[0].getEndpoint().startsWith('callout:FlowProof_Org_API/services/data/v68.0/tooling/'),
            'Calls go through the named credential'
        );
        Assert.isTrue(mock.requests[2].getEndpoint().endsWith('?_HttpMethod=PATCH'), 'Updates use the PATCH override');
        Assert.areEqual('DELETE', mock.requests[3].getMethod(), 'Deletes use DELETE');
    }

    @IsTest
    static void shouldExplainRefusedAndFailedCalls() {
        Map<Integer, String> expectedByStatus = new Map<Integer, String>{
            401 => 'Allow Access',
            403 => 'permission to manage debug logs',
            500 => 'HTTP 500'
        };
        Test.startTest();
        for (Integer status : expectedByStatus.keySet()) {
            Test.setMock(
                HttpCalloutMock.class,
                new FlowProofTestStubs.FixedResponse(status, '[{"message":"Detail from the API"}]')
            );
            try {
                new FlowProofToolingClient().query('SELECT Id FROM TraceFlag');
                Assert.fail('Expected FlowProofMetadataException for HTTP ' + status);
            } catch (FlowProofMetadataException e) {
                Assert.isTrue(
                    e.getMessage().contains(expectedByStatus.get(status)),
                    'HTTP ' + status + ': ' + e.getMessage()
                );
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldExplainUnreachableNamedCredential() {
        Test.setMock(HttpCalloutMock.class, new FailingCallout());

        Test.startTest();
        try {
            new FlowProofToolingClient().query('SELECT Id FROM TraceFlag');
            Assert.fail('Expected FlowProofMetadataException');
        } catch (FlowProofMetadataException e) {
            Assert.areEqual(FlowProofMetadataException.Reason.CONNECTION_FAILED, e.reason, 'The reason is set');
        }
        Test.stopTest();
    }

    private class FailingCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Unable to connect');
        }
    }
}
