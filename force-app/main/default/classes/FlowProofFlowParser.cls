/**
 * Converts the JSON of a Tooling API Flow record's Metadata field into a
 * FlowProofFlowModel.FlowStart. Pure: no SOQL, DML or callouts.
 *
 * Parsing is untyped and tolerant: unknown keys are ignored, and value kinds the
 * evaluator does not understand become OTHER (with their raw text) instead of being
 * guessed, so a newer Flow metadata shape degrades to UNSUPPORTED, never to a wrong match.
 *
 * @example
 * FlowProofFlowModel.FlowStart start = new FlowProofFlowParser().parseStart(metadataJson);
 */
public with sharing class FlowProofFlowParser {
    // FlowElementReferenceOrValue keys in the order they are checked; exactly one is set.
    private static final List<String> LITERAL_KEYS = new List<String>{
        'stringValue',
        'numberValue',
        'booleanValue',
        'dateValue',
        'dateTimeValue'
    };
    private static final List<String> NON_LITERAL_KEYS = new List<String>{
        'apexValue',
        'sobjectValue',
        'setupReference',
        'transformValueReference'
    };

    /**
     * Parses the start element of a Flow's metadata.
     * @param metadataJson JSON of the Tooling API Flow.Metadata field
     * @return the start element; filters is empty when the Flow has no entry conditions
     * @throws FlowProofException when the JSON is blank, malformed or has no start element
     */
    public FlowProofFlowModel.FlowStart parseStart(String metadataJson) {
        if (String.isBlank(metadataJson)) {
            throw new FlowProofException('Flow metadata is empty.');
        }
        Map<String, Object> metadata;
        try {
            metadata = (Map<String, Object>) JSON.deserializeUntyped(metadataJson);
        } catch (JSONException e) {
            throw new FlowProofException('Flow metadata is not valid JSON.', e);
        } catch (TypeException e) {
            throw new FlowProofException('Flow metadata is not a JSON object.', e);
        }
        Map<String, Object> startElement = asMap(metadata.get('start'));
        if (startElement == null) {
            throw new FlowProofException('Flow metadata has no start element, so it is not a triggered Flow.');
        }
        return toFlowStart(startElement);
    }

    private static FlowProofFlowModel.FlowStart toFlowStart(Map<String, Object> startElement) {
        FlowProofFlowModel.FlowStart start = new FlowProofFlowModel.FlowStart();
        start.objectApiName = asString(startElement.get('object'));
        start.triggerType = asString(startElement.get('triggerType'));
        start.recordTriggerType = asString(startElement.get('recordTriggerType'));
        start.filterLogic = asString(startElement.get('filterLogic'));
        start.filterFormula = asString(startElement.get('filterFormula'));
        start.requiresRecordChangedToMeetCriteria = startElement.get('doesRequireRecordChangedToMeetCriteria') == true;

        List<Object> filters = startElement.get('filters') instanceof List<Object>
            ? (List<Object>) startElement.get('filters')
            : new List<Object>();
        for (Integer i = 0; i < filters.size(); i++) {
            Map<String, Object> filter = asMap(filters[i]) ?? new Map<String, Object>();
            start.filters.add(
                new FlowProofFlowModel.Condition(
                    i + 1,
                    asString(filter.get('field')),
                    asString(filter.get('operator')),
                    toConditionValue(asMap(filter.get('value')))
                )
            );
        }
        return start;
    }

    private static FlowProofFlowModel.ConditionValue toConditionValue(Map<String, Object> value) {
        if (value == null) {
            return new FlowProofFlowModel.ConditionValue();
        }
        for (String key : LITERAL_KEYS) {
            if (value.get(key) != null) {
                return toLiteral(key, value.get(key));
            }
        }
        if (value.get('elementReference') != null) {
            return FlowProofFlowModel.referenceValue(
                FlowProofFlowModel.ValueType.ELEMENT_REFERENCE,
                asString(value.get('elementReference'))
            );
        }
        if (value.get('formulaExpression') != null) {
            return FlowProofFlowModel.referenceValue(
                FlowProofFlowModel.ValueType.FORMULA_EXPRESSION,
                asString(value.get('formulaExpression'))
            );
        }
        for (String key : NON_LITERAL_KEYS) {
            if (value.get(key) != null) {
                return FlowProofFlowModel.referenceValue(
                    FlowProofFlowModel.ValueType.OTHER,
                    key + ': ' + String.valueOf(value.get(key))
                );
            }
        }
        return new FlowProofFlowModel.ConditionValue();
    }

    private static FlowProofFlowModel.ConditionValue toLiteral(String key, Object raw) {
        try {
            switch on key {
                when 'stringValue' {
                    return FlowProofFlowModel.stringValue(String.valueOf(raw));
                }
                when 'numberValue' {
                    return FlowProofFlowModel.numberValue(Decimal.valueOf(String.valueOf(raw)));
                }
                when 'booleanValue' {
                    return FlowProofFlowModel.booleanValue(raw == true);
                }
                when 'dateValue' {
                    return FlowProofFlowModel.dateValue(Date.valueOf(String.valueOf(raw)));
                }
                when else {
                    // JSON.deserialize understands every ISO-8601 form the API returns.
                    Datetime parsed = (Datetime) JSON.deserialize('"' + String.valueOf(raw) + '"', Datetime.class);
                    return FlowProofFlowModel.dateTimeValue(parsed);
                }
            }
        } catch (TypeException e) {
            return unreadable(key, raw);
        } catch (JSONException e) {
            return unreadable(key, raw);
        }
    }

    private static FlowProofFlowModel.ConditionValue unreadable(String key, Object raw) {
        return FlowProofFlowModel.referenceValue(
            FlowProofFlowModel.ValueType.OTHER,
            'unreadable ' + key + ': ' + String.valueOf(raw)
        );
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
