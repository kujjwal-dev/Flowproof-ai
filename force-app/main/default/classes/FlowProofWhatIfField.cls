/**
 * One field in the "what if" form: a field that the checked Flows' conditions reference, its
 * current value, and how to edit it. Also converts a typed-in value to the field's type, so a
 * simulated value is compared exactly like a real one. Simulation only: nothing is saved.
 */
public with sharing class FlowProofWhatIfField implements Comparable {
    /** Field API name. */
    @AuraEnabled
    public String apiName { get; set; }
    /** Field label. */
    @AuraEnabled
    public String label { get; set; }
    /** How to edit it: text, number, checkbox, date, datetime or picklist. */
    @AuraEnabled
    public String inputType { get; set; }
    /** Current value in input form (ISO dates, plain numbers, true/false); null when blank. */
    @AuraEnabled
    public String value { get; set; }
    /** Current value as shown elsewhere in FlowProof, e.g. (blank). */
    @AuraEnabled
    public String currentDisplay { get; set; }
    /** Active picklist values, for picklist fields. */
    @AuraEnabled
    public List<Option> options { get; set; }

    /**
     * @param describe the field's describe result
     * @param field the field's current state in the snapshot
     */
    public FlowProofWhatIfField(Schema.DescribeFieldResult describe, FlowProofRecordSnapshot.FieldValue field) {
        this.apiName = describe.getName();
        this.label = describe.getLabel();
        this.inputType = inputTypeOf(field.fieldType);
        this.value = toInput(field.value);
        this.currentDisplay = FlowProofValueComparator.displayActual(field);
        this.options = new List<Option>();
        if (this.inputType == 'picklist') {
            for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                if (entry.isActive()) {
                    this.options.add(new Option(entry.getLabel(), entry.getValue()));
                }
            }
        }
    }

    /**
     * Converts a typed-in value to the field's type.
     * @param field the field's state in the snapshot (gives its type)
     * @param input the typed-in value; blank means a blank field
     * @return the value as SOQL would return it; null for blank
     * @throws IllegalArgumentException when the value does not fit the field's type
     */
    public static Object parse(FlowProofRecordSnapshot.FieldValue field, String input) {
        String type = (field.fieldType ?? '').toUpperCase();
        if (type == 'BOOLEAN') {
            return input == 'true';
        }
        if (String.isBlank(input)) {
            return null;
        }
        String text = input.trim();
        try {
            switch on type {
                when 'CURRENCY', 'DOUBLE', 'PERCENT' {
                    return Decimal.valueOf(text);
                }
                when 'INTEGER' {
                    return Integer.valueOf(text);
                }
                when 'LONG' {
                    return Long.valueOf(text);
                }
                when 'DATE' {
                    return Date.valueOf(text);
                }
                when 'DATETIME' {
                    return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
                }
                when else {
                    return text;
                }
            }
        } catch (TypeException e) {
            throw invalid(field, input, e);
        } catch (JSONException e) {
            throw invalid(field, input, e);
        }
    }

    /**
     * Orders fields by label.
     * @param other another FlowProofWhatIfField
     * @return negative, zero or positive
     */
    public Integer compareTo(Object other) {
        return (this.label ?? '').compareTo(((FlowProofWhatIfField) other).label ?? '');
    }

    private static String inputTypeOf(String fieldType) {
        switch on (fieldType ?? '').toUpperCase() {
            when 'BOOLEAN' {
                return 'checkbox';
            }
            when 'CURRENCY', 'DOUBLE', 'PERCENT', 'INTEGER', 'LONG' {
                return 'number';
            }
            when 'DATE' {
                return 'date';
            }
            when 'DATETIME' {
                return 'datetime';
            }
            when 'PICKLIST' {
                return 'picklist';
            }
            when else {
                return 'text';
            }
        }
    }

    private static String toInput(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Datetime) {
            return JSON.serialize(value).remove('"');
        }
        if (value instanceof Date) {
            return String.valueOf(value);
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).stripTrailingZeros().toPlainString();
        }
        return String.valueOf(value);
    }

    private static IllegalArgumentException invalid(
        FlowProofRecordSnapshot.FieldValue field,
        String input,
        Exception cause
    ) {
        IllegalArgumentException error = new IllegalArgumentException(
            '"' + input + '" is not a valid value for ' + field.fieldApiName + '.'
        );
        error.initCause(cause);
        return error;
    }

    /** One picklist choice. */
    public with sharing class Option {
        /** Shown to the user. */
        @AuraEnabled
        public String label { get; set; }
        /** Stored value. */
        @AuraEnabled
        public String value { get; set; }

        /**
         * @param label shown to the user
         * @param value stored value
         */
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}
