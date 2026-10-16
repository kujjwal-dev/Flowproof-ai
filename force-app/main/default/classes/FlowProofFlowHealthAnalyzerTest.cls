/**
 * Unit tests for FlowProofFlowHealthAnalyzer. Flow metadata is built in the shape the Tooling API
 * returns for Flow.Metadata (element lists keyed by type, connectors with targetReference).
 */
@IsTest
private class FlowProofFlowHealthAnalyzerTest {
    // Built at runtime: syntactically valid record Ids that exist in no org.
    private static final String ID_15 = '00G' + '5g0000' + '0ABcDE';

    @IsTest
    static void shouldFindRecordUpdateInsideLoop() {
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Loop_Contacts');
        metadata.put(
            'loops',
            new List<Object>{
                element('Loop_Contacts', 'Loop Contacts')
                    .put('nextValueConnector', connector('Check_Contact'))
                    .put('noMoreValuesConnector', connector('Create_Summary'))
                    .raw
            }
        );
        metadata.put(
            'decisions',
            new List<Object>{
                element('Check_Contact', 'Check Contact')
                    .put(
                        'rules',
                        new List<Object>{ new Map<String, Object>{ 'connector' => connector('Update_Contact') } }
                    )
                    .put('defaultConnector', connector('Loop_Contacts'))
                    .raw
            }
        );
        metadata.put(
            'recordUpdates',
            new List<Object>{
                protectedElement('Update_Contact', 'Update Contact').put('connector', connector('Loop_Contacts')).raw
            }
        );
        metadata.put('recordCreates', new List<Object>{ protectedElement('Create_Summary', 'Create Summary').raw });

        FlowProofFinding finding = findRule(analyze(metadata, null), 'DATA_OPERATION_IN_LOOP');

        Assert.isNotNull(finding, 'An update inside a loop should be reported');
        Assert.areEqual(FlowProofFinding.Severity.HIGH, finding.severity, 'Data operations in loops are high severity');
        Assert.isTrue(finding.detail.contains('"Update Contact" (Update Records)'), 'The element should be named');
        Assert.isTrue(finding.detail.contains('"Loop Contacts" (Loop)'), 'The loop should be named');
        Assert.isFalse(finding.detail.contains('Create Summary'), 'Elements after the loop are not inside it');
    }

    @IsTest
    static void shouldNotReportLoopWithoutDataOperations() {
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Loop_Items');
        metadata.put(
            'loops',
            new List<Object>{ element('Loop_Items', 'Loop Items').put('nextValueConnector', connector('Add_Item')).raw }
        );
        metadata.put(
            'assignments',
            new List<Object>{ element('Add_Item', 'Add Item').put('connector', connector('Loop_Items')).raw }
        );

        Assert.isNull(findRule(analyze(metadata, null), 'DATA_OPERATION_IN_LOOP'), 'Assignments in loops are fine');
    }

    @IsTest
    static void shouldFindUpdateOfTriggeringRecordAfterSave() {
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Set_Status');
        metadata.put(
            'recordUpdates',
            new List<Object>{
                protectedElement('Set_Status', 'Set Status').put('inputReference', '$Record').raw,
                protectedElement('Set_Owner', 'Set Owner')
                    .put('object', 'Opportunity')
                    .put(
                        'filters',
                        new List<Object>{
                            new Map<String, Object>{
                                'field' => 'Id',
                                'operator' => 'EqualTo',
                                'value' => new Map<String, Object>{ 'elementReference' => '$Record.Id' }
                            }
                        }
                    )
                    .raw,
                protectedElement('Update_Account', 'Update Account').put('object', 'Account').raw
            }
        );

        FlowProofFinding finding = findRule(analyze(metadata, null), 'SAME_RECORD_UPDATE_AFTER_SAVE');

        Assert.isNotNull(finding, 'Updating $Record after save should be reported');
        Assert.isTrue(finding.detail.contains('Set Status'), 'The $Record update should be named');
        Assert.isTrue(finding.detail.contains('Set Owner'), 'An update filtered to $Record.Id should be named');
        Assert.isFalse(finding.detail.contains('Update Account'), 'Updates of other records are not reported');
    }

