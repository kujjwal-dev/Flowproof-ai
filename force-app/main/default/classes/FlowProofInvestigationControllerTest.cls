/**
 * Unit tests for FlowProofInvestigationController: each entry point, and that errors reach the
 * user as safe AuraHandledException messages. The investigate-and-save path uses stubbed Flow
 * metadata; catalog entry points run real (read-only) queries.
 */
@IsTest
private class FlowProofInvestigationControllerTest {
    @IsTest
    static void shouldRunAndSaveInvestigation() {
        System.runAs(flowProofUser()) {
            Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
                'Acme Expansion',
                'Closed Won',
                25000,
                true
            );
            useStubbedInvestigation();

            Test.startTest();
            FlowProofInvestigationResult result = FlowProofInvestigationController.runInvestigation(
                'Opportunity',
                opportunity.Id,
                'Opportunity_Onboarding',
                'An onboarding Task should be created'
            );
            Test.stopTest();

            Assert.isNotNull(result.investigationId, 'The investigation should be saved');
            Assert.areEqual(
                'CONDITIONS_NOT_MET',
                result.findings[0].ruleCode,
                'The failing conditions are the top finding'
            );
            Assert.areEqual(
                'An onboarding Task should be created',
                result.expectedOutcome,
                'The expected outcome should be kept'
            );
        }
    }

    @IsTest
    static void shouldListAndLoadSavedInvestigations() {
        System.runAs(flowProofUser()) {
            Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
                'History Test',
                'Closed Won',
                25000,
                true
            );
            useStubbedInvestigation();
            FlowProofInvestigationResult saved = FlowProofInvestigationController.runInvestigation(
                'Opportunity',
                opportunity.Id,
                'Opportunity_Onboarding',
                null
            );

            Test.startTest();
            List<FlowProofInvestigationSummary> recent = FlowProofInvestigationController.getRecentInvestigations(5);
            FlowProofInvestigationResult loaded = FlowProofInvestigationController.getInvestigation(
                saved.investigationId
            );
            Test.stopTest();

            Assert.areEqual(1, recent.size(), 'The saved investigation should be listed');
            Assert.areEqual(saved.investigationName, loaded.investigationName, 'The saved investigation should load');
        }
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

    @IsTest
    static void shouldShowFlowProofMessageForUnknownFlow() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
            'Unknown Flow Test',
            'Closed Won',
            25000,
            true
        );
        try {
            FlowProofInvestigationController.runInvestigation(
                'Opportunity',
                opportunity.Id,
                'FlowProof_No_Such_Flow',
                null
            );
            Assert.fail('Expected AuraHandledException for an unknown Flow');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('FlowProof_No_Such_Flow'),
                'Message should name the Flow: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void shouldShowValidationMessageForIncompleteInput() {
        try {
            FlowProofInvestigationController.runInvestigation('Opportunity', null, 'Opportunity_Onboarding', null);
            Assert.fail('Expected AuraHandledException for a missing record');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Choose'), 'Message should say what to choose: ' + e.getMessage());
        }
    }

    @IsTest
    static void shouldReportConnectedWhenOrgApiAnswers() {
        Test.setMock(HttpCalloutMock.class, new FlowProofTestStubs.FixedResponse(200, '{"size":1,"records":[]}'));

        Test.startTest();
        FlowProofConnectionStatus status = FlowProofInvestigationController.testConnection();
        Test.stopTest();

        Assert.isTrue(status.connected, 'HTTP 200 means connected');
        Assert.areEqual('CONNECTED', status.status, 'Status code should be CONNECTED');
    }

    @IsTest
    static void shouldReportNotAuthorizedWhenOrgApiRefuses() {
        Test.setMock(
            HttpCalloutMock.class,
            new FlowProofTestStubs.FixedResponse(401, '[{"errorCode":"INVALID_SESSION_ID"}]')
        );

        Test.startTest();
        FlowProofConnectionStatus status = FlowProofInvestigationController.testConnection();
        Test.stopTest();

        Assert.isFalse(status.connected, 'HTTP 401 means not connected');
        Assert.isTrue(status.message.contains('Allow Access'), 'Message should explain how to authorize');
    }

    @IsTest
    static void shouldCheckAllFlowsOnObject() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Sweep Test', 'Closed Won', 25000, true);
        useStubbedInvestigation();

        Test.startTest();
        FlowProofSweepResult sweep = FlowProofInvestigationController.checkAllFlows('Opportunity', opportunity.Id);
        Test.stopTest();

        Assert.areEqual(1, sweep.rows.size(), 'The stubbed Flow should be checked');
        Assert.areEqual('NOT_SATISFIED', sweep.rows[0].overallCode, 'Blank Type fails the conditions');
    }

    @IsTest
    static void shouldShowValidationMessageForIncompleteSweep() {
        try {
            FlowProofInvestigationController.checkAllFlows('Opportunity', null);
            Assert.fail('Expected AuraHandledException for a sweep without a record');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('record'), 'Message should say what is missing: ' + e.getMessage());
        }
    }

    @IsTest
    static void shouldExplainThatAiIsOff() {
        FlowProofInvestigationController.aiServiceOverride = new FlowProofAiService(
            new FlowProofGeminiClient(),
            new FlowProofResultService(),
            FlowProofTestStubs.aiSettings(false)
        );
        try {
            FlowProofInvestigationController.requestAiExplanation(null, false);
            Assert.fail('Expected AuraHandledException while AI is turned off');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('turned off'), 'Message should say AI is off: ' + e.getMessage());
        }
    }

    @IsTest
    static void shouldTestAiConnection() {
        Test.setMock(HttpCalloutMock.class, new FlowProofTestStubs.FixedResponse(200, '{}'));
        FlowProofInvestigationController.aiServiceOverride = new FlowProofAiService(
            new FlowProofGeminiClient(),
            new FlowProofResultService(),
            FlowProofTestStubs.aiSettings(true)
        );

        Test.startTest();
        FlowProofConnectionStatus status = FlowProofInvestigationController.testAiConnection();
        Test.stopTest();

        Assert.isTrue(status.connected, 'HTTP 200 means Gemini is reachable');
    }

    @IsTest
    static void shouldReturnSettingsWithAiOffByDefault() {
        Test.startTest();
        FlowProofSettings settings = FlowProofInvestigationController.getSettings();
        Test.stopTest();

        Assert.isFalse(settings.aiEnabled, 'AI explanations are off by default');
    }

    @IsTest
    static void shouldListObjectsAndFlowsWithRealQueries() {
        Test.startTest();
        List<FlowProofObjectOption> objects = FlowProofInvestigationController.getObjectOptions();
        List<FlowProofFlowSummary> flows = FlowProofInvestigationController.getFlows('FlowProof_No_Such_Object__c');
        Test.stopTest();

        for (FlowProofObjectOption option : objects) {
            Assert.isTrue(option.flowCount > 0, 'Every listed object has at least one Flow: ' + option.apiName);
        }
        Assert.isTrue(flows.isEmpty(), 'An unknown object has no Flows');
    }

    @IsTest
    static void shouldShowValidationMessageForBlankObject() {
        try {
            FlowProofInvestigationController.getFlows('');
            Assert.fail('Expected AuraHandledException for a blank object name');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('object'), 'Message should explain the problem: ' + e.getMessage());
        }
    }

    private static void useStubbedInvestigation() {
        FlowProofInvestigationController.investigationServiceOverride = FlowProofTestStubs.investigationService(
            FlowProofTestStubs.activeOpportunityFlow('Opportunity_Onboarding'),
            FlowProofTestStubs.onboardingStart()
        );
    }
}
