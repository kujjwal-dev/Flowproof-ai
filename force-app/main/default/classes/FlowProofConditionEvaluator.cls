/**
 * Evaluates a record-triggered Flow's entry conditions against a record's
 * CURRENT field values. Deterministic and side-effect free: no SOQL, DML or callouts.
 *
 * This class decides whether each condition can be evaluated (field exists, is
 * readable, operator supported, not a relationship path) and combines the
 * per-condition results with the Flow's filter logic. Typed value comparison is
 * delegated to FlowProofValueComparator.
 *
 * Supported (MVP): EqualTo, NotEqualTo, GreaterThan, LessThan, GreaterThanOrEqualTo,
 * LessThanOrEqualTo, IsNull; 'and' / 'or' logic. Everything else is reported as
 * UNSUPPORTED rather than guessed.
 *
 * @example
 * FlowProofEvaluationResult result = new FlowProofConditionEvaluator().evaluate(start, snapshot);
 */
public with sharing class FlowProofConditionEvaluator {
    private static final String LOGIC_AND = 'and';
    private static final String LOGIC_OR = 'or';
    private static final Set<String> SUPPORTED_OPERATORS = new Set<String>{
        'equalto',
        'notequalto',
        'greaterthan',
        'lessthan',
        'greaterthanorequalto',
        'lessthanorequalto',
        'isnull'
    };

    /**
     * Evaluates every condition and combines them according to the filter logic.
     * @param start the Flow's start element
     * @param snapshot the record's field values and access flags
     * @return per-condition results and the overall result
     * @throws IllegalArgumentException when start or snapshot is null
     */
    public FlowProofEvaluationResult evaluate(FlowProofFlowModel.FlowStart start, FlowProofRecordSnapshot snapshot) {
        if (start == null || snapshot == null) {
            throw new IllegalArgumentException('Flow start and record snapshot are required.');
        }
        List<FlowProofFlowModel.Condition> filters = start.filters ?? new List<FlowProofFlowModel.Condition>();
        FlowProofEvaluationResult result = new FlowProofEvaluationResult();
        for (FlowProofFlowModel.Condition condition : filters) {
            result.conditions.add(evaluateCondition(condition, snapshot));
        }

        if (String.isNotBlank(start.filterFormula)) {
            return withOverall(
                result,
                'FORMULA',
                FlowProofEvaluationResult.OverallResult.INDETERMINATE,
                'The Flow uses a formula entry condition, which FlowProof does not evaluate.'
            );
        }
        if (filters.isEmpty()) {
            return withOverall(
                result,
                'NONE',
                FlowProofEvaluationResult.OverallResult.SATISFIED,
                'The Flow has no entry conditions, so every qualifying save meets them.'
            );
        }

        String logic = String.isBlank(start.filterLogic) ? LOGIC_AND : start.filterLogic.trim().toLowerCase();
        if (logic == LOGIC_AND) {
            return combineAll(result);
        }
        if (logic == LOGIC_OR) {
            return combineAny(result);
        }
        return withOverall(
            result,
            'CUSTOM',
            FlowProofEvaluationResult.OverallResult.INDETERMINATE,
            'Custom condition logic "' +
                start.filterLogic +
                '" is not evaluated yet; see the individual condition results.'
        );
    }

    // ─── Single condition ────────────────────────────────────────────────

    private static FlowProofEvaluationResult.ConditionResult evaluateCondition(
        FlowProofFlowModel.Condition condition,
        FlowProofRecordSnapshot snapshot
    ) {
        FlowProofFlowModel.ConditionValue expected = condition.value ?? new FlowProofFlowModel.ConditionValue();
        FlowProofEvaluationResult.ConditionResult result = new FlowProofEvaluationResult.ConditionResult();
        result.index = condition.index;
        result.field = condition.field;
        result.operator = condition.operator;
        result.expectedDisplay = FlowProofValueComparator.displayExpected(expected);

        if (String.isBlank(condition.field)) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'The condition has no field.'
            );
        }
        if (condition.field.contains('.')) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'Conditions on related-record fields are not evaluated yet.'
            );
        }
        FlowProofRecordSnapshot.FieldValue field = snapshot.getField(condition.field);
        if (field == null) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'No value was collected for this field.'
            );
        }
        if (!field.exists) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.MISSING,
                'The object has no field named ' + condition.field + '.'
            );
        }
        if (!field.isAccessible) {
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.INACCESSIBLE,
                'You do not have read access to this field, so it was not evaluated.'
            );
        }
        String operator = String.isBlank(condition.operator) ? '' : condition.operator.toLowerCase();
        if (!SUPPORTED_OPERATORS.contains(operator)) {
            result.actualDisplay = FlowProofValueComparator.displayActual(field);
            return result.resolve(
                FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED,
                'The ' +
                    (String.isBlank(condition.operator) ? '(missing)' : condition.operator) +
                    ' operator is not supported yet.'
            );
        }
        return FlowProofValueComparator.compare(result, operator, expected, field);
    }

    // ─── Combining ───────────────────────────────────────────────────────

    private static FlowProofEvaluationResult combineAll(FlowProofEvaluationResult result) {
        List<Integer> failed = indexesWithOutcome(result, FlowProofEvaluationResult.ConditionOutcome.NO_MATCH, true);
        if (!failed.isEmpty()) {
            return withOverall(
                result,
                'AND',
                FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
                'All conditions must match, and condition(s) ' +
                    String.join(failed, ', ') +
                    ' do not match the current values.'
            );
        }
        List<Integer> unresolved = indexesWithOutcome(result, FlowProofEvaluationResult.ConditionOutcome.MATCH, false);
        if (unresolved.isEmpty()) {
            return withOverall(
                result,
                'AND',
                FlowProofEvaluationResult.OverallResult.SATISFIED,
                'All conditions match the current values.'
            );
        }
        return withOverall(
            result,
            'AND',
            FlowProofEvaluationResult.OverallResult.INDETERMINATE,
            'No condition fails, but condition(s) ' + String.join(unresolved, ', ') + ' could not be evaluated.'
        );
    }

    private static FlowProofEvaluationResult combineAny(FlowProofEvaluationResult result) {
        List<Integer> matched = indexesWithOutcome(result, FlowProofEvaluationResult.ConditionOutcome.MATCH, true);
        if (!matched.isEmpty()) {
            return withOverall(
                result,
                'OR',
                FlowProofEvaluationResult.OverallResult.SATISFIED,
                'Any one condition is enough, and condition(s) ' +
                    String.join(matched, ', ') +
                    ' match the current values.'
            );
        }
        List<Integer> unresolved = indexesWithOutcome(
            result,
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            false
        );
        if (unresolved.isEmpty()) {
            return withOverall(
                result,
                'OR',
                FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
                'Any one condition is enough, but none match the current values.'
            );
        }
        return withOverall(
            result,
            'OR',
            FlowProofEvaluationResult.OverallResult.INDETERMINATE,
            'No condition matches, but condition(s) ' + String.join(unresolved, ', ') + ' could not be evaluated.'
        );
    }

    /**
     * Lists the condition numbers that do (or do not) have an outcome.
     * @param result evaluation result to scan
     * @param outcome outcome to test for
     * @param equal true to collect conditions WITH the outcome, false to collect those WITHOUT it
     * @return 1-based condition numbers
     */
    private static List<Integer> indexesWithOutcome(
        FlowProofEvaluationResult result,
        FlowProofEvaluationResult.ConditionOutcome outcome,
        Boolean equal
    ) {
        List<Integer> indexes = new List<Integer>();
        for (FlowProofEvaluationResult.ConditionResult conditionResult : result.conditions) {
            if ((conditionResult.outcome == outcome) == equal) {
                indexes.add(conditionResult.index);
            }
        }
        return indexes;
    }

    private static FlowProofEvaluationResult withOverall(
        FlowProofEvaluationResult result,
        String logicType,
        FlowProofEvaluationResult.OverallResult overall,
        String reason
    ) {
        result.logicType = logicType;
        result.overall = overall;
        result.overallReason = reason;
        return result;
    }
}
