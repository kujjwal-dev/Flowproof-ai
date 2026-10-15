/**
 * Unit tests for FlowProofResultService: saving results and findings in user mode, reading them
 * back, listing history, and refusing users without FlowProof permissions. Saving tests run as a
 * Standard User holding the shipped FlowProof_User permission set.
 */
@IsTest
private class FlowProofResultServiceTest {
    @IsTest
    static void shouldSaveInvestigationAndFindings() {
        FlowProofInvestigationResult saved;
        Integer findingCount;
        System.runAs(flowProofUser()) {
            FlowProofInvestigationResult result = investigateAcme();
            findingCount = result.findings.size();
            Test.startTest();
            saved = new FlowProofResultService().save(result);
            Test.stopTest();
        }

        FlowProof_Investigation__c row = [
            SELECT Flow_Api_Name__c, Overall_Result__c, Conditions_Read__c, Top_Finding__c, Finding_Count__c
            FROM FlowProof_Investigation__c
            WHERE Id = :saved.investigationId
            WITH SYSTEM_MODE
        ];
        Assert.isTrue(saved.investigationName.startsWith('INV-'), 'Name should be the auto-number');
        Assert.areEqual('Opportunity_Onboarding', row.Flow_Api_Name__c, 'Flow should be stored');
        Assert.areEqual('NOT_SATISFIED', row.Overall_Result__c, 'Overall result should be stored');
        Assert.isTrue(row.Conditions_Read__c, 'Conditions were read');
        Assert.areEqual(saved.findings[0].title, row.Top_Finding__c, 'Top finding should be stored');
        Assert.areEqual(findingCount, row.Finding_Count__c.intValue(), 'Every finding should be saved');
    }

    @IsTest
    static void shouldLoadSavedResult() {
        System.runAs(flowProofUser()) {
            FlowProofInvestigationResult saved = new FlowProofResultService().save(investigateAcme());

            Test.startTest();
            FlowProofInvestigationResult loaded = new FlowProofResultService().load(saved.investigationId);
            Test.stopTest();

            Assert.areEqual(saved.investigationName, loaded.investigationName, 'Name should be set on load');
            Assert.areEqual(
                FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
                loaded.evaluation.overall,
                'Evaluation should round-trip'
            );
            Assert.areEqual(3, loaded.evaluation.conditions.size(), 'Conditions should round-trip');
            Assert.areEqual(saved.findings.size(), loaded.findings.size(), 'Findings should round-trip');
            Assert.areEqual(
                FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
                loaded.findings[0].category,
                'Enums should round-trip'
            );
            Assert.areEqual('SUPPORTED_HYPOTHESIS', loaded.findings[0].categoryCode, 'Codes should round-trip');
            Assert.areEqual('NOT_SATISFIED', loaded.evaluation.overallCode, 'Codes should round-trip');
            Assert.areEqual('Acme Expansion', loaded.recordName, 'The record name should round-trip');
        }
    }

    @IsTest
    static void shouldListRecentInvestigations() {
        System.runAs(flowProofUser()) {
            FlowProofResultService service = new FlowProofResultService();
            service.save(investigateAcme());
            service.save(investigateAcme());

            Test.startTest();
            List<FlowProofInvestigationSummary> recent = service.listRecent(10);
            Test.stopTest();

            Assert.areEqual(2, recent.size(), 'Both investigations should be listed');
            Assert.areEqual('Opportunity Onboarding', recent[0].flowLabel, 'Flow label should be listed');
            Assert.isTrue(recent[0].findingCount > 0, 'Finding count should be listed');
        }
    }

    @IsTest
    static void shouldUseDefaultPageSizeWhenNoneGiven() {
        System.runAs(flowProofUser()) {
            Test.startTest();
            List<FlowProofInvestigationSummary> recent = new FlowProofResultService().listRecent(null);
            Test.stopTest();

            Assert.isTrue(recent.isEmpty(), 'No investigations exist yet');
        }
    }

    @IsTest
    static void shouldRefuseUserWithoutFlowProofPermission() {
        FlowProofInvestigationResult result = investigateAcme();
        User outsider;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            outsider = FlowProofTestDataFactory.createMinimumAccessUser();
        }

        System.runAs(outsider) {
            try {
                new FlowProofResultService().save(result);
                Assert.fail('Expected FlowProofException for a user without FlowProof permissions');
            } catch (FlowProofException e) {
                Assert.isTrue(e.getMessage().contains('FlowProof User'), 'Message should name the permission set');
            }
        }
    }

    @IsTest
    static void shouldThrowWhenInvestigationMissing() {
        System.runAs(flowProofUser()) {
            FlowProofInvestigationResult saved = new FlowProofResultService().save(investigateAcme());
            Database.delete(new FlowProof_Investigation__c(Id = saved.investigationId), AccessLevel.SYSTEM_MODE);

            try {
                new FlowProofResultService().load(saved.investigationId);
                Assert.fail('Expected FlowProofException for a deleted investigation');
            } catch (FlowProofException e) {
                Assert.isTrue(e.getMessage().contains('not found'), 'Message should say it was not found');
            }
        }
    }

    @IsTest
    static void shouldRejectNullResult() {
        try {
            new FlowProofResultService().save(null);
            Assert.fail('Expected IllegalArgumentException for a null result');
        } catch (IllegalArgumentException e) {
            Assert.isNotNull(e.getMessage(), 'Message should explain the problem');
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

    /**
     * Investigates a synthetic Opportunity (Closed Won, 25000, blank Type) against stubbed Flow metadata.
     * @return the unsaved result
     */
    private static FlowProofInvestigationResult investigateAcme() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(
            'Acme Expansion',
            'Closed Won',
            25000,
            true
        );
        FlowProofInvestigationService service = FlowProofTestStubs.investigationService(
            FlowProofTestStubs.activeOpportunityFlow('Opportunity_Onboarding'),
            FlowProofTestStubs.onboardingStart()
        );
        return service.investigate(
            new FlowProofInvestigationRequest('Opportunity', opportunity.Id, 'Opportunity_Onboarding')
        );
    }
}
