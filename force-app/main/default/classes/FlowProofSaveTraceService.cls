/**
 * "Record a test save": switches on debug logging (Flows at FINER, validation at INFO) for the
 * signed-in user for 30 minutes, then reads the log of the user's next save of the record to show
 * which record-triggered Flows really ran. All Tooling API calls run as the user through
 * FlowProof_Org_API, so the user needs permission to manage debug logs. FlowProof never saves the
 * record; the user does. Only Flow names, element names, outcomes and errors are read from the log.
 *
 * @example
 * FlowProofSaveTraceSession session = new FlowProofSaveTraceService().start(recordId);
 * // ... the user saves the record ...
 * FlowProofSaveTrace trace = new FlowProofSaveTraceService().read(session);
 */
public with sharing class FlowProofSaveTraceService {
    @TestVisible
    private static final String DEBUG_LEVEL_NAME = 'FlowProof_Trace';
    private static final Integer TRACE_MINUTES = 30;
    // Clicking around Salesforce also writes logs, so look further back than the newest few.
    private static final Integer MAX_LOGS = 25;
    private static final Integer MAX_LOG_LENGTH = 3000000;
    // Logs that belong to one save start shortly before or after the record's last-modified time.
    private static final Long SAVE_WINDOW_BEFORE_MS = 5000;
    private static final Long SAVE_WINDOW_AFTER_MS = 10000;
    private static final Integer START_SLACK_SECONDS = 5;
    private static final String TRACE_FLAG_PREFIX = '7tf';
    private static final String DEBUG_LEVEL_PREFIX = '7dl';

    private final FlowProofToolingClient tooling;
    private final FlowProofFlowCatalogService catalog;

    /**
     * Creates a service that uses the org API connection and the Flow catalog.
     */
    public FlowProofSaveTraceService() {
        this(new FlowProofToolingClient(), new FlowProofFlowCatalogService());
    }

    /**
     * @param tooling Tooling API client
     * @param catalog Flow catalog
     */
    @TestVisible
    private FlowProofSaveTraceService(FlowProofToolingClient tooling, FlowProofFlowCatalogService catalog) {
        this.tooling = tooling;
        this.catalog = catalog;
    }

    /**
     * Switches on debug logging for the user. Reuses the user's own active trace flag when there is
     * one (switching it to FlowProof's debug level until stop restores it).
     * @param recordId the record the user will save
     * @return the session to pass to read and stop
     * @throws IllegalArgumentException when no record is given
     * @throws FlowProofException when the record cannot be read or logging cannot be switched on
     */
    public FlowProofSaveTraceSession start(Id recordId) {
        if (recordId == null) {
            throw new IllegalArgumentException('Choose a record first.');
        }
        String objectName = objectNameOf(recordId);
        readRecord(objectName, recordId);
        String debugLevelId = ensureDebugLevel();

        Datetime now = Datetime.now();
        FlowProofSaveTraceSession session = new FlowProofSaveTraceSession();
        session.objectApiName = objectName;
        session.recordId = recordId;
        session.startedAt = now;
        session.expiresAt = now.addMinutes(TRACE_MINUTES);

        List<Map<String, Object>> existing = tooling.query(
            'SELECT Id, DebugLevelId, ExpirationDate FROM TraceFlag WHERE LogType = \'USER_DEBUG\'' +
                ' AND TracedEntityId = \'' +
                UserInfo.getUserId() +
                '\' AND ExpirationDate > ' +
                soqlDatetime(now) +
                ' LIMIT 1'
        );
        if (existing.isEmpty()) {
            session.traceFlagId = tooling.create(
                'TraceFlag',
                new Map<String, Object>{
                    'TracedEntityId' => UserInfo.getUserId(),
                    'LogType' => 'USER_DEBUG',
                    'DebugLevelId' => debugLevelId,
                    'StartDate' => now,
                    'ExpirationDate' => session.expiresAt
                }
            );
            session.createdTraceFlag = true;
            return session;
        }
        Map<String, Object> flag = existing[0];
        session.traceFlagId = (String) flag.get('Id');
        session.createdTraceFlag = false;
        session.previousDebugLevelId = (String) flag.get('DebugLevelId');
        Map<String, Object> changes = new Map<String, Object>{ 'DebugLevelId' => debugLevelId };
        Datetime currentExpiry = parseDatetime(flag.get('ExpirationDate'));
        if (currentExpiry == null || currentExpiry < session.expiresAt) {
            changes.put('ExpirationDate', session.expiresAt);
        } else {
            session.expiresAt = currentExpiry;
        }
        tooling.updateRecord('TraceFlag', session.traceFlagId, changes);
        return session;
    }

    /**
     * Reads the newest logged save of the record since the session started. Switches logging off
     * again when a save was found; otherwise logging stays on so the user can save and try again.
     * @param session the session from start
     * @return what the save's debug log shows
     * @throws IllegalArgumentException when the session is incomplete
     * @throws FlowProofException when the log or the record cannot be read
     */
    public FlowProofSaveTrace read(FlowProofSaveTraceSession session) {
        if (session == null || session.recordId == null || session.startedAt == null) {
            throw new IllegalArgumentException('Start recording a test save first.');
        }
        // The object comes from the Id, never from the caller's text.
        String objectName = objectNameOf(session.recordId);
        SObject record = readRecord(objectName, session.recordId);
        FlowProofSaveTrace trace = new FlowProofSaveTrace();

        List<Map<String, Object>> logs = tooling.query(
            'SELECT Id, StartTime, Operation, Request, LogLength FROM ApexLog WHERE LogUserId = \'' +
                UserInfo.getUserId() +
                '\' AND StartTime >= ' +
                soqlDatetime(session.startedAt.addSeconds(-START_SLACK_SECONDS)) +
                ' ORDER BY StartTime DESC, Id DESC LIMIT ' +
                MAX_LOGS
        );
        if (logs.isEmpty()) {
            trace.message = 'No save was logged yet. Save the record, then click Show what happened.';
            return trace;
        }

        // 1. The record's newest save, when the user made it after recording started: one save can
        //    write several logs (before-save, after-save, ...), so every log around it is combined.
        Map<String, FlowProofDebugLogParser.ParsedLog> parsedById = new Map<String, FlowProofDebugLogParser.ParsedLog>();
        FlowProofDebugLogParser.ParsedLog saveLog = new FlowProofDebugLogParser.ParsedLog();
        Map<String, Object> sourceLog;
        Datetime modifiedAt = (Datetime) record.get('LastModifiedDate');
        Boolean savedByUserSinceStart =
            (Id) record.get('LastModifiedById') == UserInfo.getUserId() &&
            modifiedAt != null &&
            modifiedAt >= session.startedAt.addSeconds(-START_SLACK_SECONDS);
        if (savedByUserSinceStart) {
            for (Map<String, Object> log : logs) {
                if (isAroundSave(log, modifiedAt) && !isTooLong(log)) {
                    saveLog.addLog(parsedLog(log, parsedById));
                    sourceLog = sourceLog ?? log;
                }
            }
        }
        if (saveLog.mentionsRecord(session.recordId)) {
            trace.matchedBy = 'RECORD_ID';
            trace.savedAt = modifiedAt;
        } else if (sourceLog != null && saveLog.flowObjects.contains(objectName.toLowerCase())) {
            trace.matchedBy = 'SAVE_TIME';
            trace.savedAt = modifiedAt;
        } else {
            // 2. Otherwise the newest logged save in which a Flow ran for the record.
            sourceLog = null;
            for (Map<String, Object> log : logs) {
                if (isTooLong(log)) {
                    continue;
                }
                FlowProofDebugLogParser.ParsedLog parsed = parsedLog(log, parsedById);
                if (parsed.mentionsRecord(session.recordId)) {
                    saveLog = parsed;
                    sourceLog = log;
                    trace.matchedBy = 'RECORD_ID';
                    trace.savedAt = parseDatetime(log.get('StartTime'));
                    break;
                }
            }
        }
        if (trace.matchedBy == null) {
            trace.message =
                'FlowProof found your recent activity, but not a save of this record. ' +
                'Save this record (change any field, then Save) and try again.';
            return trace;
        }

        trace.logFound = true;
        trace.source = sourceOf((String) sourceLog.get('Operation'), (String) sourceLog.get('Request'));
        Set<String> ranVersions = new Set<String>();
        for (FlowProofDebugLogParser.Interview interview : saveLog.interviewsFor(session.recordId)) {
            trace.ran.add(new FlowProofSaveTrace.FlowRun(interview));
            if (String.isNotBlank(interview.versionId)) {
                ranVersions.add(interview.versionId.left(15));
            }
        }
        for (FlowProofFlowSummary flow : catalog.listRecordTriggeredFlows(objectName)) {
            if (
                flow.isActive == true &&
                String.isNotBlank(flow.activeVersionId) &&
                !ranVersions.contains(flow.activeVersionId.left(15))
            ) {
                trace.notStarted.add(flow.label);
            }
        }
        trace.validationFailures.addAll(saveLog.validationFailures);
        trace.validationFailures.addAll(saveLog.validationMessages);
        trace.loggingStopped = stopQuietly(session);
        return trace;
    }

    /**
     * Switches FlowProof's logging off: deletes the trace flag FlowProof created, or gives the
     * user's own trace flag its previous debug level back.
     * @param session the session from start
     * @throws FlowProofException when the trace flag cannot be changed
     */
    public void stop(FlowProofSaveTraceSession session) {
        if (session == null || String.isBlank(session.traceFlagId)) {
            return;
        }
        Id traceFlagId = idWithPrefix(session.traceFlagId, TRACE_FLAG_PREFIX);
        if (session.createdTraceFlag == true) {
            tooling.deleteRecord('TraceFlag', traceFlagId);
        } else if (String.isNotBlank(session.previousDebugLevelId)) {
            tooling.updateRecord(
                'TraceFlag',
                traceFlagId,
                new Map<String, Object>{
                    'DebugLevelId' => idWithPrefix(session.previousDebugLevelId, DEBUG_LEVEL_PREFIX)
                }
            );
        }
    }

    private Boolean stopQuietly(FlowProofSaveTraceSession session) {
        try {
            stop(session);
            return true;
        } catch (FlowProofException e) {
            // Logging switches itself off when the trace flag expires.
            return false;
        }
    }

    private String ensureDebugLevel() {
        List<Map<String, Object>> levels = tooling.query(
            'SELECT Id FROM DebugLevel WHERE DeveloperName = \'' + DEBUG_LEVEL_NAME + '\' LIMIT 1'
        );
        if (!levels.isEmpty()) {
            return (String) levels[0].get('Id');
        }
        return tooling.create(
            'DebugLevel',
            new Map<String, Object>{
                'DeveloperName' => DEBUG_LEVEL_NAME,
                'MasterLabel' => 'FlowProof Trace',
                'Workflow' => 'FINER',
                'Validation' => 'INFO',
                'Database' => 'INFO',
                'ApexCode' => 'NONE',
                'ApexProfiling' => 'NONE',
                'Callout' => 'NONE',
                'System' => 'NONE',
                'Visualforce' => 'NONE',
                'Nba' => 'NONE',
                'Wave' => 'NONE'
            }
        );
    }

    /** True when the log started within a few seconds of the record's save. */
    private static Boolean isAroundSave(Map<String, Object> log, Datetime modifiedAt) {
        Datetime loggedAt = parseDatetime(log.get('StartTime'));
        if (loggedAt == null) {
            return false;
        }
        Long offset = loggedAt.getTime() - modifiedAt.getTime();
        return offset >= -SAVE_WINDOW_BEFORE_MS && offset <= SAVE_WINDOW_AFTER_MS;
    }

    private static Boolean isTooLong(Map<String, Object> log) {
        return toInteger(log.get('LogLength')) > MAX_LOG_LENGTH;
    }

    /** Reads and parses each log once. */
    private FlowProofDebugLogParser.ParsedLog parsedLog(
        Map<String, Object> log,
        Map<String, FlowProofDebugLogParser.ParsedLog> parsedById
    ) {
        String logId = (String) log.get('Id');
        if (!parsedById.containsKey(logId)) {
            parsedById.put(logId, new FlowProofDebugLogParser().parse(tooling.getLogBody(Id.valueOf(logId))));
        }
        return parsedById.get(logId);
    }

    private static SObject readRecord(String objectName, Id recordId) {
        List<SObject> rows = Database.queryWithBinds(
            'SELECT Id, LastModifiedDate, LastModifiedById FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1',
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.USER_MODE
        );
        if (rows.isEmpty()) {
            throw new FlowProofException('The record was not found, or you do not have access to it.');
        }
        return rows[0];
    }

    private static String objectNameOf(Id recordId) {
        return recordId.getSObjectType().getDescribe().getName();
    }

    private static String sourceOf(String operation, String request) {
        String value = (operation ?? '').toLowerCase();
        if (value.contains('/aura')) {
            return 'Lightning page';
        }
        if (value.contains('/services/data') || request == 'Api') {
            return 'API';
        }
        if (value.contains('execute_anonymous')) {
            return 'Anonymous Apex';
        }
        return String.isBlank(operation) ? 'Unknown' : operation;
    }

    private static Id idWithPrefix(String value, String prefix) {
        if (String.isBlank(value) || !value.startsWith(prefix)) {
            throw new IllegalArgumentException('The recording session is not valid. Start a new test save.');
        }
        return Id.valueOf(value);
    }

    private static String soqlDatetime(Datetime value) {
        return value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static Datetime parseDatetime(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + String.valueOf(value) + '"', Datetime.class);
        } catch (JSONException e) {
            return null;
        }
    }

    private static Integer toInteger(Object value) {
        return value == null ? 0 : Integer.valueOf(String.valueOf(value));
    }
}
