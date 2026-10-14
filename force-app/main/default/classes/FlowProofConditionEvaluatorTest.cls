/**
 * Unit tests for FlowProofConditionEvaluator: combining conditions with AND / OR /
 * custom / formula logic, and gating conditions that cannot be evaluated
 * (inaccessible, missing, relationship, unsupported operator). Pure logic: no records.
 */
@IsTest
private class FlowProofConditionEvaluatorTest {
    // ─── The brief's example: Opportunity_Onboarding ─────────────────────

    @IsTest
    static void shouldReturnNotSatisfiedForOnboardingExampleWithBlankRegion() {
        FlowProofFlowModel.FlowStart start = startWith(
            'and',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won')),
                condition(2, 'Amount', 'GreaterThan', FlowProofFlowModel.numberValue(10000)),
                condition(3, 'Region__c', 'EqualTo', FlowProofFlowModel.stringValue('North America'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.conditions[0].outcome,
            'Stage condition should match'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.conditions[1].outcome,
            'Amount condition should match'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.conditions[2].outcome,
            'Region condition should not match'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
            result.overall,
            'One failed AND condition fails the set'
        );
        Assert.isTrue(
            result.overallReason.contains('3'),
            'Reason should name the failing condition: ' + result.overallReason
        );
    }

    // ─── AND ─────────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnSatisfiedWhenAllAndConditionsMatch() {
        FlowProofFlowModel.FlowStart start = startWith(
            'and',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won')),
                condition(2, 'Amount', 'GreaterThan', FlowProofFlowModel.numberValue(10000))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.SATISFIED,
            result.overall,
            'All matching conditions satisfy AND'
        );
        Assert.areEqual('AND', result.logicType, 'Logic type should be AND');
    }

    @IsTest
    static void shouldReturnIndeterminateWhenAndHasUnevaluatedConditionAndNoFailure() {
        FlowProofFlowModel.FlowStart start = startWith(
            'and',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won')),
                condition(2, 'Secret__c', 'EqualTo', FlowProofFlowModel.stringValue('x'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.INDETERMINATE,
            result.overall,
            'An unreadable condition must not be assumed to match'
        );
    }

    @IsTest
    static void shouldReturnNotSatisfiedWhenAndHasFailureAlongsideUnevaluatedCondition() {
        FlowProofFlowModel.FlowStart start = startWith(
            'and',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'Region__c', 'EqualTo', FlowProofFlowModel.stringValue('North America')),
                condition(2, 'Secret__c', 'EqualTo', FlowProofFlowModel.stringValue('x'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
            result.overall,
            'A definite AND failure decides the result'
        );
    }

    @IsTest
    static void shouldTreatBlankLogicAsAnd() {
        FlowProofFlowModel.FlowStart start = startWith(
            null,
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual('AND', result.logicType, 'Blank filter logic defaults to AND');
    }

    // ─── OR ──────────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnSatisfiedWhenAnyOrConditionMatches() {
        FlowProofFlowModel.FlowStart start = startWith(
            'or',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'Region__c', 'EqualTo', FlowProofFlowModel.stringValue('North America')),
                condition(2, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.SATISFIED,
            result.overall,
            'One matching condition satisfies OR'
        );
    }

    @IsTest
    static void shouldReturnNotSatisfiedWhenNoOrConditionMatches() {
        FlowProofFlowModel.FlowStart start = startWith(
            'OR',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'Region__c', 'EqualTo', FlowProofFlowModel.stringValue('North America')),
                condition(2, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Prospecting'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
            result.overall,
            'No matching condition fails OR'
        );
    }

    @IsTest
    static void shouldReturnIndeterminateWhenOrHasNoMatchButUnevaluatedCondition() {
        FlowProofFlowModel.FlowStart start = startWith(
            'or',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'Region__c', 'EqualTo', FlowProofFlowModel.stringValue('North America')),
                condition(2, 'Secret__c', 'EqualTo', FlowProofFlowModel.stringValue('x'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.INDETERMINATE,
            result.overall,
            'The unreadable condition could still satisfy OR'
        );
    }

    // ─── Custom logic, formula, none ─────────────────────────────────────

    @IsTest
    static void shouldReturnIndeterminateButEvaluateEachConditionWhenCustomLogic() {
        FlowProofFlowModel.FlowStart start = startWith(
            '1 AND (2 OR 3)',
            new List<FlowProofFlowModel.Condition>{
                condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won')),
                condition(2, 'Amount', 'GreaterThan', FlowProofFlowModel.numberValue(10000)),
                condition(3, 'Region__c', 'EqualTo', FlowProofFlowModel.stringValue('North America'))
            }
        );

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.INDETERMINATE,
            result.overall,
            'Custom logic is not evaluated yet'
        );
        Assert.areEqual('CUSTOM', result.logicType, 'Logic type should be CUSTOM');
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.conditions[0].outcome,
            'Individual conditions are still evaluated'
        );
    }

    @IsTest
    static void shouldReturnIndeterminateWhenFilterFormulaPresent() {
        FlowProofFlowModel.FlowStart start = startWith(null, new List<FlowProofFlowModel.Condition>());
        start.filterFormula = 'ISPICKVAL({!$Record.StageName}, "Closed Won")';

        FlowProofEvaluationResult result = evaluate(start, onboardingSnapshot());

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.INDETERMINATE,
            result.overall,
            'Formula conditions are not evaluated'
        );
        Assert.areEqual('FORMULA', result.logicType, 'Logic type should be FORMULA');
    }

    @IsTest
    static void shouldReturnSatisfiedWhenNoConditions() {
        FlowProofEvaluationResult result = evaluate(
            startWith(null, new List<FlowProofFlowModel.Condition>()),
            onboardingSnapshot()
        );

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.SATISFIED,
            result.overall,
            'No conditions means every save qualifies'
        );
        Assert.areEqual('NONE', result.logicType, 'Logic type should be NONE');
    }

    // ─── Gating ──────────────────────────────────────────────────────────

    @IsTest
    static void shouldReportInaccessibleWithoutValueWhenUserCannotReadField() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, 'Secret__c', 'EqualTo', FlowProofFlowModel.stringValue('x'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.INACCESSIBLE,
            result.outcome,
            'Unreadable field must be reported'
        );
        Assert.isNull(result.actualDisplay, 'An unreadable value must never be displayed');
    }

