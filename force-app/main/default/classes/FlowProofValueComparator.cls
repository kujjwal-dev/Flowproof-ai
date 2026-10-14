/**
 * Type-aware comparison of one record field value against one Flow condition value,
 * plus display formatting for both. Used by FlowProofConditionEvaluator once a
 * condition is known to be evaluable. Pure: no SOQL, DML or callouts.
 *
 * The comparison strategy comes from the field's Schema.DisplayType, never from
 * runtime instanceof checks, which are unreliable for Date vs Datetime in Apex.
 * Cases whose Flow semantics are not yet verified are reported as UNCERTAIN or
 * carry an explicit "assumption" in the reason.
 */
public with sharing class FlowProofValueComparator {
    private static final String OP_IS_NULL = 'isnull';
    private static final String OP_NOT_EQUAL = 'notequalto';
    private static final Set<String> ORDERING_OPERATORS = new Set<String>{
        'greaterthan',
        'lessthan',
        'greaterthanorequalto',
        'lessthanorequalto'
    };
    private static final String BLANK_DISPLAY = '(blank)';
    private static final String GLOBAL_TRUE = '$globalconstant.true';
    private static final String GLOBAL_FALSE = '$globalconstant.false';
    private static final String DATETIME_DISPLAY_FORMAT = 'yyyy-MM-dd\'T\'HH:mm:ss\'Z\'';

    private static final Set<String> ID_TYPES = new Set<String>{ 'ID', 'REFERENCE' };
    private static final Set<String> TEXT_TYPES = new Set<String>{
        'STRING',
        'PICKLIST',
        'TEXTAREA',
        'EMAIL',
        'PHONE',
        'URL',
        'ID',
        'REFERENCE',
        'COMBOBOX',
        'ENCRYPTEDSTRING'
    };
    private static final Set<String> NUMBER_TYPES = new Set<String>{
        'CURRENCY',
        'DOUBLE',
        'INTEGER',
        'LONG',
        'PERCENT'
    };

    private enum FieldCategory {
        TEXT_FIELD,
        NUMBER_FIELD,
        BOOLEAN_FIELD,
        DATE_FIELD,
        DATETIME_FIELD,
        UNSUPPORTED_FIELD
    }

    private static final Map<FieldCategory, FlowProofFlowModel.ValueType> VALUE_TYPE_BY_CATEGORY = new Map<FieldCategory, FlowProofFlowModel.ValueType>{
        FieldCategory.TEXT_FIELD => FlowProofFlowModel.ValueType.STRING_VALUE,
        FieldCategory.NUMBER_FIELD => FlowProofFlowModel.ValueType.NUMBER_VALUE,
        FieldCategory.BOOLEAN_FIELD => FlowProofFlowModel.ValueType.BOOLEAN_VALUE,
        FieldCategory.DATE_FIELD => FlowProofFlowModel.ValueType.DATE_VALUE,
        FieldCategory.DATETIME_FIELD => FlowProofFlowModel.ValueType.DATETIME_VALUE
    };

    /**
     * Compares a readable field with a condition value and resolves the result.
     * @param result condition result to populate (actualDisplay, outcome, reason)
     * @param operator lower-case supported operator name
     * @param expected the condition's comparison value
     * @param field the record field (exists and is accessible)
     * @return the populated result
     */
    public static FlowProofEvaluationResult.ConditionResult compare(
        FlowProofEvaluationResult.ConditionResult result,
        String operator,
        FlowProofFlowModel.ConditionValue expected,
        FlowProofRecordSnapshot.FieldValue field
    ) {
        FieldCategory category = categoryOf(field.fieldType);
        result.actualDisplay = displayActual(field.value, category);
        FlowProofFlowModel.ConditionValue resolved = resolveGlobalConstant(expected);

        if (operator == OP_IS_NULL) {
            return compareIsNull(result, resolved, field.value);
        }
        String mismatch = typeMismatch(category, resolved, field.fieldType);
        if (mismatch != null) {
            return result.resolve(FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED, mismatch);
        }
        if (ORDERING_OPERATORS.contains(operator)) {
            return compareOrdering(result, operator, category, resolved, field.value);
        }
        compareEquality(result, category, resolved, field);
        return operator == OP_NOT_EQUAL ? negate(result, field.value == null) : result;
    }

    /**
     * Formats a condition value for display.
     * @param value a condition's comparison value
     * @return the value formatted for display
     */
    public static String displayExpected(FlowProofFlowModel.ConditionValue value) {
        switch on value.valueType {
            when STRING_VALUE {
                return String.isEmpty(value.stringValue) ? '(empty text)' : value.stringValue;
            }
            when NUMBER_VALUE {
                return value.numberValue == null
                    ? BLANK_DISPLAY
                    : value.numberValue.stripTrailingZeros().toPlainString();
            }
            when BOOLEAN_VALUE {
                return String.valueOf(value.booleanValue);
            }
            when DATE_VALUE {
                return value.dateValue == null ? BLANK_DISPLAY : String.valueOf(value.dateValue);
            }
            when DATETIME_VALUE {
                return value.dateTimeValue == null
                    ? BLANK_DISPLAY
                    : value.dateTimeValue.formatGmt(DATETIME_DISPLAY_FORMAT);
            }
            when NONE {
                return '(no value)';
            }
            when else {
                return value.referenceOrExpression;
            }
        }
    }

    /**
     * Formats a record field value for display.
     * @param field a readable record field
     * @return the field's value formatted for display
     */
    public static String displayActual(FlowProofRecordSnapshot.FieldValue field) {
        return displayActual(field.value, categoryOf(field.fieldType));
    }

    // ─── Comparisons ─────────────────────────────────────────────────────

    private static FlowProofEvaluationResult.ConditionResult compareIsNull(
        FlowProofEvaluationResult.ConditionResult result,
        FlowProofFlowModel.ConditionValue expected,
        Object actual
    ) {
        if (expected.valueType != FlowProofFlowModel.ValueType.BOOLEAN_VALUE || expected.booleanValue == null) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'IsNull needs a true/false comparison value.'
            );
        }
        Boolean isBlank = actual == null;
        return result.resolve(
            isBlank == expected.booleanValue
                ? FlowProofEvaluationResult.ConditionOutcome.MATCH
                : FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            'The field is ' +
                (isBlank ? 'blank' : 'not blank') +
                '; the condition requires it to be ' +
                (expected.booleanValue ? 'blank.' : 'not blank.')
        );
    }

    private static FlowProofEvaluationResult.ConditionResult compareEquality(
        FlowProofEvaluationResult.ConditionResult result,
        FieldCategory category,
        FlowProofFlowModel.ConditionValue expected,
        FlowProofRecordSnapshot.FieldValue field
    ) {
        if (field.value == null) {
            if (category == FieldCategory.TEXT_FIELD && String.isEmpty(expected.stringValue)) {
                return result.resolve(
                    FlowProofEvaluationResult.ConditionOutcome.UNCERTAIN,
                    'The field is blank and the condition compares to empty text; whether Flow treats these as equal is not yet verified.'
                );
            }
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
                'The field is blank, so it does not equal ' + result.expectedDisplay + '.'
            );
        }
        if (category == FieldCategory.TEXT_FIELD) {
            return compareText(result, expected.stringValue, String.valueOf(field.value), field.fieldType);
        }
        Integer comparison = compareValues(category, expected, field.value);
        if (comparison == null) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'The field value could not be compared.'
            );
        }
        return result.resolve(
            comparison == 0
                ? FlowProofEvaluationResult.ConditionOutcome.MATCH
                : FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            comparison == 0
                ? 'The field equals ' + result.expectedDisplay + '.'
                : 'The field is ' + result.actualDisplay + ', not ' + result.expectedDisplay + '.'
        );
    }

    private static FlowProofEvaluationResult.ConditionResult compareText(
        FlowProofEvaluationResult.ConditionResult result,
        String expected,
        String actual,
        String fieldType
    ) {
        if (actual.equals(expected) || sameRecordId(actual, expected, fieldType)) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.MATCH,
                'The field equals ' + result.expectedDisplay + '.'
            );
        }
        if (actual.equalsIgnoreCase(expected)) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNCERTAIN,
                'The values differ only in letter case; whether Flow entry conditions are case-sensitive is not yet verified.'
            );
        }
        return result.resolve(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            'The field is ' + result.actualDisplay + ', not ' + result.expectedDisplay + '.'
        );
    }

    /**

     * Treats 15- and 18-character forms of the same record Id as equal.

     * @param actual record value as text

     * @param expected condition value as text

     * @param fieldType Schema.DisplayType name

     * @return true when both are valid Ids of the same record

     */
    private static Boolean sameRecordId(String actual, String expected, String fieldType) {
        if (!ID_TYPES.contains(fieldType?.toUpperCase()) || String.isBlank(expected)) {
            return false;
        }
        try {
            return Id.valueOf(actual) == Id.valueOf(expected);
        } catch (StringException e) {
            return false;
        }
    }

    private static FlowProofEvaluationResult.ConditionResult compareOrdering(
        FlowProofEvaluationResult.ConditionResult result,
        String operator,
        FieldCategory category,
        FlowProofFlowModel.ConditionValue expected,
        Object actual
    ) {
        if (category == FieldCategory.TEXT_FIELD || category == FieldCategory.BOOLEAN_FIELD) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'Greater/less-than comparisons are only evaluated for number, date and datetime fields.'
            );
        }
        if (actual == null) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
                'The field is blank; a blank value is treated as not satisfying a comparison (assumption, not yet verified).'
            );
        }
        Integer comparison = compareValues(category, expected, actual);
        if (comparison == null) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'The field value could not be compared.'
            );
        }
        return result.resolve(
            orderingHolds(operator, comparison)
                ? FlowProofEvaluationResult.ConditionOutcome.MATCH
                : FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            'The field is ' +
                result.actualDisplay +
                '; the condition requires ' +
                operatorPhrase(operator) +
                ' ' +
                result.expectedDisplay +
                '.'
        );
    }

    private static Boolean orderingHolds(String operator, Integer comparison) {
        switch on operator {
            when 'greaterthan' {
                return comparison > 0;
            }
            when 'lessthan' {
                return comparison < 0;
            }
            when 'greaterthanorequalto' {
                return comparison >= 0;
            }
            when else {
                return comparison <= 0;
            }
        }
    }

    private static String operatorPhrase(String operator) {
        switch on operator {
            when 'greaterthan' {
                return 'greater than';
            }
            when 'lessthan' {
                return 'less than';
            }
            when 'greaterthanorequalto' {
                return 'at least';
            }
            when else {
                return 'at most';
            }
        }
    }

    private static FlowProofEvaluationResult.ConditionResult negate(
        FlowProofEvaluationResult.ConditionResult equality,
        Boolean actualIsBlank
    ) {
        if (equality.outcome == FlowProofEvaluationResult.ConditionOutcome.MATCH) {
            return equality.resolve(
                FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
                'The field equals ' + equality.expectedDisplay + ', but the condition requires a different value.'
            );
        }
        if (equality.outcome == FlowProofEvaluationResult.ConditionOutcome.NO_MATCH) {
            return equality.resolve(
                FlowProofEvaluationResult.ConditionOutcome.MATCH,
                actualIsBlank
                    ? 'The field is blank, which counts as different from ' +
                      equality.expectedDisplay +
                      ' (assumption, not yet verified).'
                    : 'The field is ' +
                      equality.actualDisplay +
                      ', which differs from ' +
                      equality.expectedDisplay +
                      '.'
            );
        }
        return equality;
    }

    /**
     * Compares a non-null record value with the expected value.
     * @param category comparison strategy for the field
     * @param expected the condition value
     * @param actual the record value
     * @return negative, zero or positive like compareTo; null when the value cannot be read
     */
    private static Integer compareValues(
        FieldCategory category,
        FlowProofFlowModel.ConditionValue expected,
        Object actual
    ) {
        try {
            switch on category {
                when NUMBER_FIELD {
                    return signum(Decimal.valueOf(String.valueOf(actual)) - expected.numberValue);
                }
                when BOOLEAN_FIELD {
                    return ((Boolean) actual) == expected.booleanValue ? 0 : 1;
                }
                when DATE_FIELD {
                    return signum(Decimal.valueOf(expected.dateValue.daysBetween((Date) actual)));
                }
                when DATETIME_FIELD {
                    return signum(Decimal.valueOf(((Datetime) actual).getTime() - expected.dateTimeValue.getTime()));
                }
                when else {
                    return null;
                }
            }
        } catch (TypeException e) {
            return null;
        } catch (NullPointerException e) {
            return null;
        }
    }

    private static Integer signum(Decimal value) {
        return value == 0 ? 0 : (value > 0 ? 1 : -1);
    }

    // ─── Types and values ────────────────────────────────────────────────

    private static FieldCategory categoryOf(String fieldType) {
        String normalized = String.isBlank(fieldType) ? '' : fieldType.toUpperCase();
        if (TEXT_TYPES.contains(normalized)) {
            return FieldCategory.TEXT_FIELD;
        }
        if (NUMBER_TYPES.contains(normalized)) {
            return FieldCategory.NUMBER_FIELD;
        }
        switch on normalized {
            when 'BOOLEAN' {
                return FieldCategory.BOOLEAN_FIELD;
            }
            when 'DATE' {
                return FieldCategory.DATE_FIELD;
            }
            when 'DATETIME' {
                return FieldCategory.DATETIME_FIELD;
            }
            when else {
                return FieldCategory.UNSUPPORTED_FIELD;
            }
        }
    }

    /**
     * Checks that the condition value can be compared with this field.
     * @param category comparison strategy for the field
     * @param expected the condition value
     * @param fieldType Schema.DisplayType name, used in the message
     * @return a reason when the comparison value cannot be compared with this field; null when compatible
     */
    private static String typeMismatch(
        FieldCategory category,
        FlowProofFlowModel.ConditionValue expected,
        String fieldType
    ) {
        FlowProofFlowModel.ValueType valueType = expected.valueType;
        if (category == FieldCategory.UNSUPPORTED_FIELD) {
            return 'Fields of type ' + (String.isBlank(fieldType) ? 'unknown' : fieldType) + ' are not evaluated yet.';
        }
        if (
            valueType == FlowProofFlowModel.ValueType.ELEMENT_REFERENCE ||
            valueType == FlowProofFlowModel.ValueType.FORMULA_EXPRESSION ||
            valueType == FlowProofFlowModel.ValueType.OTHER
        ) {
            return 'The condition compares to a resource or formula (' +
                expected.referenceOrExpression +
                '), which is not evaluated yet.';
        }
        if (valueType == FlowProofFlowModel.ValueType.NONE) {
            return 'The condition has no comparison value.';
        }
        if (VALUE_TYPE_BY_CATEGORY.get(category) != valueType) {
            return 'The comparison value type does not match the ' +
                fieldType +
                ' field; type conversion is not evaluated yet.';
        }
        return null;
    }

    private static FlowProofFlowModel.ConditionValue resolveGlobalConstant(FlowProofFlowModel.ConditionValue value) {
        if (value.valueType != FlowProofFlowModel.ValueType.ELEMENT_REFERENCE || value.referenceOrExpression == null) {
            return value;
        }
        String reference = value.referenceOrExpression.toLowerCase();
        if (reference == GLOBAL_TRUE) {
            return FlowProofFlowModel.booleanValue(true);
        }
        if (reference == GLOBAL_FALSE) {
            return FlowProofFlowModel.booleanValue(false);
        }
        return value;
    }

    private static String displayActual(Object value, FieldCategory category) {
        if (value == null) {
            return BLANK_DISPLAY;
        }
        try {
            switch on category {
                when DATETIME_FIELD {
                    return ((Datetime) value).formatGmt(DATETIME_DISPLAY_FORMAT);
                }
                when NUMBER_FIELD {
                    return Decimal.valueOf(String.valueOf(value)).stripTrailingZeros().toPlainString();
                }
                when else {
                    return String.valueOf(value);
                }
            }
        } catch (TypeException e) {
            return String.valueOf(value);
        }
    }
}
