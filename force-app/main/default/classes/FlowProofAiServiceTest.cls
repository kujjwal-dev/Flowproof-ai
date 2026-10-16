/**
 * Unit tests for FlowProofAiService: the setting gate, generating and storing an explanation
 * without touching the deterministic result, reuse of a stored explanation, and regeneration.
 * Runs as a Standard User holding the FlowProof_User permission set.
 */
@IsTest
private class FlowProofAiServiceTest {
    @IsTest
    static void shouldRefuseWhenAiIsTurnedOff() {
        FlowProofAiService service = new FlowProofAiService(
            new FlowProofGeminiClient(),
            new FlowProofResultService(),
            FlowProofTestStubs.aiSettings(false)
        );
        FlowProofTestStubs.FixedResponse mock = new FlowProofTestStubs.FixedResponse(200, '{}');
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            service.explain(null, false);
            Assert.fail('Expected FlowProofException while AI is turned off');
        } catch (FlowProofException e) {
            Assert.isTrue(e.getMessage().contains('turned off'), 'The message should say AI is off');
        }
        Assert.isTrue(mock.requests.isEmpty(), 'Nothing is sent while AI is turned off');
    }

    @IsTest
    static void shouldGenerateAndStoreExplanation() {
        System.runAs(flowProofUser()) {
            FlowProofInvestigationResult saved = saveAcme();
            FlowProofTestStubs.FixedResponse mock = new FlowProofTestStubs.FixedResponse(
                200,
                FlowProofTestStubs.geminiResponse(FlowProofTestStubs.geminiAnswer())
            );

            Test.startTest();
            Test.setMock(HttpCalloutMock.class, mock);
            FlowProofAiExplanation explanation = enabledService().explain(saved.investigationId, false);
            Test.stopTest();

            FlowProofInvestigationResult loaded = new FlowProofResultService().load(saved.investigationId);
            Assert.isTrue(explanation.summary.contains('Type'), 'The summary should be returned');
            Assert.areEqual('gemini-3.8-flash', explanation.model, 'The model should be recorded');
            Assert.isFalse(explanation.fieldValuesShared, 'Values were not shared');
            Assert.areEqual(explanation.summary, loaded.aiExplanation.summary, 'The explanation should be stored');
            Assert.areEqual(saved.findings.size(), loaded.findings.size(), 'The deterministic findings are unchanged');
            Assert.isFalse(mock.requests[0].getBody().contains('Acme Expansion'), 'The record name is not sent');
        }
    }

    @IsTest
    static void shouldReuseStoredExplanationUnlessRegenerating() {
        System.runAs(flowProofUser()) {
            FlowProofInvestigationResult saved = saveAcme();
            FlowProofAiExplanation stored = new FlowProofAiExplanation();
            stored.summary = 'Stored explanation';
            new FlowProofResultService().saveAiExplanation(saved.investigationId, stored);
            FlowProofTestStubs.FixedResponse mock = new FlowProofTestStubs.FixedResponse(
                200,
                FlowProofTestStubs.geminiResponse(FlowProofTestStubs.geminiAnswer())
            );

            Test.startTest();
            Test.setMock(HttpCalloutMock.class, mock);
            FlowProofAiExplanation reused = enabledService().explain(saved.investigationId, false);
            Integer callsAfterReuse = mock.requests.size();
            FlowProofAiExplanation regenerated = enabledService().explain(saved.investigationId, true);
            Test.stopTest();

            Assert.areEqual('Stored explanation', reused.summary, 'A stored explanation is reused');
            Assert.areEqual(0, callsAfterReuse, 'Reuse makes no callout');
            Assert.areNotEqual('Stored explanation', regenerated.summary, 'Regenerating replaces it');
        }
    }

    @IsTest
    static void shouldTestConnectionWhileTurnedOff() {
        Test.setMock(HttpCalloutMock.class, new FlowProofTestStubs.FixedResponse(200, '{}'));
        FlowProofAiService service = new FlowProofAiService(
            new FlowProofGeminiClient(),
            new FlowProofResultService(),
            FlowProofTestStubs.aiSettings(false)
        );

        Test.startTest();
        FlowProofConnectionStatus status = service.testConnection();
        Test.stopTest();

        Assert.isTrue(status.connected, 'An admin can test the key before turning AI on');
    }

    private static FlowProofAiService enabledService() {
        return new FlowProofAiService(
            new FlowProofGeminiClient(),
            new FlowProofResultService(),
            FlowProofTestStubs.aiSettings(true)
        );
    }

    private static FlowProofInvestigationResult saveAcme() {
        return new FlowProofResultService()
            .save(FlowProofTestStubs.investigateOpportunity('Acme Expansion', 'Closed Won', 25000));
    }

    /**
     * Creates a FlowProof user; setup DML runs as the current user to avoid mixed-DML errors.
     * @return the user
     */
    private static User flowProofUser() {
        User user;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            user = FlowProofTestDataFactory.createFlowProofUser();
        }
        return user;
    }
}
