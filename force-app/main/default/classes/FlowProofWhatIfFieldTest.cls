/**
 * Unit tests for FlowProofWhatIfField: form metadata from real Opportunity field describes, and
 * converting typed-in values to each field type.
 */
@IsTest
private class FlowProofWhatIfFieldTest {
    @IsTest
    static void shouldDescribePicklistWithActiveValues() {
        FlowProofWhatIfField field = new FlowProofWhatIfField(
            Opportunity.StageName.getDescribe(),
            fieldValue('StageName', 'PICKLIST', 'Closed Won')
        );

        Assert.areEqual('picklist', field.inputType, 'Picklists get a picklist input');
        Assert.areEqual('Closed Won', field.value, 'The current value is the input value');
        Assert.isFalse(field.options.isEmpty(), 'Active picklist values are offered');
    }

    @IsTest
    static void shouldDescribeOtherInputTypes() {
        FlowProofWhatIfField amount = new FlowProofWhatIfField(
            Opportunity.Amount.getDescribe(),
            fieldValue('Amount', 'CURRENCY', 25000.50)
        );
        FlowProofWhatIfField closeDate = new FlowProofWhatIfField(
            Opportunity.CloseDate.getDescribe(),
            fieldValue('CloseDate', 'DATE', Date.newInstance(2026, 10, 17))
        );
        FlowProofWhatIfField isPrivate = new FlowProofWhatIfField(
            Opportunity.IsPrivate.getDescribe(),
            fieldValue('IsPrivate', 'BOOLEAN', true)
        );
        FlowProofWhatIfField created = new FlowProofWhatIfField(
            Opportunity.CreatedDate.getDescribe(),
            fieldValue('CreatedDate', 'DATETIME', Datetime.newInstanceGmt(2026, 10, 17, 9, 30, 0))
        );
        FlowProofWhatIfField name = new FlowProofWhatIfField(
            Opportunity.Name.getDescribe(),
            fieldValue('Name', 'STRING', null)
        );

        Assert.areEqual('number', amount.inputType, 'Currency is a number');
        Assert.areEqual('25000.5', amount.value, 'Numbers are plain');
        Assert.areEqual('2026-10-17', closeDate.value, 'Dates are ISO');
        Assert.areEqual('checkbox', isPrivate.inputType, 'Booleans are checkboxes');
        Assert.areEqual('true', isPrivate.value, 'Booleans are true or false');
        Assert.areEqual('datetime', created.inputType, 'Datetimes get a datetime input');
        Assert.isTrue(created.value.startsWith('2026-10-17T09:30:00'), 'Datetimes are ISO: ' + created.value);
        Assert.areEqual('text', name.inputType, 'Text is text');
        Assert.isNull(name.value, 'Blank is null');
        Assert.areEqual('(blank)', name.currentDisplay, 'Blank shows as (blank)');
    }

    @IsTest
    static void shouldParseValuesByFieldType() {
        Assert.areEqual(true, FlowProofWhatIfField.parse(fieldValue('X', 'BOOLEAN', null), 'true'), 'Boolean');
        Assert.areEqual(false, FlowProofWhatIfField.parse(fieldValue('X', 'BOOLEAN', null), ''), 'Blank boolean');
        Assert.isTrue(
            (Decimal) FlowProofWhatIfField.parse(fieldValue('X', 'CURRENCY', null), ' 12.5 ') == 12.5,
            'Currency'
        );
        Assert.areEqual(3, FlowProofWhatIfField.parse(fieldValue('X', 'INTEGER', null), '3'), 'Integer');
        Assert.areEqual(4L, FlowProofWhatIfField.parse(fieldValue('X', 'LONG', null), '4'), 'Long');
        Assert.areEqual(
            Date.newInstance(2026, 10, 17),
            FlowProofWhatIfField.parse(fieldValue('X', 'DATE', null), '2026-10-17'),
            'Date'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 17, 9, 30, 0),
            FlowProofWhatIfField.parse(fieldValue('X', 'DATETIME', null), '2026-10-17T09:30:00.000Z'),
            'Datetime'
        );
        Assert.areEqual('EMEA', FlowProofWhatIfField.parse(fieldValue('X', 'PICKLIST', null), 'EMEA'), 'Text');
        Assert.isNull(FlowProofWhatIfField.parse(fieldValue('X', 'CURRENCY', null), ' '), 'Blank is null');
    }

    @IsTest
    static void shouldRejectValuesThatDoNotFit() {
        for (String fieldType : new List<String>{ 'CURRENCY', 'DATE', 'DATETIME' }) {
            try {
                FlowProofWhatIfField.parse(fieldValue('Amount', fieldType, null), 'not-a-value');
                Assert.fail('Expected IllegalArgumentException for ' + fieldType);
            } catch (IllegalArgumentException e) {
                Assert.isTrue(e.getMessage().contains('Amount'), 'The message names the field: ' + e.getMessage());
            }
        }
    }

    private static FlowProofRecordSnapshot.FieldValue fieldValue(String apiName, String fieldType, Object value) {
        FlowProofRecordSnapshot snapshot = new FlowProofRecordSnapshot('Opportunity');
        snapshot.putValue(apiName, fieldType, value);
        return snapshot.getField(apiName);
    }
}
