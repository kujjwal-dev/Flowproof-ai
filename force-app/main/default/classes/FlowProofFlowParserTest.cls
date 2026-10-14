/**
 * Unit tests for FlowProofFlowParser. Hand-built fixtures follow the Tooling API
 * Flow.Metadata JSON shape (every FlowElementReferenceOrValue key present, all but one
 * null). The FlowProofTestOnboardingFlow static resource is the real Flow.Metadata of
 * the demo Opportunity_Onboarding Flow, captured from flowproof-dev.
 */
@IsTest
private class FlowProofFlowParserTest {
    private static final String REAL_FLOW_RESOURCE = 'FlowProofTestOnboardingFlow';

    @IsTest
    static void shouldParseRealToolingMetadataOfOnboardingFlow() {
        FlowProofFlowModel.FlowStart start = parse(realFlowJson());

        Assert.areEqual('Opportunity', start.objectApiName, 'Trigger object should be read from real metadata');
        Assert.areEqual('RecordAfterSave', start.triggerType, 'Trigger type should be read from real metadata');
        Assert.isTrue(start.requiresRecordChangedToMeetCriteria, 'Only-when-changed flag should be read');
        Assert.areEqual(3, start.filters.size(), 'All three entry conditions should be parsed');
        Assert.areEqual('Region__c', start.filters[2].field, 'Third condition is the Region condition');
        Assert.isTrue(start.filters[1].value.numberValue == 10000, 'Amount threshold should be 10000');
    }

    @IsTest
    static void shouldReproduceBriefExampleFromRealFlowMetadata() {
        FlowProofFlowModel.FlowStart start = new FlowProofFlowParser().parseStart(realFlowJson());
        FlowProofRecordSnapshot snapshot = new FlowProofRecordSnapshot('Opportunity');
        snapshot.putValue('StageName', 'PICKLIST', 'Closed Won');
        snapshot.putValue('Amount', 'CURRENCY', 25000);
        snapshot.putValue('Region__c', 'PICKLIST', null);

        Test.startTest();
        FlowProofEvaluationResult result = new FlowProofConditionEvaluator().evaluate(start, snapshot);
        Test.stopTest();

        Assert.areEqual(
            FlowProofEvaluationResult.OverallResult.NOT_SATISFIED,
            result.overall,
            'Blank Region fails the Flow'
        );
        Assert.areEqual(
            FlowProofEvaluationResult.ConditionOutcome.NO_MATCH,
            result.conditions[2].outcome,
            'Region is the failing condition'
        );
    }

    @IsTest
    static void shouldMarkUnlistedValueKindAsOther() {
        String json =
            '{"start":{"object":"Opportunity","filterLogic":"and","filters":[{"field":"Time__c","operator":"EqualTo",' +
            '"value":{"stringValue":null,"formulaDataType":null,"timeValue":"09:00:00.000Z"}}]}}';

        FlowProofFlowModel.ConditionValue value = parse(json).filters[0].value;

        Assert.areEqual(
            FlowProofFlowModel.ValueType.OTHER,
            value.valueType,
            'Value kinds not handled explicitly must not be NONE'
        );
        Assert.isTrue(value.referenceOrExpression.startsWith('timeValue'), 'The key name should be reported');
    }

    @IsTest
    static void shouldParseTriggerSettings() {
        String json = metadataJson(
            'and',
            null,
            true,
            '[' + filterJson('StageName', 'EqualTo', 'stringValue', '"Closed Won"') + ']'
        );

        FlowProofFlowModel.FlowStart start = parse(json);

        Assert.areEqual('Opportunity', start.objectApiName, 'Trigger object should be read');
        Assert.areEqual('RecordAfterSave', start.triggerType, 'Trigger type should be read');
        Assert.areEqual('CreateAndUpdate', start.recordTriggerType, 'Record trigger type should be read');
        Assert.areEqual('and', start.filterLogic, 'Filter logic should be read');
        Assert.isTrue(start.requiresRecordChangedToMeetCriteria, 'Only-when-changed flag should be read');
    }