    @IsTest
    static void shouldNotReportRecordUpdateInBeforeSaveFlow() {
        Map<String, Object> start = afterSaveStart(true);
        start.put('triggerType', 'RecordBeforeSave');
        Map<String, Object> metadata = flow(start, 'Set_Status');
        metadata.put(
            'recordUpdates',
            new List<Object>{ protectedElement('Set_Status', 'Set Status').put('inputReference', '$Record').raw }
        );

        Assert.isNull(
            findRule(analyze(metadata, null), 'SAME_RECORD_UPDATE_AFTER_SAVE'),
            'Only after-save Flows save the record twice'
        );
    }

    @IsTest
    static void shouldReportMissingEntryConditionsAndFirstDecision() {
        Map<String, Object> start = afterSaveStart(false);
        start.remove('filters');
        start.remove('filterLogic');
        Map<String, Object> metadata = flow(start, 'Is_Won');
        metadata.put(
            'decisions',
            new List<Object>{ element('Is_Won', 'Is Won').put('defaultConnector', connector('Create_Task')).raw }
        );
        metadata.put('recordCreates', new List<Object>{ protectedElement('Create_Task', 'Create Task').raw });

        FlowProofFinding finding = findRule(analyze(metadata, null), 'NO_ENTRY_CONDITIONS');

        Assert.isNotNull(finding, 'A Flow without entry conditions should be reported');
        Assert.areEqual(FlowProofFinding.Severity.MEDIUM, finding.severity, 'It does work on every save');
        Assert.isTrue(finding.detail.contains('"Is Won" (Decision)'), 'The first Decision should be suggested');
    }

    @IsTest
    static void shouldRateMissingEntryConditionsLowWhenFlowOnlyAssigns() {
        Map<String, Object> start = afterSaveStart(false);
        start.remove('filters');
        Map<String, Object> metadata = flow(start, 'Set_Value');
        metadata.put('assignments', new List<Object>{ element('Set_Value', 'Set Value').raw });

        FlowProofFinding finding = findRule(analyze(metadata, null), 'NO_ENTRY_CONDITIONS');

        Assert.areEqual(FlowProofFinding.Severity.LOW, finding.severity, 'A Flow that changes nothing is low risk');
    }

    @IsTest
    static void shouldReportRepeatedWorkOnEveryUpdate() {
        Map<String, Object> metadata = flow(afterSaveStart(false), 'Create_Task');
        metadata.put('recordCreates', new List<Object>{ protectedElement('Create_Task', 'Create Task').raw });

        FlowProofFinding finding = findRule(analyze(metadata, null), 'REPEATED_WORK_ON_EVERY_UPDATE');

        Assert.isNotNull(finding, 'Creating records on every qualifying update should be reported');
        Assert.areEqual(
            FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
            finding.category,
            'Duplicates are possible, not proven'
        );
        Assert.isTrue(finding.detail.contains('Create Task'), 'The repeated element should be named');
    }

    @IsTest
    static void shouldNotReportRepeatedWorkWhenFlowChecksForChanges() {
        Map<String, Object> onlyWhenMet = flow(afterSaveStart(true), 'Create_Task');
        onlyWhenMet.put('recordCreates', new List<Object>{ protectedElement('Create_Task', 'Create Task').raw });

        Map<String, Object> isChangedStart = afterSaveStart(false);
        ((List<Object>) isChangedStart.get('filters'))
            .add(
                new Map<String, Object>{
                    'field' => 'StageName',
                    'operator' => 'IsChanged',
                    'value' => new Map<String, Object>{ 'booleanValue' => true }
                }
            );
        Map<String, Object> isChanged = flow(isChangedStart, 'Create_Task');
        isChanged.put('recordCreates', new List<Object>{ protectedElement('Create_Task', 'Create Task').raw });

        Map<String, Object> formulaStart = afterSaveStart(false);
        formulaStart.remove('filters');
        formulaStart.put('filterFormula', 'ISCHANGED({!$Record.StageName})');
        Map<String, Object> formula = flow(formulaStart, 'Create_Task');
        formula.put('recordCreates', new List<Object>{ protectedElement('Create_Task', 'Create Task').raw });

        Assert.isNull(
            findRule(analyze(onlyWhenMet, null), 'REPEATED_WORK_ON_EVERY_UPDATE'),
            'Only when updated to meet'
        );
        Assert.isNull(findRule(analyze(isChanged, null), 'REPEATED_WORK_ON_EVERY_UPDATE'), 'Is Changed condition');
        Assert.isNull(findRule(analyze(formula, null), 'REPEATED_WORK_ON_EVERY_UPDATE'), 'ISCHANGED formula');
    }