    @IsTest
    static void shouldReportMissingWhenFieldDoesNotExist() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, 'Deleted__c', 'EqualTo', FlowProofFlowModel.stringValue('x'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MISSING,
            result.outcome,
            'Nonexistent field must be reported'
        );
    }

    @IsTest
    static void shouldReportUnsupportedWhenFieldIsRelationshipPath() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, 'Account.Industry', 'EqualTo', FlowProofFlowModel.stringValue('Banking'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Relationship paths are not evaluated'
        );
    }

    @IsTest
    static void shouldReportUnsupportedWithValueWhenOperatorNotSupported() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, 'StageName', 'Contains', FlowProofFlowModel.stringValue('Won'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Contains is not supported yet'
        );
        Assert.areEqual('Closed Won', result.actualDisplay, 'The readable value is still shown');
    }

    @IsTest
    static void shouldReportUnsupportedWhenOperatorMissing() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, 'StageName', null, FlowProofFlowModel.stringValue('Closed Won'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'A condition without an operator cannot be evaluated'
        );
    }

    @IsTest
    static void shouldReportUnsupportedWhenFieldValueNotCollected() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, 'Description', 'EqualTo', FlowProofFlowModel.stringValue('x'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Uncollected fields are never assumed blank'
        );
    }

    @IsTest
    static void shouldReportUnsupportedWhenConditionHasNoField() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, '', 'EqualTo', FlowProofFlowModel.stringValue('x'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'A condition without a field cannot be evaluated'
        );
    }

    @IsTest
    static void shouldTreatNullConditionValueAsNoValue() {
        FlowProofFlowModel.Condition noValue = condition(1, 'StageName', 'EqualTo', null);
        noValue.value = null;

        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(noValue);

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'A null value is reported, not dereferenced'
        );
    }

    @IsTest
    static void shouldMatchFieldNamesCaseInsensitively() {
        FlowProofEvaluationResult.ConditionResult result = evaluateSingle(
            condition(1, 'stagename', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won'))
        );

        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'Apex field names are case-insensitive'
        );
    }

    // ─── Input validation ────────────────────────────────────────────────

    @IsTest
    static void shouldThrowWhenStartIsNull() {
        try {
            new FlowProofConditionEvaluator().evaluate(null, onboardingSnapshot());
            Assert.fail('Expected IllegalArgumentException for a null start element');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('required'), 'Message should explain the missing input');
        }
    }

    @IsTest
    static void shouldThrowWhenSnapshotIsNull() {
        try {
            new FlowProofConditionEvaluator().evaluate(new FlowProofFlowModel.FlowStart(), null);
            Assert.fail('Expected IllegalArgumentException for a null snapshot');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('required'), 'Message should explain the missing input');
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    /**

     * Opportunity: Stage = Closed Won, Amount = 25000, Region blank, Secret unreadable, Deleted missing.

     * @return the snapshot

     */
    private static FlowProofRecordSnapshot onboardingSnapshot() {
        FlowProofRecordSnapshot snapshot = new FlowProofRecordSnapshot('Opportunity');
        snapshot.putValue('StageName', 'PICKLIST', 'Closed Won');
        snapshot.putValue('Amount', 'CURRENCY', 25000);
        snapshot.putValue('Region__c', 'PICKLIST', null);
        snapshot.putInaccessible('Secret__c');
        snapshot.putMissing('Deleted__c');
        return snapshot;
    }

    private static FlowProofFlowModel.FlowStart startWith(String logic, List<FlowProofFlowModel.Condition> conditions) {
        FlowProofFlowModel.FlowStart start = new FlowProofFlowModel.FlowStart();
        start.objectApiName = 'Opportunity';
        start.filterLogic = logic;
        start.filters = conditions;
        return start;
    }

    private static FlowProofFlowModel.Condition condition(
        Integer index,
        String field,
        String operator,
        FlowProofFlowModel.ConditionValue value
    ) {
        return new FlowProofFlowModel.Condition(index, field, operator, value);
    }

    private static FlowProofEvaluationResult evaluate(
        FlowProofFlowModel.FlowStart start,
        FlowProofRecordSnapshot snapshot
    ) {
        Test.startTest();
        FlowProofEvaluationResult result = new FlowProofConditionEvaluator().evaluate(start, snapshot);
        Test.stopTest();
        return result;
    }

    private static FlowProofEvaluationResult.ConditionResult evaluateSingle(FlowProofFlowModel.Condition condition) {
        return evaluate(startWith('and', new List<FlowProofFlowModel.Condition>{ condition }), onboardingSnapshot())
            .conditions[0];
    }
}
