/**
 * Best-practice ("health") checks over one Flow version's full metadata: performance, reliability
 * and maintenance risks that hold whichever record is saved. Suggest-only: FlowProof never changes
 * a Flow. Each finding names the Flow elements it is based on. Pure: no SOQL, DML or callouts.
 *
 * @example
 * List<FlowProofFinding> health = new FlowProofFlowHealthAnalyzer().analyze(definition, 2);
 */
public with sharing class FlowProofFlowHealthAnalyzer {
    private static final Map<String, String> DATA_ELEMENT_TYPES = new Map<String, String>{
        'recordLookups' => 'Get Records',
        'recordCreates' => 'Create Records',
        'recordUpdates' => 'Update Records',
        'recordDeletes' => 'Delete Records'
    };
    private static final Map<String, String> OTHER_ELEMENT_TYPES = new Map<String, String>{
        'actionCalls' => 'Action',
        'subflows' => 'Subflow',
        'loops' => 'Loop',
        'decisions' => 'Decision',
        'assignments' => 'Assignment',
        'constants' => 'Constant',
        'formulas' => 'Formula',
        'variables' => 'Variable',
        'textTemplates' => 'Text Template'
    };
    // Element types whose failures can be caught with a fault path.
    private static final List<String> FAULT_PATH_TYPES = new List<String>{
        'recordLookups',
        'recordCreates',
        'recordUpdates',
        'recordDeletes',
        'actionCalls'
    };
    // Keys that hold names, labels or layout rather than values a Flow uses at run time.
    private static final Set<String> NON_VALUE_KEYS = new Set<String>{
        'processMetadataValues',
        'name',
        'label',
        'description',
        'interviewLabel',
        'targetReference',
        'elementReference',
        'locationX',
        'locationY'
    };
    private static final Pattern ID_PATTERN = Pattern.compile('\\b0[0-9A-Za-z]{14}(?:[0-9A-Za-z]{3})?\\b');
    private static final String CHECKSUM_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    private static final Integer MIN_ID_DIGITS = 4;
    private static final Integer MAX_NAMES = 5;
    private static final String START_LOCATION = 'Start (entry conditions)';

    /**
     * Runs every health check.
     * @param definition the Flow version; nothing is checked when it or its metadata is null
     * @param otherActiveFlowsAtSameTrigger number of other active Flows that run at the same point
     *        (same object, before or after save); null when unknown or when this Flow is inactive
     * @return health findings, most important first; empty when nothing was found
     */
    public List<FlowProofFinding> analyze(FlowProofFlowDefinition definition, Integer otherActiveFlowsAtSameTrigger) {
        List<FlowProofFinding> findings = new List<FlowProofFinding>();
        if (definition == null || definition.metadata == null) {
            return findings;
        }
        Map<String, Object> metadata = definition.metadata;
        Map<String, Object> start = asMap(metadata.get('start')) ?? new Map<String, Object>();
        FlowGraph graph = new FlowGraph(metadata);

        addIfPresent(findings, dataOperationsInLoops(graph));
        addIfPresent(findings, sameRecordUpdateAfterSave(graph, start));
        addIfPresent(findings, noEntryConditions(graph, start));
        addIfPresent(findings, repeatedWorkOnEveryUpdate(graph, start));
        addIfPresent(findings, possibleHardcodedIds(graph, start));
        addIfPresent(findings, missingFaultPaths(graph));
        addIfPresent(findings, triggerOrderNotSet(metadata, start, otherActiveFlowsAtSameTrigger));

        for (Integer i = 0; i < findings.size(); i++) {
            findings[i].sortOrder = i + 1;
        }
        findings.sort();
        return findings;
    }

    // ─── Rules ───────────────────────────────────────────────────────────

    private static FlowProofFinding dataOperationsInLoops(FlowGraph graph) {
        List<String> locations = new List<String>();
        Set<String> seen = new Set<String>();
        for (FlowElement loopElement : graph.ofType('loops')) {
            List<String> inLoop = new List<String>();
            for (FlowElement element : loopBody(graph, loopElement)) {
                if (DATA_ELEMENT_TYPES.containsKey(element.type) && seen.add(element.name)) {
                    inLoop.add(element.display());
                }
            }
            if (!inLoop.isEmpty()) {
                locations.add('inside loop ' + loopElement.display() + ': ' + joinNames(inLoop));
            }
        }
        if (locations.isEmpty()) {
            return null;
        }
        return new FlowProofFinding(
                'DATA_OPERATION_IN_LOOP',
                FlowProofFinding.Category.CONFIRMED,
                FlowProofFinding.Severity.HIGH
            )
            .describe(
                'Records are read or saved inside a loop',
                'Found ' +
                    String.join(locations, '; ') +
                    '. Each pass through a loop runs its own query or save, so a bulk change (a data import, or an ' +
                    'integration saving many records at once) can reach Salesforce limits (100 queries, 150 saves per ' +
                    'transaction) and fail the whole save.',
                'Inside the loop, add records to a collection variable with an Assignment, then save the collection once ' +
                    'after the loop with a single Create or Update Records element. For Get Records, query once before the ' +
                    'loop and work with the collection.'
            );
    }

    private static FlowProofFinding sameRecordUpdateAfterSave(FlowGraph graph, Map<String, Object> start) {
        if (asString(start.get('triggerType')) != 'RecordAfterSave') {
            return null;
        }
        String triggerObject = asString(start.get('object'));
        List<String> updates = new List<String>();
        for (FlowElement element : graph.ofType('recordUpdates')) {
            if (updatesTriggeringRecord(element.raw, triggerObject)) {
                updates.add(element.display());
            }
        }
        if (updates.isEmpty()) {
            return null;
        }
        return new FlowProofFinding(
                'SAME_RECORD_UPDATE_AFTER_SAVE',
                FlowProofFinding.Category.CONFIRMED,
                FlowProofFinding.Severity.MEDIUM
            )
            .describe(
                'The Flow updates the triggering record after it is saved',
                joinNames(updates) +
                    ' updates the record that started this after-save Flow. That saves the record a second time, which ' +
                    'runs its triggers, validation rules and Flows again.',
                'If the update only sets fields on the triggering record, do it in a before-save Flow (Optimize the Flow ' +
                'for: Fast Field Updates) by assigning values to $Record. It is much faster and does not save the record twice.'
            );
    }

    private static FlowProofFinding noEntryConditions(FlowGraph graph, Map<String, Object> start) {
        if (hasEntryConditions(start)) {
            return null;
        }
        Boolean doesWork =
            !graph.ofTypes(DATA_ELEMENT_TYPES.keySet()).isEmpty() || !graph.ofType('actionCalls').isEmpty();
        String detail =
            'The Flow has no entry conditions, so it starts every time a ' +
            (asString(start.get('object')) ?? 'record') +
            ' record is ' +
            savedPhrase(asString(start.get('recordTriggerType'))) +
            ', including saves that have nothing to do with what it is for.';
        FlowElement first = graph.byName.get(connectorTarget(start.get('connector')) ?? '');
        if (first?.type == 'decisions') {
            detail +=
                ' Its first element is the Decision ' +
                first.display() +
                ', which could become an entry condition.';
        }
        return new FlowProofFinding(
                'NO_ENTRY_CONDITIONS',
                FlowProofFinding.Category.CONFIRMED,
                doesWork ? FlowProofFinding.Severity.MEDIUM : FlowProofFinding.Severity.LOW
            )
            .describe(
                'The Flow starts on every save',
                detail,
                'Add entry conditions in the Start element so the Flow only starts for the records it needs to act on.'
            );
    }

    private static FlowProofFinding repeatedWorkOnEveryUpdate(FlowGraph graph, Map<String, Object> start) {
        String recordTriggerType = asString(start.get('recordTriggerType'));
        Boolean runsOnUpdate = recordTriggerType == 'Update' || recordTriggerType == 'CreateAndUpdate';
        if (
            !runsOnUpdate ||
            !hasEntryConditions(start) ||
            start.get('doesRequireRecordChangedToMeetCriteria') == true ||
            checksForChanges(start)
        ) {
            return null;
        }
        List<String> repeatable = new List<String>();
        for (FlowElement element : graph.ofTypes(new Set<String>{ 'recordCreates', 'actionCalls' })) {
            repeatable.add(element.display());
        }
        if (repeatable.isEmpty()) {
            return null;
        }
        return new FlowProofFinding(
                'REPEATED_WORK_ON_EVERY_UPDATE',
                FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
                FlowProofFinding.Severity.MEDIUM
            )
            .describe(
                'The Flow can repeat its work on every edit',
                'The Flow runs each time a record that meets its entry conditions is updated, not only when the record ' +
                    'first meets them, and it creates records or runs actions (' +
                    joinNames(repeatable) +
                    '). Each later edit of a qualifying record can create duplicates or send repeat emails.',
                'In the Start element, set "When to Run the Flow for Updated Records" to "Only when a record is updated to ' +
                'meet the condition requirements", or add an "Is Changed" entry condition.'
            );
    }

    private static FlowProofFinding possibleHardcodedIds(FlowGraph graph, Map<String, Object> start) {
        List<String> locations = new List<String>();
        if (containsLikelyId(start, null)) {
            locations.add(START_LOCATION);
        }
        for (FlowElement element : graph.elements) {
            if (containsLikelyId(element.raw, null)) {
                locations.add(element.display());
            }
        }
        if (locations.isEmpty()) {
            return null;
        }
        return new FlowProofFinding(
                'POSSIBLE_HARDCODED_IDS',
                FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
                FlowProofFinding.Severity.MEDIUM
            )
            .describe(
                'The Flow may contain hard-coded record Ids',
                'Values that look like Salesforce record Ids appear in ' +
                    joinNames(locations) +
                    '. Record Ids differ between sandboxes and production, so the Flow can stop working after it is deployed.',
                'Find the record by a stable value instead (a DeveloperName, a unique name or a Custom Metadata setting) ' +
                'with Get Records, or keep the value in a Custom Label.'
            );
    }

    private static FlowProofFinding missingFaultPaths(FlowGraph graph) {
        List<String> unprotected = new List<String>();
        for (FlowElement element : graph.ofTypes(new Set<String>(FAULT_PATH_TYPES))) {
            if (connectorTarget(element.raw.get('faultConnector')) == null) {
                unprotected.add(element.display());
            }
        }
        if (unprotected.isEmpty()) {
            return null;
        }
        return new FlowProofFinding(
                'MISSING_FAULT_PATHS',
                FlowProofFinding.Category.CONFIRMED,
                FlowProofFinding.Severity.LOW
            )
            .describe(
                'Some elements have no fault path',
                joinNames(unprotected) +
                    (unprotected.size() == 1 ? ' has' : ' have') +
                    ' no fault path. If one fails, the whole record save fails with a generic "unhandled fault" error, ' +
                    'and nobody is told why.',
                'Add a fault path to these elements to log the error or notify an admin. Use a Custom Error element when ' +
                'the user should see a clear message.'
            );
    }

    private static FlowProofFinding triggerOrderNotSet(
        Map<String, Object> metadata,
        Map<String, Object> start,
        Integer otherActiveFlowsAtSameTrigger
    ) {
        if (
            otherActiveFlowsAtSameTrigger == null ||
            otherActiveFlowsAtSameTrigger == 0 ||
            metadata.get('triggerOrder') != null
        ) {
            return null;
        }
        String others = otherActiveFlowsAtSameTrigger == 1
            ? '1 other active Flow also runs'
            : otherActiveFlowsAtSameTrigger + ' other active Flows also run';
        return new FlowProofFinding(
                'TRIGGER_ORDER_NOT_SET',
                FlowProofFinding.Category.CONFIRMED,
                FlowProofFinding.Severity.LOW
            )
            .describe(
                'Run order with other Flows is not set',
                others +
                    ' ' +
                    timingPhrase(asString(start.get('triggerType'))) +
                    ' on ' +
                    (asString(start.get('object')) ?? 'this object') +
                    ', and this Flow has no Trigger Order, so the order they run in is not set explicitly. If they change ' +
                    'the same records or fields, the result can depend on which runs first.',
                'Set Trigger Order in the Start element. Setup > Flow Trigger Explorer shows every Flow on this object ' +
                'and the order they run in.'
            );
    }

    // ─── Flow structure ──────────────────────────────────────────────────

    /**
     * Elements reachable from a loop's "for each item" path before the path returns to the loop.
     * Fault paths are not followed.
     */
    private static List<FlowElement> loopBody(FlowGraph graph, FlowElement loopElement) {
        List<FlowElement> body = new List<FlowElement>();
        Set<String> visited = new Set<String>{ loopElement.name };
        List<String> queue = new List<String>();
        String first = connectorTarget(loopElement.raw.get('nextValueConnector'));
        if (first != null) {
            queue.add(first);
        }
        while (!queue.isEmpty()) {
            String name = queue.remove(0);
            if (visited.contains(name) || !graph.byName.containsKey(name)) {
                continue;
            }
            visited.add(name);
            FlowElement element = graph.byName.get(name);
            body.add(element);
            queue.addAll(successors(element.raw));
        }
        return body;
    }

    private static List<String> successors(Map<String, Object> element) {
        List<String> targets = new List<String>();
        for (String key : element.keySet()) {
            Object value = element.get(key);
            if (key == 'faultConnector') {
                continue;
            }
            if (key.endsWithIgnoreCase('connector')) {
                addTarget(targets, value);
            } else if (value instanceof List<Object>) {
                // Decision outcomes, wait events and similar each carry their own connector.
                for (Object item : (List<Object>) value) {
                    Map<String, Object> child = asMap(item);
                    if (child != null) {
                        addTarget(targets, child.get('connector'));
                    }
                }
            }
        }
        return targets;
    }

    private static void addTarget(List<String> targets, Object connector) {
        String target = connectorTarget(connector);
        if (target != null) {
            targets.add(target);
        }
    }

    private static String connectorTarget(Object connector) {
        Map<String, Object> value = asMap(connector);
        return value == null ? null : asString(value.get('targetReference'));
    }

    private static Boolean updatesTriggeringRecord(Map<String, Object> element, String triggerObject) {
        if (asString(element.get('inputReference')) == '$Record') {
            return true;
        }
        String targetObject = asString(element.get('object'));
        if (String.isBlank(targetObject) || targetObject != triggerObject) {
            return false;
        }
        for (Object item : asList(element.get('filters'))) {
            Map<String, Object> filter = asMap(item) ?? new Map<String, Object>();
            Map<String, Object> value = asMap(filter.get('value')) ?? new Map<String, Object>();
            if (
                asString(filter.get('field')) == 'Id' &&
                asString(filter.get('operator')) == 'EqualTo' &&
                asString(value.get('elementReference')) == '$Record.Id'
            ) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasEntryConditions(Map<String, Object> start) {
        return !asList(start.get('filters')).isEmpty() || String.isNotBlank(asString(start.get('filterFormula')));
    }

    private static Boolean checksForChanges(Map<String, Object> start) {
        for (Object item : asList(start.get('filters'))) {
            Map<String, Object> filter = asMap(item) ?? new Map<String, Object>();
            if (asString(filter.get('operator')) == 'IsChanged') {
                return true;
            }
        }
        String formula = (asString(start.get('filterFormula')) ?? '').toUpperCase();
        return formula.contains('ISCHANGED') || formula.contains('PRIORVALUE');
    }

    // ─── Record Id detection ─────────────────────────────────────────────

    private static Boolean containsLikelyId(Object value, String key) {
        if (key != null && NON_VALUE_KEYS.contains(key)) {
            return false;
        }
        if (value instanceof String) {
            Matcher matcher = ID_PATTERN.matcher((String) value);
            while (matcher.find()) {
                if (isLikelyId(matcher.group())) {
                    return true;
                }
            }
            return false;
        }
        Map<String, Object> mapValue = asMap(value);
        if (mapValue != null) {
            for (String childKey : mapValue.keySet()) {
                if (containsLikelyId(mapValue.get(childKey), childKey)) {
                    return true;
                }
            }
            return false;
        }
        for (Object item : asList(value)) {
            if (containsLikelyId(item, null)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isLikelyId(String candidate) {
        Integer digits = 0;
        Integer letters = 0;
        for (String character : candidate.split('')) {
            if (character.isNumeric()) {
                digits++;
            } else {
                letters++;
            }
        }
        if (digits < MIN_ID_DIGITS || letters == 0) {
            return false;
        }
        return candidate.length() == 15 || hasValidChecksum(candidate);
    }

    // An 18-character Id ends with a checksum of the case of its first 15 characters.
    private static Boolean hasValidChecksum(String id18) {
        String suffix = '';
        for (Integer chunk = 0; chunk < 3; chunk++) {
            Integer flags = 0;
            for (Integer i = 0; i < 5; i++) {
                String character = id18.substring(chunk * 5 + i, chunk * 5 + i + 1);
                if (character.isAlpha() && character.isAllUpperCase()) {
                    flags += 1 << i;
                }
            }
            suffix += CHECKSUM_CHARS.substring(flags, flags + 1);
        }
        return id18.substring(15).equals(suffix);
    }

    // ─── Text helpers ────────────────────────────────────────────────────

    private static String joinNames(List<String> names) {
        if (names.size() <= MAX_NAMES) {
            return String.join(names, ', ');
        }
        List<String> shown = new List<String>();
        for (Integer i = 0; i < MAX_NAMES; i++) {
            shown.add(names[i]);
        }
        return String.join(shown, ', ') + ' and ' + (names.size() - MAX_NAMES) + ' more';
    }

    private static String savedPhrase(String recordTriggerType) {
        switch on recordTriggerType {
            when 'Create' {
                return 'created';
            }
            when 'Update' {
                return 'updated';
            }
            when 'Delete' {
                return 'deleted';
            }
            when else {
                return 'created or updated';
            }
        }
    }

    private static String timingPhrase(String triggerType) {
        switch on triggerType {
            when 'RecordBeforeSave' {
                return 'before save';
            }
            when 'RecordBeforeDelete' {
                return 'before delete';
            }
            when else {
                return 'after save';
            }
        }
    }

    private static void addIfPresent(List<FlowProofFinding> findings, FlowProofFinding finding) {
        if (finding != null) {
            findings.add(finding);
        }
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static String asString(Object value) {
        return value instanceof String ? (String) value : null;
    }

    private static String typeLabel(String type) {
        return DATA_ELEMENT_TYPES.get(type) ?? OTHER_ELEMENT_TYPES.get(type) ?? type;
    }

    // ─── Model ───────────────────────────────────────────────────────────

    /** One named Flow element (or resource) and the metadata list it came from. */
    private class FlowElement {
        final String name;
        final String label;
        final String type;
        final Map<String, Object> raw;

        FlowElement(String type, Map<String, Object> raw) {
            this.type = type;
            this.raw = raw;
            this.name = asString(raw.get('name'));
            this.label = asString(raw.get('label'));
        }

        String display() {
            return '"' + (String.isNotBlank(label) ? label : name) + '" (' + typeLabel(type) + ')';
        }
    }

    /** Every named element of a Flow, indexed by name, in metadata order. */
    private class FlowGraph {
        final List<FlowElement> elements = new List<FlowElement>();
        final Map<String, FlowElement> byName = new Map<String, FlowElement>();

        FlowGraph(Map<String, Object> metadata) {
            for (String type : metadata.keySet()) {
                if (type == 'start' || type == 'processMetadataValues') {
                    continue;
                }
                for (Object item : asList(metadata.get(type))) {
                    Map<String, Object> raw = asMap(item);
                    if (raw != null && String.isNotBlank(asString(raw.get('name')))) {
                        FlowElement element = new FlowElement(type, raw);
                        elements.add(element);
                        byName.put(element.name, element);
                    }
                }
            }
        }

        List<FlowElement> ofType(String type) {
            return ofTypes(new Set<String>{ type });
        }

        List<FlowElement> ofTypes(Set<String> types) {
            List<FlowElement> matches = new List<FlowElement>();
            for (FlowElement element : elements) {
                if (types.contains(element.type)) {
                    matches.add(element);
                }
            }
            return matches;
        }
    }
}
