/**
 * Test class for ContactTrigger
 */
@isTest
private class ContactTriggerTest {
  @isTest
  static void testContactLastNameDefault() {
    // Create a test contact with blank LastName
    Contact testContact = new Contact();
    testContact.FirstName = 'Test';
    testContact.Email = 'test@example.com';

    // Insert the contact which should trigger the trigger
    Test.startTest();
    insert testContact;
    Test.stopTest();

    // Query the contact to verify the trigger worked
    Contact insertedContact = [
      SELECT Id, LastName
      FROM Contact
      WHERE Email = 'test@example.com'
      LIMIT 1
    ];

    // Assert that the LastName was set to 'Default' by the trigger
    System.assertEquals(
      'Default',
      insertedContact.LastName,
      'LastName should be set to Default'
    );
  }

  @isTest
  static void testContactWithLastName() {
    // Create a test contact with a specified LastName
    Contact testContact = new Contact();
    testContact.FirstName = 'Test';
    testContact.LastName = 'Specified';
    testContact.Email = 'test2@example.com';

    // Insert the contact which should trigger the trigger
    Test.startTest();
    insert testContact;
    Test.stopTest();

    // Query the contact to verify the trigger worked
    Contact insertedContact = [
      SELECT Id, LastName
      FROM Contact
      WHERE Email = 'test2@example.com'
      LIMIT 1
    ];

    // Assert that the LastName remains unchanged
    System.assertEquals(
      'Specified',
      insertedContact.LastName,
      'LastName should remain as specified'
    );
  }
}