    @IsTest
    static void shouldFindValuesThatLookLikeRecordIds() {
        String id18 = String.valueOf(Id.valueOf(ID_15));
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Assign_Queue');
        metadata.put(
            'assignments',
            new List<Object>{
                element('Assign_Queue', 'Assign Queue')
                    .put('assignmentItems', new List<Object>{ new Map<String, Object>{ 'value' => stringValue(id18) } })
                    .raw,
                element('Set_Stage', 'Set Stage')
                    .put(
                        'assignmentItems',
                        new List<Object>{ new Map<String, Object>{ 'value' => stringValue('Closed Won') } }
                    )
                    .raw
            }
        );
        metadata.put(
            'formulas',
            new List<Object>{ element('Owner_Check', 'Owner Check').put('expression', 'OwnerId = "' + ID_15 + '"').raw }
        );
        metadata.put('description', 'Mentions ' + id18 + ' only in a description.');

        FlowProofFinding finding = findRule(analyze(metadata, null), 'POSSIBLE_HARDCODED_IDS');

        Assert.isNotNull(finding, 'Record Ids in values should be reported');
        Assert.isTrue(finding.detail.contains('Assign Queue'), 'An 18-character Id should be found');
        Assert.isTrue(finding.detail.contains('Owner Check'), 'A 15-character Id in a formula should be found');
        Assert.isFalse(finding.detail.contains('Set Stage'), 'Ordinary text is not an Id');
    }

    @IsTest
    static void shouldIgnoreIdShapedTextWithWrongChecksum() {
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Set_Code');
        metadata.put(
            'assignments',
            new List<Object>{
                element('Set_Code', 'Set Code')
                    .put(
                        'assignmentItems',
                        new List<Object>{ new Map<String, Object>{ 'value' => stringValue(ID_15 + 'ZZZ') } }
                    )
                    .raw
            }
        );

        Assert.isNull(findRule(analyze(metadata, null), 'POSSIBLE_HARDCODED_IDS'), 'A bad checksum means not an Id');
    }

    @IsTest
    static void shouldListElementsWithoutFaultPaths() {
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Get_1');
        List<Object> lookups = new List<Object>();
        for (Integer i = 1; i <= 7; i++) {
            lookups.add(element('Get_' + i, 'Get ' + i).raw);
        }
        lookups.add(protectedElement('Get_Safe', 'Get Safe').raw);
        metadata.put('recordLookups', lookups);

        FlowProofFinding finding = findRule(analyze(metadata, null), 'MISSING_FAULT_PATHS');

        Assert.isNotNull(finding, 'Elements without fault paths should be reported');
        Assert.isTrue(finding.detail.contains('and 2 more'), 'Long lists should be shortened: ' + finding.detail);
        Assert.isFalse(finding.detail.contains('Get Safe'), 'Elements with a fault path are fine');
    }

    @IsTest
    static void shouldReportTriggerOrderOnlyWhenOtherFlowsShareTheTrigger() {
        Map<String, Object> metadata = flow(afterSaveStart(true), null);
        Map<String, Object> ordered = flow(afterSaveStart(true), null);
        ordered.put('triggerOrder', 10);

        FlowProofFinding finding = findRule(analyze(metadata, 2), 'TRIGGER_ORDER_NOT_SET');

        Assert.isNotNull(finding, 'Unordered Flows sharing a trigger should be reported');
        Assert.isTrue(finding.detail.contains('2 other active Flows'), 'The other Flows should be counted');
        Assert.isNull(findRule(analyze(metadata, 0), 'TRIGGER_ORDER_NOT_SET'), 'No other Flows, no order needed');
        Assert.isNull(findRule(analyze(metadata, null), 'TRIGGER_ORDER_NOT_SET'), 'Unknown peers are not reported');
        Assert.isNull(findRule(analyze(ordered, 2), 'TRIGGER_ORDER_NOT_SET'), 'A set Trigger Order is fine');
    }

