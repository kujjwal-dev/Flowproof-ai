/**
 * Reads the Flow and validation events of one debug log (Workflow at FINER, Validation at INFO).
 * Pure: no SOQL, DML or callouts. Only names, Ids and outcomes are kept; the field values that
 * the log also contains (for example the $Record snapshot) are never stored.
 *
 * Log lines look like: 03:17:05.107 (109379645)|FLOW_ELEMENT_BEGIN|<interview>|FlowRecordCreate|Create_Task
 *
 * @example
 * FlowProofDebugLogParser.ParsedLog parsed = new FlowProofDebugLogParser().parse(logBody);
 */
public with sharing class FlowProofDebugLogParser {
    private static final Map<String, String> ELEMENT_TYPES = new Map<String, String>{
        'FlowRecordCreate' => 'Create Records',
        'FlowRecordUpdate' => 'Update Records',
        'FlowRecordLookup' => 'Get Records',
        'FlowRecordDelete' => 'Delete Records',
        'FlowDecision' => 'Decision',
        'FlowAssignment' => 'Assignment',
        'FlowLoop' => 'Loop',
        'FlowActionCall' => 'Action',
        'FlowApexPluginCall' => 'Apex Action',
        'FlowSubflow' => 'Subflow',
        'FlowCustomError' => 'Custom Error',
        'FlowWait' => 'Wait'
    };
    private static final String RECORD_VARIABLE = '$Record';
    private static final String ID_PREFIX = '{Id=';

    /**
     * Parses a debug log.
     * @param logBody the log text
     * @return the Flow interviews, the objects whose record-triggered Flows were evaluated, and validation failures
     */
    public ParsedLog parse(String logBody) {
        ParsedLog parsed = new ParsedLog();
        if (String.isBlank(logBody)) {
            return parsed;
        }
        String pendingVersionId;
        String currentRule;
        Interview current;
        for (String line : logBody.split('\n')) {
            List<String> parts = line.trim().split('\\|');
            if (parts.size() < 2) {
                continue;
            }
            String eventName = parts[1];
            if (eventName == 'CODE_UNIT_STARTED' && parts.size() > 3 && parts[3].startsWith('Flow:')) {
                parsed.flowObjects.add(parts[3].removeStart('Flow:').toLowerCase());
            } else if (eventName == 'FLOW_CREATE_INTERVIEW_BEGIN' && parts.size() > 4) {
                pendingVersionId = parts[4];
            } else if (eventName == 'FLOW_CREATE_INTERVIEW_END' && parts.size() > 3) {
                Interview interview = parsed.interview(parts[2]);
                interview.label = parts[3];
                interview.versionId = pendingVersionId;
                pendingVersionId = null;
            } else if (eventName == 'FLOW_START_INTERVIEW_BEGIN' && parts.size() > 2) {
                current = parsed.interview(parts[2]);
                current.started = true;
                if (String.isBlank(current.label) && parts.size() > 3) {
                    current.label = parts[3];
                }
            } else if (eventName == 'FLOW_VALUE_ASSIGNMENT' && parts.size() > 4 && parts[3] == RECORD_VARIABLE) {
                String recordId = recordIdOf(parts[4]);
                if (recordId != null) {
                    parsed.interview(parts[2]).recordIds.add(recordId);
                }
            } else if (eventName == 'FLOW_ELEMENT_BEGIN' && parts.size() > 4) {
                Interview interview = parsed.interview(parts[2]);
                current = interview;
                String element = '"' + parts[4] + '" (' + (ELEMENT_TYPES.get(parts[3]) ?? parts[3]) + ')';
                if (!interview.elements.contains(element)) {
                    interview.elements.add(element);
                }
            } else if (
                eventName == 'FLOW_RULE_DETAIL' &&
                parts.size() > 4 &&
                parts[parts.size() - 1].trim() == 'true'
            ) {
                parsed.interview(parts[2]).outcomes.add(parts[3]);
            } else if (eventName == 'FLOW_INTERVIEW_FINISHED' && parts.size() > 2) {
                parsed.interview(parts[2]).finished = true;
            } else if (eventName.startsWith('FLOW_') && (eventName.contains('ERROR') || eventName.contains('FAULT'))) {
                Interview target = parts.size() > 2 && parsed.interviews.containsKey(parts[2])
                    ? parsed.interview(parts[2])
                    : current;
                if (target != null) {
                    target.errors.add(String.join(tail(parts, 2), ' | ').abbreviate(500));
                }
            } else if (eventName == 'VALIDATION_RULE' && parts.size() > 3) {
                currentRule = parts[3];
            } else if (eventName == 'VALIDATION_FAIL') {
                parsed.validationFailures.add(currentRule ?? 'A validation rule');
            } else if (eventName == 'VALIDATION_ERROR' && parts.size() > 2) {
                parsed.validationMessages.add(String.join(tail(parts, 2), ' | ').abbreviate(500));
            }
        }
        return parsed;
    }

    // $Record values look like {Id=006..., IsDeleted=false, ...}; only the Id is read.
    private static String recordIdOf(String value) {
        if (value == null || !value.startsWith(ID_PREFIX)) {
            return null;
        }
        String rest = value.removeStart(ID_PREFIX);
        Integer endIndex = rest.indexOfAny(',}');
        String candidate = (endIndex < 0 ? rest : rest.left(endIndex)).trim();
        return candidate.length() == 15 || candidate.length() == 18 ? candidate : null;
    }

    private static List<String> tail(List<String> parts, Integer start) {
        List<String> values = new List<String>();
        for (Integer i = start; i < parts.size(); i++) {
            values.add(parts[i]);
        }
        return values;
    }

    /** What one debug log says about Flows and validation. */
    public with sharing class ParsedLog {
        /** Interviews by interview Id, in the order they appeared. */
        public Map<String, Interview> interviews = new Map<String, Interview>();
        /** Lower-case API names of objects whose record-triggered Flows ran in this log. */
        public Set<String> flowObjects = new Set<String>();
        /** Names of validation rules that failed. */
        public List<String> validationFailures = new List<String>();
        /** Validation error messages shown to the user. */
        public List<String> validationMessages = new List<String>();

        /**
         * @param interviewId interview Id from the log
         * @return the interview, created on first use
         */
        public Interview interview(String interviewId) {
            if (!interviews.containsKey(interviewId)) {
                interviews.put(interviewId, new Interview(interviewId));
            }
            return interviews.get(interviewId);
        }

        /**
         * Adds another log of the same save; one save can be written as several logs.
         * @param other another parsed log
         */
        public void addLog(ParsedLog other) {
            for (String interviewId : other.interviews.keySet()) {
                if (!interviews.containsKey(interviewId)) {
                    interviews.put(interviewId, other.interviews.get(interviewId));
                }
            }
            flowObjects.addAll(other.flowObjects);
            validationFailures.addAll(other.validationFailures);
            validationMessages.addAll(other.validationMessages);
        }

        /**
         * @param recordId a record Id (15 or 18 characters)
         * @return true when a Flow in this log ran for that record
         */
        public Boolean mentionsRecord(Id recordId) {
            return !interviewsFor(recordId).isEmpty();
        }

        /**
         * @param recordId a record Id
         * @return the started interviews whose $Record was that record
         */
        public List<Interview> interviewsFor(Id recordId) {
            String id15 = String.valueOf(recordId).left(15);
            List<Interview> matches = new List<Interview>();
            for (Interview interview : interviews.values()) {
                for (String candidate : interview.recordIds) {
                    if (interview.started && candidate.left(15).equals(id15)) {
                        matches.add(interview);
                        break;
                    }
                }
            }
            return matches;
        }
    }

    /** One Flow interview in the log. */
    public with sharing class Interview {
        /** Interview Id from the log. */
        public String interviewId;
        /** Flow label. */
        public String label;
        /** Flow version Id (15 characters, prefix 301). */
        public String versionId;
        /** True once the interview started. */
        public Boolean started = false;
        /** True when the interview finished. */
        public Boolean finished = false;
        /** Ids of the records the interview ran for ($Record). */
        public Set<String> recordIds = new Set<String>();
        /** Elements that ran, e.g. "Create_Task" (Create Records), in order. */
        public List<String> elements = new List<String>();
        /** Decision outcomes that were true. */
        public List<String> outcomes = new List<String>();
        /** Error and fault lines. */
        public List<String> errors = new List<String>();

        /**
         * @param interviewId interview Id from the log
         */
        public Interview(String interviewId) {
            this.interviewId = interviewId;
        }
    }
}
