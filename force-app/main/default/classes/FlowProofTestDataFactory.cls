/**
 * Test data for FlowProof tests: synthetic records and low-privilege users with exactly the
 * object and field access a test needs. Records are inserted in system mode so a test controls
 * access through the user it runs as, not through the data setup.
 */
@IsTest
public class FlowProofTestDataFactory {
    private static final String MINIMUM_ACCESS_PROFILE = 'Minimum Access - Salesforce';
    private static final String STANDARD_USER_PROFILE = 'Standard User';

    /**
     * Builds (and optionally inserts) a synthetic Opportunity.
     * @param name record name
     * @param stageName StageName picklist value
     * @param amount Amount
     * @param doInsert true to insert in system mode
     * @return the Opportunity
     */
    public static Opportunity createOpportunity(String name, String stageName, Decimal amount, Boolean doInsert) {
        Opportunity opportunity = new Opportunity(
            Name = name,
            StageName = stageName,
            Amount = amount,
            CloseDate = Date.newInstance(2026, 10, 15)
        );
        if (doInsert) {
            Database.insert(opportunity, AccessLevel.SYSTEM_MODE);
        }
        return opportunity;
    }

    /**
     * Inserts a user on the Minimum Access - Salesforce profile (no object access of its own).
     * Call inside System.runAs to keep setup DML separate from record DML.
     * @return the user
     */
    public static User createMinimumAccessUser() {
        return insertUser(MINIMUM_ACCESS_PROFILE);
    }

    /**
     * Inserts a Standard User holding the FlowProof_User permission set, as a real FlowProof user
     * would. Proves that the shipped permission set grants what FlowProof needs.
     * Call inside System.runAs to keep setup DML separate from record DML.
     * @return the user
     */
    public static User createFlowProofUser() {
        User user = insertUser(STANDARD_USER_PROFILE);
        PermissionSet flowProofUser = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'FlowProof_User'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Database.insert(
            new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = flowProofUser.Id),
            AccessLevel.SYSTEM_MODE
        );
        return user;
    }

    private static User insertUser(String profileName) {
        Profile profile = [SELECT Id FROM Profile WHERE Name = :profileName WITH SYSTEM_MODE LIMIT 1];
        String unique = String.valueOf(Math.abs(Crypto.getRandomLong()));
        User user = new User(
            Alias = 'fptest',
            Email = 'flowproof.test@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'FlowProof Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'flowproof.test.' + unique + '@example.com'
        );
        Database.insert(user, AccessLevel.SYSTEM_MODE);
        return user;
    }

    /**
     * Grants a user read and create access to Opportunity and read access to the listed fields only.
     * Call inside System.runAs to keep setup DML separate from record DML.
     * @param userId user to grant access to
     * @param readableFields Opportunity field API names the user may read
     */
    public static void grantOpportunityAccess(Id userId, List<String> readableFields) {
        PermissionSet permissionSet = new PermissionSet(
            Name = 'FlowProof_Test_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Label = 'FlowProof Test Opportunity Access'
        );
        Database.insert(permissionSet, AccessLevel.SYSTEM_MODE);
        Database.insert(
            new ObjectPermissions(
                ParentId = permissionSet.Id,
                SobjectType = 'Opportunity',
                PermissionsRead = true,
                PermissionsCreate = true
            ),
            AccessLevel.SYSTEM_MODE
        );
        List<FieldPermissions> fieldPermissions = new List<FieldPermissions>();
        for (String field : readableFields) {
            fieldPermissions.add(
                new FieldPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = 'Opportunity',
                    Field = 'Opportunity.' + field,
                    PermissionsRead = true
                )
            );
        }
        Database.insert(fieldPermissions, AccessLevel.SYSTEM_MODE);
        Database.insert(
            new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSet.Id),
            AccessLevel.SYSTEM_MODE
        );
    }
}
