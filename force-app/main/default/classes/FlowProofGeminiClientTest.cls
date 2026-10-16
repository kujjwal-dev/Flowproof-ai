/**
 * Unit tests for FlowProofGeminiClient: the request it sends through the Gemini_API named
 * credential, how it reads answers, and the user-safe messages for every failure.
 */
@IsTest
private class FlowProofGeminiClientTest {
    private static final String MODEL = 'gemini-3.8-flash';

    @IsTest
    static void shouldSendJsonRequestThroughNamedCredential() {
        FlowProofTestStubs.FixedResponse mock = new FlowProofTestStubs.FixedResponse(
            200,
            FlowProofTestStubs.geminiResponse('{"summary":"ok"}')
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String answer = generate(MODEL);
        Test.stopTest();

        HttpRequest request = mock.requests[0];
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
        Map<String, Object> config = (Map<String, Object>) body.get('generationConfig');
        Assert.areEqual('{"summary":"ok"}', answer, 'The answer text should be returned');
        Assert.areEqual(
            'callout:Gemini_API/v1beta/models/gemini-3.8-flash:generateContent',
            request.getEndpoint(),
            'Calls go through the named credential'
        );
        Assert.areEqual('POST', request.getMethod(), 'generateContent is a POST');
        Assert.isNull(request.getHeader('x-goog-api-key'), 'The key is added by the named credential, never by Apex');
        Assert.areEqual('application/json', config.get('responseMimeType'), 'A JSON answer is requested');
        Assert.isNotNull(config.get('responseSchema'), 'The answer schema is sent');
        Assert.isFalse(body.containsKey('tools'), 'Gemini gets no tools');
    }

    @IsTest
    static void shouldSkipThoughtParts() {
        String response = JSON.serialize(
            new Map<String, Object>{
                'candidates' => new List<Object>{
                    new Map<String, Object>{
                        'finishReason' => 'STOP',
                        'content' => new Map<String, Object>{
                            'parts' => new List<Object>{
                                new Map<String, Object>{ 'text' => 'thinking...', 'thought' => true },
                                new Map<String, Object>{ 'text' => '{"summary":' },
                                new Map<String, Object>{ 'text' => '"ok"}' }
                            }
                        }
                    }
                }
            }
        );
        Test.setMock(HttpCalloutMock.class, new FlowProofTestStubs.FixedResponse(200, response));

        Test.startTest();
        String answer = generate(MODEL);
        Test.stopTest();

        Assert.areEqual('{"summary":"ok"}', answer, 'Only answer parts are joined');
    }

    @IsTest
    static void shouldExplainHttpErrors() {
        Map<Integer, String> expectedByStatus = new Map<Integer, String>{
            403 => 'Gemini refused the request (HTTP 403)',
            404 => 'does not offer the model',
            429 => 'usage limit',
            503 => 'unavailable right now'
        };
        Test.startTest();
        for (Integer status : expectedByStatus.keySet()) {
            Test.setMock(HttpCalloutMock.class, new FlowProofTestStubs.FixedResponse(status, '{}'));
            assertFailure(MODEL, expectedByStatus.get(status));
        }
        Test.setMock(
            HttpCalloutMock.class,
            new FlowProofTestStubs.FixedResponse(400, '{"error":{"code":400,"message":"API key not valid."}}')
        );
        assertFailure(MODEL, 'rejected the API key');
        Test.setMock(
            HttpCalloutMock.class,
            new FlowProofTestStubs.FixedResponse(400, '{"error":{"code":400,"message":"Invalid schema."}}')
        );
        assertFailure(MODEL, 'Invalid schema.');
        Test.stopTest();
    }

    @IsTest
    static void shouldExplainUnfinishedAnswers() {
        Map<String, String> expectedByBody = new Map<String, String>{
            '{"promptFeedback":{"blockReason":"SAFETY"}}' => 'declined the request (SAFETY)',
            '{"candidates":[]}' => 'no answer',
            '{"candidates":[{"finishReason":"MAX_TOKENS"}]}' => 'cut off',
            '{"candidates":[{"finishReason":"RECITATION"}]}' => 'RECITATION',
            '{"candidates":[{"finishReason":"STOP","content":{"parts":[]}}]}' => 'empty answer',
            'not json' => 'could not be read'
        };
        Test.startTest();
        for (String body : expectedByBody.keySet()) {
            Test.setMock(HttpCalloutMock.class, new FlowProofTestStubs.FixedResponse(200, body));
            assertFailure(MODEL, expectedByBody.get(body));
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldExplainUnreachableNamedCredential() {
        Test.setMock(HttpCalloutMock.class, new FailingCallout());

        Test.startTest();
        assertFailure(MODEL, 'could not reach Gemini');
        Test.stopTest();
    }

    @IsTest
    static void shouldRejectInvalidModelBeforeCallout() {
        FlowProofTestStubs.FixedResponse mock = new FlowProofTestStubs.FixedResponse(200, '{}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        assertFailure('../tunedModels/x', 'not a valid Gemini model');
        assertFailure(null, 'not a valid Gemini model');
        Test.stopTest();

        Assert.isTrue(mock.requests.isEmpty(), 'No callout is made for an invalid model');
    }

    @IsTest
    static void shouldTestConnectionWithoutGenerating() {
        FlowProofTestStubs.FixedResponse mock = new FlowProofTestStubs.FixedResponse(200, '{"name":"models/x"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        FlowProofConnectionStatus connected = new FlowProofGeminiClient().testConnection(MODEL);
        FlowProofConnectionStatus invalid = new FlowProofGeminiClient().testConnection('');
        Test.stopTest();

        Assert.isTrue(connected.connected, 'HTTP 200 means connected');
        Assert.areEqual('GET', mock.requests[0].getMethod(), 'The check reads the model, it does not generate');
        Assert.areEqual(
            'callout:Gemini_API/v1beta/models/gemini-3.8-flash',
            mock.requests[0].getEndpoint(),
            'The check reads the configured model'
        );
        Assert.areEqual('NOT_CONFIGURED', invalid.status, 'An invalid model is a configuration problem');
    }

    @IsTest
    static void shouldReportRefusedConnection() {
        Test.setMock(HttpCalloutMock.class, new FlowProofTestStubs.FixedResponse(403, '{}'));

        Test.startTest();
        FlowProofConnectionStatus status = new FlowProofGeminiClient().testConnection(MODEL);
        Test.stopTest();

        Assert.isFalse(status.connected, 'HTTP 403 means not connected');
        Assert.isTrue(status.message.contains('External Credentials'), 'The message says where to put the key');
    }

    private static String generate(String model) {
        return new FlowProofGeminiClient()
            .generateJson(model, 'rules', 'facts', new Map<String, Object>{ 'type' => 'OBJECT' });
    }

    private static void assertFailure(String model, String expectedText) {
        try {
            generate(model);
            Assert.fail('Expected FlowProofException containing: ' + expectedText);
        } catch (FlowProofException e) {
            Assert.isTrue(
                e.getMessage().contains(expectedText),
                'Expected "' + expectedText + '" in: ' + e.getMessage()
            );
        }
    }

    private class FailingCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Unable to connect');
        }
    }
}
