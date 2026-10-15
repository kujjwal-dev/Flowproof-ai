/**
 * Unit tests for FlowProofRecordService: values and types of readable fields, missing and
 * inaccessible fields, object access, and input validation. Uses synthetic Opportunities and
 * a Minimum Access user granted exactly the access each test needs.
 */
@IsTest
private class FlowProofRecordServiceTest {
    private static final String STAGE = 'Closed Won';
    private static final Decimal AMOUNT = 25000;

    @IsTest
    static void shouldReadRequestedFieldValuesWithTypes() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Acme Expansion', STAGE, AMOUNT, true);

        Test.startTest();
        FlowProofRecordSnapshot snapshot = new FlowProofRecordService()
            .getSnapshot('Opportunity', opportunity.Id, new Set<String>{ 'StageName', 'Amount', 'CloseDate' });
        Test.stopTest();

        Assert.areEqual(STAGE, snapshot.getField('StageName').value, 'Stage should be read');
        Assert.areEqual('PICKLIST', snapshot.getField('StageName').fieldType, 'Stage type should come from describe');
        Assert.isTrue((Decimal) snapshot.getField('Amount').value == AMOUNT, 'Amount should be read');
        Assert.areEqual('CURRENCY', snapshot.getField('Amount').fieldType, 'Amount type should come from describe');
        Assert.areEqual('DATE', snapshot.getField('CloseDate').fieldType, 'Close date type should come from describe');
        Assert.areEqual('Acme Expansion', snapshot.recordName, 'The record name should be read for display');
    }

    @IsTest
    static void shouldMatchFieldNamesCaseInsensitively() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Case Test', STAGE, AMOUNT, true);

        Test.startTest();
        FlowProofRecordSnapshot snapshot = new FlowProofRecordService()
            .getSnapshot('opportunity', opportunity.Id, new Set<String>{ 'stagename' });
        Test.stopTest();

        Assert.areEqual(STAGE, snapshot.getField('StageName').value, 'Lower-case names should resolve to the field');
    }

    @IsTest
    static void shouldReportMissingField() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Missing Test', STAGE, AMOUNT, true);

        Test.startTest();
        FlowProofRecordSnapshot snapshot = new FlowProofRecordService()
            .getSnapshot('Opportunity', opportunity.Id, new Set<String>{ 'FlowProof_Not_A_Field__c' });
        Test.stopTest();

        Assert.isFalse(snapshot.getField('FlowProof_Not_A_Field__c').exists, 'A field the object lacks is missing');
    }

    @IsTest
    static void shouldSkipRelationshipPaths() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Path Test', STAGE, AMOUNT, true);

        Test.startTest();
        FlowProofRecordSnapshot snapshot = new FlowProofRecordService()
            .getSnapshot('Opportunity', opportunity.Id, new Set<String>{ 'Account.Industry' });
        Test.stopTest();

        Assert.isNull(snapshot.getField('Account.Industry'), 'Relationship paths are left for the evaluator to report');
    }

    @IsTest
    static void shouldReportInaccessibleFieldWithoutReadingIt() {
        User analyst = minimumAccessUser(new List<String>{ 'Amount' });
        FlowProofRecordSnapshot snapshot;

        System.runAs(analyst) {
            Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('FLS Test', STAGE, AMOUNT, false);
            opportunity.NextStep = 'Call the CFO';
            Database.insert(opportunity, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            snapshot = new FlowProofRecordService()
                .getSnapshot('Opportunity', opportunity.Id, new Set<String>{ 'Amount', 'NextStep' });
            Test.stopTest();
        }

        Assert.isFalse(snapshot.getField('NextStep').isAccessible, 'NextStep is not readable for this user');
        Assert.isNull(snapshot.getField('NextStep').value, 'An unreadable value must never be collected');
        Assert.isTrue((Decimal) snapshot.getField('Amount').value == AMOUNT, 'Readable fields are still collected');
    }

    @IsTest
    static void shouldDenyUserWithoutObjectAccess() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Object Access Test', STAGE, AMOUNT, true);
        User outsider = minimumAccessUser(null);

        System.runAs(outsider) {
            try {
                new FlowProofRecordService().getSnapshot('Opportunity', opportunity.Id, new Set<String>{ 'StageName' });
                Assert.fail('Expected FlowProofException for a user without Opportunity access');
            } catch (FlowProofException e) {
                Assert.isTrue(
                    e.getMessage().contains('Opportunities'),
                    'Message should name the object: ' + e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void shouldThrowWhenRecordNotFound() {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity('Deleted Test', STAGE, AMOUNT, true);
        Database.delete(opportunity, AccessLevel.SYSTEM_MODE);

        try {
            new FlowProofRecordService().getSnapshot('Opportunity', opportunity.Id, new Set<String>{ 'StageName' });
            Assert.fail('Expected FlowProofException for a deleted record');
        } catch (FlowProofException e) {
            Assert.isTrue(e.getMessage().contains('not found'), 'Message should say the record was not found');
        }
    }

    @IsTest
    static void shouldRejectIdOfAnotherObject() {
        try {
            new FlowProofRecordService()
                .getSnapshot('Opportunity', UserInfo.getUserId(), new Set<String>{ 'StageName' });
            Assert.fail('Expected FlowProofException for a User Id passed as an Opportunity');
        } catch (FlowProofException e) {
            Assert.isTrue(e.getMessage().contains('Opportunity'), 'Message should name the expected object');
        }
    }

    @IsTest
    static void shouldRejectUnknownObject() {
        try {
            new FlowProofRecordService()
                .getSnapshot('FlowProof_No_Such_Object__c', UserInfo.getUserId(), new Set<String>{ 'Name' });
            Assert.fail('Expected FlowProofException for an unknown object');
        } catch (FlowProofException e) {
            Assert.isTrue(e.getMessage().contains('FlowProof_No_Such_Object__c'), 'Message should name the object');
        }
    }

    @IsTest
    static void shouldRejectMissingRecordId() {
        try {
            new FlowProofRecordService().getSnapshot('Opportunity', null, new Set<String>{ 'StageName' });
            Assert.fail('Expected IllegalArgumentException for a missing record Id');
        } catch (IllegalArgumentException e) {
            Assert.isNotNull(e.getMessage(), 'Message should explain the problem');
        }
    }

    /**
     * Creates a Minimum Access user, optionally granted Opportunity access with the given readable fields.
     * Setup DML runs as the current user to avoid mixed-DML errors.
     * @param readableFields Opportunity fields to grant read on, or null for no Opportunity access
     * @return the user
     */
    private static User minimumAccessUser(List<String> readableFields) {
        User user;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            user = FlowProofTestDataFactory.createMinimumAccessUser();
            if (readableFields != null) {
                FlowProofTestDataFactory.grantOpportunityAccess(user.Id, readableFields);
            }
        }
        return user;
    }
}
