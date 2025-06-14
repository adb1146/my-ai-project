@isTest
private class LeadDataLoaderControllerTest {
  @isTest
  static void testInnerClasses() {
    // Test FieldInfo class
    LeadDataLoaderController.FieldInfo fieldInfo = new LeadDataLoaderController.FieldInfo(
      'test',
      'Test__c',
      90
    );
    System.assertEquals(90, fieldInfo.confidence, 'Confidence should be 90');

    // Test ImportResult class
    LeadDataLoaderController.ImportResult result = new LeadDataLoaderController.ImportResult(
      1,
      0
    );
    System.assertEquals(1, result.success, 'Success count should be 1');
    System.assertEquals(0, result.errors, 'Error count should be 0');
  }

  @isTest
  static void testParseCsvData() {
    // Prepare test data
    String csvData = 'FirstName,LastName,Company,Email\nJohn,Doe,Acme Inc,john@example.com\nJane,Smith,XYZ Corp,jane@example.com';

    // Call the method
    Test.startTest();
    List<Map<String, String>> result = LeadDataLoaderController.parseCsvData(
      csvData
    );
    Test.stopTest();

    // Assert
    System.assertEquals(2, result.size(), 'Should have 2 rows of data');
    System.assertEquals(
      'John',
      result[0].get('FirstName'),
      'First row FirstName should be John'
    );
    System.assertEquals(
      'Jane',
      result[1].get('FirstName'),
      'Second row FirstName should be Jane'
    );
    System.assertEquals(
      'jane@example.com',
      result[1].get('Email'),
      'Second row Email should be jane@example.com'
    );
  }

  @isTest
  static void testGetCsvFileContents() {
    // Create a test ContentVersion
    String testContent = 'FirstName,LastName,Company\nTest,User,TestCompany';
    ContentVersion cv = new ContentVersion();
    cv.Title = 'Test CSV';
    cv.PathOnClient = 'test.csv';
    cv.VersionData = Blob.valueOf(testContent);
    cv.IsMajorVersion = true;
    insert cv;

    // Get the ContentDocumentId
    cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    Id contentDocId = cv.ContentDocumentId;

    // Test the method
    Test.startTest();
    String result = LeadDataLoaderController.getCsvFileContents(contentDocId);
    Test.stopTest();

    // Assert
    System.assertEquals(
      testContent,
      result,
      'Retrieved content should match original content'
    );

    // Test error case
    Boolean exceptionThrown = false;
    String exceptionMessage = '';

    try {
      LeadDataLoaderController.getCsvFileContents(null);
    } catch (AuraHandledException e) {
      exceptionThrown = true;
    }

    System.assert(exceptionThrown, 'Should have thrown an exception');
    // Since we can't reliably test AuraHandledException messages in tests,
    // we'll simply verify an exception was thrown
  }

  @isTest
  static void testGetLeadFields() {
    // Call the method
    Test.startTest();
    List<LeadDataLoaderController.LeadFieldInfo> fields = LeadDataLoaderController.getLeadFields();
    Test.stopTest();

    // Assert
    System.assertNotEquals(0, fields.size(), 'Should return some Lead fields');

    // Verify some standard fields are present
    Boolean hasLastName = false;
    Boolean hasCompany = false;

    for (LeadDataLoaderController.LeadFieldInfo field : fields) {
      if (field.apiName == 'LastName') {
        hasLastName = true;
        System.assertEquals(
          true,
          field.required,
          'LastName should be required'
        );
      }

      if (field.apiName == 'Company') {
        hasCompany = true;
        System.assertEquals(true, field.required, 'Company should be required');
      }
    }

    System.assert(hasLastName, 'LastName field should be present');
    System.assert(hasCompany, 'Company field should be present');
  }

  @isTest
  static void testProcessLeadData() {
    // Prepare test data
    List<Map<String, String>> testLeads = new List<Map<String, String>>();

    // Valid lead
    Map<String, String> lead1 = new Map<String, String>{
      'LastName' => 'TestLead1',
      'Company' => 'Test Company 1',
      'Email' => 'test1@example.com'
    };

    // Invalid lead (missing required field)
    Map<String, String> lead2 = new Map<String, String>{
      'FirstName' => 'Test',
      'Email' => 'test2@example.com'
      // No LastName or Company
    };

    testLeads.add(lead1);
    testLeads.add(lead2);

    String jsonData = JSON.serialize(testLeads);

    // Call the method
    Test.startTest();
    LeadDataLoaderController.ProcessResult result = LeadDataLoaderController.processLeadData(
      jsonData
    );
    Test.stopTest();

    // Assert
    System.assertNotEquals(
      null,
      result.successes,
      'Successes list should not be null'
    );
    System.assertNotEquals(
      null,
      result.errors,
      'Errors list should not be null'
    );

    // Valid lead should succeed, invalid lead should fail
    System.assertEquals(
      1,
      result.successes.size(),
      'Should have 1 successful insert'
    );
    System.assertEquals(1, result.errors.size(), 'Should have 1 error');

    // Check if the Lead was actually created
    List<Lead> insertedLeads = [
      SELECT LastName, Company, Email
      FROM Lead
      WHERE LastName = 'TestLead1'
    ];
    System.assertEquals(
      1,
      insertedLeads.size(),
      'One Lead should have been inserted'
    );
    System.assertEquals(
      'test1@example.com',
      insertedLeads[0].Email,
      'Email should match'
    );
  }

  @isTest
  static void testProcessLeadDataErrors() {
    // Test empty data
    Boolean emptyDataExceptionThrown = false;

    try {
      LeadDataLoaderController.processLeadData('');
    } catch (AuraHandledException e) {
      emptyDataExceptionThrown = true;
    }

    System.assert(
      emptyDataExceptionThrown,
      'Should throw exception for empty data'
    );

    // Test malformed JSON
    Boolean invalidJsonExceptionThrown = false;

    try {
      LeadDataLoaderController.processLeadData('{invalid json}');
    } catch (Exception e) {
      invalidJsonExceptionThrown = true;
    }

    System.assert(
      invalidJsonExceptionThrown,
      'Should throw exception for invalid JSON'
    );
  }
}