    @IsTest
    static void shouldNumberConditionsFromOneInOrder() {
        String json = metadataJson(
            'and',
            null,
            false,
            '[' +
                filterJson('StageName', 'EqualTo', 'stringValue', '"Closed Won"') +
                ',' +
                filterJson('Amount', 'GreaterThan', 'numberValue', '10000.0') +
                ']'
        );

        FlowProofFlowModel.FlowStart start = parse(json);

        Assert.areEqual(2, start.filters.size(), 'Both conditions should be parsed');
        Assert.areEqual(1, start.filters[0].index, 'First condition is number 1');
        Assert.areEqual('Amount', start.filters[1].field, 'Second condition field should be read');
        Assert.areEqual('GreaterThan', start.filters[1].operator, 'Second condition operator should be read');
    }

    @IsTest
    static void shouldParseStringValue() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('stringValue', '"Closed Won"');
        Assert.areEqual(FlowProofFlowModel.ValueType.STRING_VALUE, value.valueType, 'Type should be STRING_VALUE');
        Assert.areEqual('Closed Won', value.stringValue, 'Text should be preserved');
    }

    @IsTest
    static void shouldParseNumberValue() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('numberValue', '10000.0');
        Assert.areEqual(FlowProofFlowModel.ValueType.NUMBER_VALUE, value.valueType, 'Type should be NUMBER_VALUE');
        Assert.isTrue(value.numberValue == 10000, 'Number should be preserved, got ' + value.numberValue);
    }

    @IsTest
    static void shouldParseBooleanValue() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('booleanValue', 'true');
        Assert.areEqual(FlowProofFlowModel.ValueType.BOOLEAN_VALUE, value.valueType, 'Type should be BOOLEAN_VALUE');
        Assert.isTrue(value.booleanValue, 'Boolean should be preserved');
    }

    @IsTest
    static void shouldParseDateValue() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('dateValue', '"2026-10-01"');
        Assert.areEqual(FlowProofFlowModel.ValueType.DATE_VALUE, value.valueType, 'Type should be DATE_VALUE');
        Assert.areEqual(Date.newInstance(2026, 10, 1), value.dateValue, 'Date should be preserved');
    }

    @IsTest
    static void shouldParseDateTimeValueWithOffset() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('dateTimeValue', '"2026-10-01T09:30:00.000+0000"');
        Assert.areEqual(FlowProofFlowModel.ValueType.DATETIME_VALUE, value.valueType, 'Type should be DATETIME_VALUE');
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 1, 9, 30, 0),
            value.dateTimeValue,
            'Datetime should be read as GMT'
        );
    }

    @IsTest
    static void shouldParseElementReference() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('elementReference', '"$Record__Prior.StageName"');
        Assert.areEqual(
            FlowProofFlowModel.ValueType.ELEMENT_REFERENCE,
            value.valueType,
            'Type should be ELEMENT_REFERENCE'
        );
        Assert.areEqual('$Record__Prior.StageName', value.referenceOrExpression, 'Reference text should be preserved');
    }

    @IsTest
    static void shouldParseFormulaExpression() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('formulaExpression', '"TODAY()"');
        Assert.areEqual(
            FlowProofFlowModel.ValueType.FORMULA_EXPRESSION,
            value.valueType,
            'Type should be FORMULA_EXPRESSION'
        );
    }

    @IsTest
    static void shouldMarkUnknownValueKindAsOther() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('apexValue', '"SomeApexType"');
        Assert.areEqual(FlowProofFlowModel.ValueType.OTHER, value.valueType, 'Unknown kinds must not be guessed');
    }

    @IsTest
    static void shouldMarkUnreadableDateAsOther() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('dateValue', '"not-a-date"');
        Assert.areEqual(FlowProofFlowModel.ValueType.OTHER, value.valueType, 'Unreadable literals become OTHER');
        Assert.isTrue(value.referenceOrExpression.contains('not-a-date'), 'Raw text should be kept for the report');
    }

    @IsTest
    static void shouldReturnNoneWhenAllValueKeysNull() {
        FlowProofFlowModel.ConditionValue value = parseSingleValue('stringValue', 'null');
        Assert.areEqual(FlowProofFlowModel.ValueType.NONE, value.valueType, 'An empty value object is NONE');
    }

    @IsTest
    static void shouldReturnEmptyFiltersWhenFlowHasNoConditions() {
        FlowProofFlowModel.FlowStart start = parse(metadataJson(null, null, false, 'null'));
        Assert.areEqual(0, start.filters.size(), 'No filters should parse to an empty list');
    }

    @IsTest
    static void shouldReadFilterFormula() {
        FlowProofFlowModel.FlowStart start = parse(
            metadataJson(null, '"ISPICKVAL({!$Record.StageName}, \\"Closed Won\\")"', false, '[]')
        );
        Assert.isTrue(start.filterFormula.startsWith('ISPICKVAL'), 'Formula text should be read');
    }

    @IsTest
    static void shouldThrowWhenJsonIsBlank() {
        assertParseFails('', 'empty');
    }

    @IsTest
    static void shouldThrowWhenJsonIsMalformed() {
        assertParseFails('{"start": ', 'not valid JSON');
    }

    @IsTest
    static void shouldThrowWhenJsonIsNotAnObject() {
        assertParseFails('[1, 2]', 'not a JSON object');
    }

    @IsTest
    static void shouldThrowWhenStartElementMissing() {
        assertParseFails('{"processType": "Flow", "start": null}', 'no start element');
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    /**
     * Loads the real Flow.Metadata fixture of the demo Opportunity_Onboarding Flow.
     * @return the metadata JSON
     */
    private static String realFlowJson() {
        StaticResource fixture = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :REAL_FLOW_RESOURCE
            WITH USER_MODE
            LIMIT 1
        ];
        return fixture.Body.toString();
    }

    private static FlowProofFlowModel.FlowStart parse(String json) {
        Test.startTest();
        FlowProofFlowModel.FlowStart start = new FlowProofFlowParser().parseStart(json);
        Test.stopTest();
        return start;
    }

    private static FlowProofFlowModel.ConditionValue parseSingleValue(String key, String rawJson) {
        String json = metadataJson('and', null, false, '[' + filterJson('Test__c', 'EqualTo', key, rawJson) + ']');
        return parse(json).filters[0].value;
    }

    private static void assertParseFails(String json, String expectedMessagePart) {
        try {
            new FlowProofFlowParser().parseStart(json);
            Assert.fail('Expected FlowProofException for input: ' + json);
        } catch (FlowProofException e) {
            Assert.isTrue(e.getMessage().contains(expectedMessagePart), 'Unexpected message: ' + e.getMessage());
        }
    }

    /**
     * Builds Flow.Metadata JSON with a record-triggered start element on Opportunity.
     * @param filterLogic filter logic, or null
     * @param filterFormulaJson JSON literal for filterFormula ("null" or a quoted string), or null
     * @param requiresChange doesRequireRecordChangedToMeetCriteria
     * @param filtersJson JSON array literal for filters, or "null"
     * @return the metadata JSON
     */
    private static String metadataJson(
        String filterLogic,
        String filterFormulaJson,
        Boolean requiresChange,
        String filtersJson
    ) {
        return '{"processType":"AutoLaunchedFlow","status":"Active","start":{' +
            '"locationX":50,"locationY":0,"connector":null,' +
            '"object":"Opportunity","triggerType":"RecordAfterSave","recordTriggerType":"CreateAndUpdate",' +
            '"filterLogic":' +
            (filterLogic == null ? 'null' : '"' + filterLogic + '"') +
            ',' +
            '"filterFormula":' +
            (filterFormulaJson ?? 'null') +
            ',' +
            '"doesRequireRecordChangedToMeetCriteria":' +
            requiresChange +
            ',' +
            '"filters":' +
            filtersJson +
            '}}';
    }

    /**
     * Builds one FlowRecordFilter whose value object has every key present and all but one null.
     * @param field field API name
     * @param operator operator name
     * @param valueKey the value key to populate
     * @param valueJson JSON literal for that key
     * @return the filter JSON
     */
    private static String filterJson(String field, String operator, String valueKey, String valueJson) {
        List<String> keys = new List<String>{
            'apexValue',
            'booleanValue',
            'dateTimeValue',
            'dateValue',
            'elementReference',
            'formulaDataType',
            'formulaExpression',
            'numberValue',
            'setupReference',
            'setupReferenceType',
            'sobjectValue',
            'stringValue',
            'transformValueReference'
        };
        List<String> pairs = new List<String>();
        for (String key : keys) {
            pairs.add('"' + key + '":' + (key == valueKey ? valueJson : 'null'));
        }
        return '{"field":"' + field + '","operator":"' + operator + '","value":{' + String.join(pairs, ',') + '}}';
    }
}
