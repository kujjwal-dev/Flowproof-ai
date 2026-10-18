/**
 * Unit tests for FlowProofDebugLogParser, using log lines in the format Salesforce writes for
 * record-triggered Flows (Workflow at FINER) and validation rules (Validation at INFO).
 */
@IsTest
private class FlowProofDebugLogParserTest {
    private static final String VERSION_15 = '301' + '0'.repeat(11) + '1';

    @IsTest
    static void shouldReadFlowThatRanForRecord() {
        Id recordId = fakeOpportunityId(1);

        FlowProofDebugLogParser.ParsedLog parsed = new FlowProofDebugLogParser()
            .parse(FlowProofTestStubs.flowSaveLog(recordId, 'Opportunity Onboarding', VERSION_15));

        List<FlowProofDebugLogParser.Interview> interviews = parsed.interviewsFor(recordId);
        Assert.areEqual(1, interviews.size(), 'One Flow ran for the record');
        FlowProofDebugLogParser.Interview interview = interviews[0];
        Assert.areEqual('Opportunity Onboarding', interview.label, 'The Flow label is read');
        Assert.areEqual(VERSION_15, interview.versionId, 'The Flow version is read');
        Assert.isTrue(interview.finished, 'The interview finished');
        Assert.areEqual(
            new List<String>{ '"Is_Large" (Decision)', '"Create_Onboarding_Task" (Create Records)' },
            interview.elements,
            'Elements are listed once each, in order'
        );
        Assert.areEqual(new List<String>{ 'Large_Deal' }, interview.outcomes, 'Taken outcomes are listed');
        Assert.isTrue(parsed.flowObjects.contains('opportunity'), 'The object whose Flows ran is known');
        Assert.isTrue(parsed.mentionsRecord(Id.valueOf(String.valueOf(recordId).left(15))), '15-character Ids match');
        Assert.isFalse(parsed.mentionsRecord(fakeOpportunityId(2)), 'Other records do not match');
    }

    @IsTest
    static void shouldReadErrorsAndValidationFailures() {
        Id recordId = fakeOpportunityId(3);
        String interview = 'abc-1';
        String log = String.join(
            new List<String>{
                '10:00:00.1 (1)|CODE_UNIT_STARTED|[EXTERNAL]|Flow:Opportunity',
                '10:00:00.1 (2)|FLOW_CREATE_INTERVIEW_BEGIN|00D|300|' + VERSION_15,
                '10:00:00.1 (3)|FLOW_CREATE_INTERVIEW_END|' +
                interview +
                '|Broken Flow',
                '10:00:00.1 (4)|FLOW_START_INTERVIEW_BEGIN|' +
                interview +
                '|Broken Flow',
                '10:00:00.1 (5)|FLOW_VALUE_ASSIGNMENT|' +
                interview +
                '|$Record|{Id=' +
                recordId +
                '}',
                '10:00:00.1 (6)|FLOW_ELEMENT_BEGIN|' +
                interview +
                '|FlowRecordUpdate|Update_Account',
                '10:00:00.1 (7)|FLOW_ELEMENT_ERROR|Required fields are missing: [Name]|FlowRecordUpdate|Update_Account',
                '10:00:00.1 (8)|VALIDATION_RULE|03d000000000001|Amount_Required',
                '10:00:00.1 (9)|VALIDATION_FAIL',
                '10:00:00.1 (10)|VALIDATION_ERROR|Amount is required for won deals.',
                'not a log line'
            },
            '\n'
        );

        FlowProofDebugLogParser.ParsedLog parsed = new FlowProofDebugLogParser().parse(log);

        FlowProofDebugLogParser.Interview broken = parsed.interviewsFor(recordId)[0];
        Assert.isFalse(broken.finished, 'A failed interview does not finish');
        Assert.isTrue(broken.errors[0].contains('Required fields are missing'), 'The error is kept: ' + broken.errors);
        Assert.areEqual(new List<String>{ 'Amount_Required' }, parsed.validationFailures, 'Failed rules are named');
        Assert.areEqual(
            new List<String>{ 'Amount is required for won deals.' },
            parsed.validationMessages,
            'Validation messages are kept'
        );
    }

    @IsTest
    static void shouldReturnNothingForEmptyOrUnrelatedLogs() {
        FlowProofDebugLogParser.ParsedLog empty = new FlowProofDebugLogParser().parse('');
        FlowProofDebugLogParser.ParsedLog noFlows = new FlowProofDebugLogParser()
            .parse('10:00:00.1 (1)|CODE_UNIT_STARTED|[EXTERNAL]|Flow:Opportunity\n10:00:00.1 (2)|EXECUTION_FINISHED');

        Assert.isTrue(empty.interviews.isEmpty(), 'An empty log has no interviews');
        Assert.isTrue(noFlows.interviews.isEmpty(), 'A save where no Flow started has no interviews');
        Assert.isTrue(noFlows.flowObjects.contains('opportunity'), 'The save of the object is still visible');
    }

    private static Id fakeOpportunityId(Integer suffix) {
        return Id.valueOf('006' + '0'.repeat(11) + String.valueOf(suffix));
    }
}