    @IsTest
    static void shouldFindNothingInHealthyFlow() {
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Create_Task');
        metadata.put(
            'recordCreates',
            new List<Object>{ protectedElement('Create_Task', 'Create Task').put('object', 'Task').raw }
        );

        Assert.areEqual(0, analyze(metadata, 0).size(), 'A healthy Flow has no health findings');
    }

    @IsTest
    static void shouldSortMostSevereFirst() {
        Map<String, Object> metadata = flow(afterSaveStart(true), 'Loop_Contacts');
        metadata.put(
            'loops',
            new List<Object>{
                element('Loop_Contacts', 'Loop Contacts').put('nextValueConnector', connector('Get_Contact')).raw
            }
        );
        metadata.put(
            'recordLookups',
            new List<Object>{ element('Get_Contact', 'Get Contact').put('connector', connector('Loop_Contacts')).raw }
        );

        List<FlowProofFinding> findings = analyze(metadata, null);

        Assert.areEqual('DATA_OPERATION_IN_LOOP', findings[0].ruleCode, 'High severity comes first');
        Assert.areEqual('MISSING_FAULT_PATHS', findings[1].ruleCode, 'Low severity comes later');
    }

    @IsTest
    static void shouldReturnNoFindingsWithoutMetadata() {
        FlowProofFlowHealthAnalyzer analyzer = new FlowProofFlowHealthAnalyzer();

        Assert.areEqual(0, analyzer.analyze(null, 1).size(), 'No definition, no findings');
        Assert.areEqual(
            0,
            analyzer.analyze(new FlowProofFlowDefinition(null, null), 1).size(),
            'No metadata, no findings'
        );
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static List<FlowProofFinding> analyze(Map<String, Object> metadata, Integer otherFlows) {
        return new FlowProofFlowHealthAnalyzer().analyze(new FlowProofFlowDefinition(null, metadata), otherFlows);
    }

    private static FlowProofFinding findRule(List<FlowProofFinding> findings, String ruleCode) {
        for (FlowProofFinding finding : findings) {
            if (finding.ruleCode == ruleCode) {
                return finding;
            }
        }
        return null;
    }

    private static Map<String, Object> flow(Map<String, Object> start, String firstElement) {
        if (firstElement != null) {
            start.put('connector', connector(firstElement));
        }
        return new Map<String, Object>{
            'label' => 'Test Flow',
            'processType' => 'AutoLaunchedFlow',
            'processMetadataValues' => new List<Object>{
                new Map<String, Object>{ 'name' => 'BuilderType', 'value' => stringValue('LightningFlowBuilder') }
            },
            'start' => start
        };
    }

    /** After save on Opportunity, created or updated, with one entry condition. */
    private static Map<String, Object> afterSaveStart(Boolean onlyWhenUpdatedToMeetConditions) {
        return new Map<String, Object>{
            'object' => 'Opportunity',
            'triggerType' => 'RecordAfterSave',
            'recordTriggerType' => 'CreateAndUpdate',
            'doesRequireRecordChangedToMeetCriteria' => onlyWhenUpdatedToMeetConditions,
            'filterLogic' => 'and',
            'filters' => new List<Object>{
                new Map<String, Object>{
                    'field' => 'StageName',
                    'operator' => 'EqualTo',
                    'value' => stringValue('Closed Won')
                }
            }
        };
    }

    private static ElementBuilder element(String name, String label) {
        return new ElementBuilder(name, label);
    }

    private static ElementBuilder protectedElement(String name, String label) {
        return new ElementBuilder(name, label).put('faultConnector', connector('Log_Error'));
    }

    private static Map<String, Object> connector(String target) {
        return new Map<String, Object>{ 'targetReference' => target };
    }

    private static Map<String, Object> stringValue(String value) {
        return new Map<String, Object>{ 'stringValue' => value };
    }

    private class ElementBuilder {
        final Map<String, Object> raw = new Map<String, Object>();

        ElementBuilder(String name, String label) {
            raw.put('name', name);
            raw.put('label', label);
            raw.put('locationX', 0);
        }

        ElementBuilder put(String key, Object value) {
            raw.put(key, value);
            return this;
        }
    }
}
