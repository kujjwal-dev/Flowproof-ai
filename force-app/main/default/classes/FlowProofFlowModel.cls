/**
 * In-memory model of a record-triggered Flow's start element: trigger settings
 * and entry conditions. Built by the Flow parser from Tooling API or snapshot
 * metadata and consumed by the condition evaluator. Contains no org access.
 *
 * Field names mirror the Metadata API FlowStart / FlowRecordFilter types.
 *
 * @example
 * FlowProofFlowModel.FlowStart start = new FlowProofFlowModel.FlowStart();
 * start.filterLogic = 'and';
 * start.filters.add(new FlowProofFlowModel.Condition(1, 'StageName', 'EqualTo',
 *     FlowProofFlowModel.stringValue('Closed Won')));
 */
public with sharing class FlowProofFlowModel {
    /** Kinds of comparison value a FlowRecordFilter can carry. */
    public enum ValueType {
        STRING_VALUE,
        NUMBER_VALUE,
        BOOLEAN_VALUE,
        DATE_VALUE,
        DATETIME_VALUE,
        ELEMENT_REFERENCE,
        FORMULA_EXPRESSION,
        OTHER,
        NONE
    }

    /**
     * The start element of a record-triggered Flow.
     */
    public with sharing class FlowStart {
        /** API name of the triggering object, e.g. Opportunity. */
        public String objectApiName { get; set; }
        /** RecordBeforeSave, RecordAfterSave, RecordBeforeDelete, ... */
        public String triggerType { get; set; }
        /** Create, Update, CreateAndUpdate, Delete. */
        public String recordTriggerType { get; set; }
        /** 'and', 'or', custom logic such as '1 AND (2 OR 3)', or blank. */
        public String filterLogic { get; set; }
        /** Formula entry condition; when set, filters are not used. */
        public String filterFormula { get; set; }
        /** True when the Flow runs only if the record is updated to meet the conditions. */
        public Boolean requiresRecordChangedToMeetCriteria { get; set; }
        /** Entry conditions in metadata order. */
        public List<Condition> filters { get; set; }

        /**
         * Creates an empty start element with no conditions.
         */
        public FlowStart() {
            this.filters = new List<Condition>();
            this.requiresRecordChangedToMeetCriteria = false;
        }
    }

    /**
     * One entry condition (FlowRecordFilter).
     */
    public with sharing class Condition {
        /** 1-based position, as referenced by custom filter logic. */
        public Integer index { get; set; }
        /** Field API name on the triggering object; may contain '.' for relationships. */
        public String field { get; set; }
        /** FlowRecordFilterOperator name, e.g. EqualTo. */
        public String operator { get; set; }
        /** Comparison value; never null (NONE when absent). */
        public ConditionValue value { get; set; }

        /**
         * No-arg constructor for deserialization.
         */
        public Condition() {
            this.value = new ConditionValue();
        }

        /**
         * Creates a condition from its parts.
         * @param index 1-based condition number
         * @param field field API name
         * @param operator FlowRecordFilterOperator name
         * @param value comparison value (null is stored as NONE)
         */
        public Condition(Integer index, String field, String operator, ConditionValue value) {
            this.index = index;
            this.field = field;
            this.operator = operator;
            this.value = value ?? new ConditionValue();
        }
    }

    /**
     * Typed comparison value (FlowElementReferenceOrValue). Exactly one typed slot is set.
     */
    public with sharing class ConditionValue {
        /** Which slot holds the value. */
        public ValueType valueType { get; set; }
        /** Set when valueType is STRING_VALUE. */
        public String stringValue { get; set; }
        /** Set when valueType is NUMBER_VALUE. */
        public Decimal numberValue { get; set; }
        /** Set when valueType is BOOLEAN_VALUE. */
        public Boolean booleanValue { get; set; }
        /** Set when valueType is DATE_VALUE. */
        public Date dateValue { get; set; }
        /** Set when valueType is DATETIME_VALUE. */
        public Datetime dateTimeValue { get; set; }
        /** Set when valueType is ELEMENT_REFERENCE, FORMULA_EXPRESSION or OTHER (raw text). */
        public String referenceOrExpression { get; set; }

        /**
         * Creates a value of type NONE.
         */
        public ConditionValue() {
            this.valueType = FlowProofFlowModel.ValueType.NONE;
        }
    }

    // Apex inner classes cannot declare static methods, so value factories live here.

    /**
     * Builds a typed comparison value.
     * @param value text comparison value
     * @return a STRING_VALUE condition value
     */
    public static ConditionValue stringValue(String value) {
        ConditionValue result = new ConditionValue();
        result.valueType = ValueType.STRING_VALUE;
        result.stringValue = value;
        return result;
    }

    /**
     * Builds a typed comparison value.
     * @param value numeric comparison value
     * @return a NUMBER_VALUE condition value
     */
    public static ConditionValue numberValue(Decimal value) {
        ConditionValue result = new ConditionValue();
        result.valueType = ValueType.NUMBER_VALUE;
        result.numberValue = value;
        return result;
    }

    /**
     * Builds a typed comparison value.
     * @param value boolean comparison value
     * @return a BOOLEAN_VALUE condition value
     */
    public static ConditionValue booleanValue(Boolean value) {
        ConditionValue result = new ConditionValue();
        result.valueType = ValueType.BOOLEAN_VALUE;
        result.booleanValue = value;
        return result;
    }

    /**
     * Builds a typed comparison value.
     * @param value date comparison value
     * @return a DATE_VALUE condition value
     */
    public static ConditionValue dateValue(Date value) {
        ConditionValue result = new ConditionValue();
        result.valueType = ValueType.DATE_VALUE;
        result.dateValue = value;
        return result;
    }

    /**
     * Builds a typed comparison value.
     * @param value datetime comparison value
     * @return a DATETIME_VALUE condition value
     */
    public static ConditionValue dateTimeValue(Datetime value) {
        ConditionValue result = new ConditionValue();
        result.valueType = ValueType.DATETIME_VALUE;
        result.dateTimeValue = value;
        return result;
    }

    /**
     * Builds a non-literal comparison value (resource reference or formula).
     * @param valueType ELEMENT_REFERENCE, FORMULA_EXPRESSION or OTHER
     * @param rawText the reference or expression text as stored in metadata
     * @return a non-literal condition value
     */
    public static ConditionValue referenceValue(ValueType valueType, String rawText) {
        ConditionValue result = new ConditionValue();
        result.valueType = valueType;
        result.referenceOrExpression = rawText;
        return result;
    }
}
