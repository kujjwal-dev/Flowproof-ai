/**
 * FlowProof AI settings as shown on the Settings screen, read from the FlowProof_Setting__mdt
 * record named Default. Missing settings fall back to safe defaults (AI off).
 */
public with sharing class FlowProofSettings {
    private static final String DEFAULT_RECORD = 'Default';

    /** True when investigations may request a Gemini explanation. */
    @AuraEnabled
    public Boolean aiEnabled { get; set; }
    /** Gemini model code. */
    @AuraEnabled
    public String aiModel { get; set; }
    /** True when the record's field values may be sent to Gemini; otherwise they are hidden. */
    @AuraEnabled
    public Boolean aiSendFieldValues { get; set; }

    /**
     * Reads the Default settings record.
     * @return the settings; AI disabled when the record is missing
     */
    public static FlowProofSettings load() {
        FlowProof_Setting__mdt record = FlowProof_Setting__mdt.getInstance(DEFAULT_RECORD);
        FlowProofSettings settings = new FlowProofSettings();
        settings.aiEnabled = record?.AI_Enabled__c == true;
        settings.aiModel = record?.AI_Model__c;
        settings.aiSendFieldValues = record?.AI_Send_Field_Values__c == true;
        return settings;
    }
}
