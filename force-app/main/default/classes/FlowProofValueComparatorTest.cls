/**
 * Unit tests for FlowProofValueComparator: every supported operator against each
 * field category, blank values, and the cases reported as UNCERTAIN or UNSUPPORTED.
 * Pure logic: no records, no org data.
 */
@IsTest
private class FlowProofValueComparatorTest {
    private static final String FIELD = 'Test_Field__c';

    // ─── Text ────────────────────────────────────────────────────────────

    @IsTest
    static void shouldMatchWhenTextEqualsExactly() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue('Closed Won'),
            'PICKLIST',
            'Closed Won'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'Identical picklist values should match'
        );
    }

    @IsTest
    static void shouldNotMatchWhenTextDiffers() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue('Closed Won'),
            'PICKLIST',
            'Prospecting'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.outcome,
            'Different picklist values should not match'
        );
        Assert.areEqual('Prospecting', result.actualDisplay, 'Actual value should be displayed as-is');
    }

    @IsTest
    static void shouldBeUncertainWhenTextDiffersOnlyByCase() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue('Closed Won'),
            'STRING',
            'closed won'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNCERTAIN,
            result.outcome,
            'Case sensitivity is unverified, so the result must not be guessed'
        );
    }

    @IsTest
    static void shouldBeUncertainWhenBlankComparedToEmptyText() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue(''),
            'STRING',
            null
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNCERTAIN,
            result.outcome,
            'Blank vs empty-text semantics are unverified'
        );
    }

    @IsTest
    static void shouldNotMatchWhenBlankFieldComparedToText() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue('North America'),
            'PICKLIST',
            null
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.outcome,
            'A blank field cannot equal a non-empty value'
        );
        Assert.areEqual('(blank)', result.actualDisplay, 'Blank values should display as (blank)');
    }

    @IsTest
    static void shouldMatchWhenNotEqualToAndTextDiffers() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'NotEqualTo',
            FlowProofFlowModel.stringValue('Closed Lost'),
            'PICKLIST',
            'Closed Won'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'Different values satisfy NotEqualTo'
        );
    }

    @IsTest
    static void shouldNotMatchWhenNotEqualToAndTextSame() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'NotEqualTo',
            FlowProofFlowModel.stringValue('Closed Won'),
            'PICKLIST',
            'Closed Won'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.outcome,
            'Equal values fail NotEqualTo'
        );
    }

    @IsTest
    static void shouldMatchWithStatedAssumptionWhenNotEqualToAndFieldBlank() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'NotEqualTo',
            FlowProofFlowModel.stringValue('Closed Won'),
            'PICKLIST',
            null
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'A blank field differs from a non-empty value'
        );
        Assert.isTrue(
            result.reason.contains('assumption'),
            'The unverified blank semantics must be stated: ' + result.reason
        );
    }

    @IsTest
    static void shouldMatchWhen15And18CharacterIdsReferToSameRecord() {
        String fullId = UserInfo.getUserId();
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue(fullId.left(15)),
            'REFERENCE',
            fullId
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            '15- and 18-character Ids of the same record should match'
        );
    }

    // ─── Numbers ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldMatchWhenNumberEqualsWithDifferentScale() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.numberValue(25000),
            'CURRENCY',
            25000.00
        );
        Assert.areEqual(FlowProofEvaluationResult.ConditionOutcome.MATCH, result.outcome, '25000.00 equals 25000');
        Assert.areEqual('25000', result.actualDisplay, 'Trailing zeros should be stripped for display');
    }

    @IsTest
    static void shouldMatchWhenIntegerFieldEqualsNumber() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.numberValue(50),
            'INTEGER',
            50
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'Integer field values compare numerically'
        );
    }

    @IsTest
    static void shouldMatchWhenGreaterThan() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'GreaterThan',
            FlowProofFlowModel.numberValue(10000),
            'CURRENCY',
            25000
        );
        Assert.areEqual(FlowProofEvaluationResult.ConditionOutcome.MATCH, result.outcome, '25000 > 10000');
    }

    @IsTest
    static void shouldNotMatchWhenGreaterThanAtBoundary() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'GreaterThan',
            FlowProofFlowModel.numberValue(10000),
            'CURRENCY',
            10000
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.outcome,
            '10000 is not greater than 10000'
        );
    }

    @IsTest
    static void shouldMatchWhenGreaterThanOrEqualAtBoundary() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'GreaterThanOrEqualTo',
            FlowProofFlowModel.numberValue(10000),
            'CURRENCY',
            10000
        );
        Assert.areEqual(FlowProofEvaluationResult.ConditionOutcome.MATCH, result.outcome, '10000 >= 10000');
    }

    @IsTest
    static void shouldMatchWhenLessThan() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'LessThan',
            FlowProofFlowModel.numberValue(50),
            'PERCENT',
            20
        );
        Assert.areEqual(FlowProofEvaluationResult.ConditionOutcome.MATCH, result.outcome, '20 < 50');
    }

    @IsTest
    static void shouldMatchWhenLessThanOrEqualAtBoundary() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'LessThanOrEqualTo',
            FlowProofFlowModel.numberValue(50),
            'DOUBLE',
            50
        );
        Assert.areEqual(FlowProofEvaluationResult.ConditionOutcome.MATCH, result.outcome, '50 <= 50');
    }

    @IsTest
    static void shouldNotMatchWithStatedAssumptionWhenOrderingFieldBlank() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'GreaterThan',
            FlowProofFlowModel.numberValue(10000),
            'CURRENCY',
            null
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.outcome,
            'A blank amount does not satisfy > 10000'
        );
        Assert.isTrue(
            result.reason.contains('assumption'),
            'The unverified blank semantics must be stated: ' + result.reason
        );
    }

    @IsTest
    static void shouldBeUnsupportedWhenNumberFieldHoldsNonNumericValue() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.numberValue(5),
            'CURRENCY',
            'not a number'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Unreadable values must not be compared'
        );
    }

    // ─── Dates, datetimes, booleans ──────────────────────────────────────

    @IsTest
    static void shouldMatchWhenDateLessThan() {
        Date closeDate = Date.newInstance(2026, 10, 1);
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'LessThan',
            FlowProofFlowModel.dateValue(closeDate.addDays(1)),
            'DATE',
            closeDate
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'An earlier date is less than a later date'
        );
    }

    @IsTest
    static void shouldMatchWhenDatetimeGreaterThan() {
        Datetime threshold = Datetime.newInstanceGmt(2026, 10, 1, 9, 0, 0);
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'GreaterThan',
            FlowProofFlowModel.dateTimeValue(threshold),
            'DATETIME',
            threshold.addMinutes(1)
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'A later datetime is greater'
        );
        Assert.areEqual('2026-10-01T09:01:00Z', result.actualDisplay, 'Datetimes display in ISO-8601 GMT');
    }

    @IsTest
    static void shouldMatchWhenBooleanEqualsTrue() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.booleanValue(true),
            'BOOLEAN',
            true
        );
        Assert.areEqual(FlowProofEvaluationResult.ConditionOutcome.MATCH, result.outcome, 'Checked box equals true');
    }

    @IsTest
    static void shouldMatchWhenGlobalConstantTrueComparedToCheckedBox() {
        FlowProofFlowModel.ConditionValue globalTrue = FlowProofFlowModel.referenceValue(
            FlowProofFlowModel.ValueType.ELEMENT_REFERENCE,
            '$GlobalConstant.True'
        );
        FlowProofEvaluationResult.ConditionResult result = compareField('EqualTo', globalTrue, 'BOOLEAN', true);
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            '$GlobalConstant.True resolves to true'
        );
    }

    // ─── IsNull ──────────────────────────────────────────────────────────

    @IsTest
    static void shouldMatchWhenIsNullTrueAndFieldBlank() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'IsNull',
            FlowProofFlowModel.booleanValue(true),
            'PICKLIST',
            null
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.MATCH,
            result.outcome,
            'Blank field satisfies IsNull = true'
        );
    }

    @IsTest
    static void shouldNotMatchWhenIsNullFalseAndFieldBlank() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'IsNull',
            FlowProofFlowModel.booleanValue(false),
            'PICKLIST',
            null
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.outcome,
            'Blank field fails IsNull = false'
        );
    }

    @IsTest
    static void shouldBeUnsupportedWhenIsNullValueNotBoolean() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'IsNull',
            FlowProofFlowModel.stringValue('yes'),
            'PICKLIST',
            null
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'IsNull requires a boolean value'
        );
    }

    // ─── Unsupported constructs ──────────────────────────────────────────

    @IsTest
    static void shouldBeUnsupportedWhenOrderingOnText() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'GreaterThan',
            FlowProofFlowModel.stringValue('M'),
            'STRING',
            'Z'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Text ordering semantics are not evaluated'
        );
    }

    @IsTest
    static void shouldBeUnsupportedWhenValueIsElementReference() {
        FlowProofFlowModel.ConditionValue prior = FlowProofFlowModel.referenceValue(
            FlowProofFlowModel.ValueType.ELEMENT_REFERENCE,
            '$Record__Prior.StageName'
        );
        FlowProofEvaluationResult.ConditionResult result = compareField('EqualTo', prior, 'PICKLIST', 'Closed Won');
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Prior-value references need historical data'
        );
        Assert.areEqual('$Record__Prior.StageName', result.expectedDisplay, 'The raw reference should be shown');
    }

    @IsTest
    static void shouldBeUnsupportedWhenValueTypeMismatchesField() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue('25000'),
            'CURRENCY',
            25000
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Type conversion is not guessed'
        );
    }

    @IsTest
    static void shouldBeUnsupportedWhenFieldTypeUnsupported() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            FlowProofFlowModel.stringValue('A;B'),
            'MULTIPICKLIST',
            'A;B'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'Multi-select picklists are not evaluated yet'
        );
    }

    @IsTest
    static void shouldBeUnsupportedWhenConditionHasNoValue() {
        FlowProofEvaluationResult.ConditionResult result = compareField(
            'EqualTo',
            new FlowProofFlowModel.ConditionValue(),
            'PICKLIST',
            'Closed Won'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
            result.outcome,
            'A condition without a value cannot be compared'
        );
        Assert.areEqual('(no value)', result.expectedDisplay, 'Missing values display as (no value)');
    }

    // ─── Display ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldFormatExpectedValuesByType() {
        Test.startTest();
        String dateText = FlowProofValueComparator.displayExpected(
            FlowProofFlowModel.dateValue(Date.newInstance(2026, 1, 5))
        );
        String numberText = FlowProofValueComparator.displayExpected(FlowProofFlowModel.numberValue(10000.50));
        String emptyText = FlowProofValueComparator.displayExpected(FlowProofFlowModel.stringValue(''));
        Test.stopTest();

        Assert.areEqual('2026-01-05', dateText, 'Dates display as yyyy-MM-dd');
        Assert.areEqual('10000.5', numberText, 'Numbers display without trailing zeros');
        Assert.areEqual('(empty text)', emptyText, 'Empty text is labelled explicitly');
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static FlowProofEvaluationResult.ConditionResult compareField(
        String operator,
        FlowProofFlowModel.ConditionValue expected,
        String fieldType,
        Object actual
    ) {
        FlowProofRecordSnapshot snapshot = new FlowProofRecordSnapshot('Opportunity');
        snapshot.putValue(FIELD, fieldType, actual);
        FlowProofEvaluationResult.ConditionResult result = new FlowProofEvaluationResult.ConditionResult();
        result.index = 1;
        result.field = FIELD;
        result.operator = operator;
        result.expectedDisplay = FlowProofValueComparator.displayExpected(expected);

        Test.startTest();
        FlowProofEvaluationResult.ConditionResult compared = FlowProofValueComparator.compare(
            result,
            operator.toLowerCase(),
            expected,
            snapshot.getField(FIELD)
        );
        Test.stopTest();
        return compared;
    }
}
