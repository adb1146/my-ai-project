public with sharing class LeadDataLoaderController {
  public class FieldInfo {
    @AuraEnabled
    public String header;
    @AuraEnabled
    public String fieldApi;
    @AuraEnabled
    public Integer confidence;
    public FieldInfo(String h, String f, Integer c) {
      header = h;
      fieldApi = f;
      confidence = c;
    }
  }

  public class ImportResult {
    @AuraEnabled
    public Integer success;
    @AuraEnabled
    public Integer errors;
    public ImportResult(Integer s, Integer e) {
      success = s;
      errors = e;
    }
  }

  public class LeadFieldInfo {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public Boolean required;
  }

  public class ProcessResult {
    @AuraEnabled
    public List<SuccessResult> successes;
    @AuraEnabled
    public List<ErrorResult> errors;
  }

  public class SuccessResult {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public Integer index;
  }

  public class ErrorResult {
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer index;
  }
  /**
   * @description Parses CSV data into a list of field mappings
   * @param csvData The CSV data as a string
   * @return List<Map<String, String>> List of maps representing each row
   */
  @AuraEnabled(cacheable=false)
  public static List<Map<String, String>> parseCsvData(String csvData) {
    List<Map<String, String>> result = new List<Map<String, String>>();

    if (String.isBlank(csvData)) {
      return result;
    }

    try {
      // Split into lines and handle both CRLF and LF line endings
      List<String> lines = csvData.split('\r?\n');

      if (lines.isEmpty()) {
        return result;
      }

      // Get headers from first line
      List<String> headers = parseCsvLine(lines[0]);

      // Process data rows
      for (Integer i = 1; i < lines.size(); i++) {
        if (String.isBlank(lines[i]))
          continue;

        List<String> values = parseCsvLine(lines[i]);
        Map<String, String> row = new Map<String, String>();

        // Map values to headers
        for (Integer j = 0; j < Math.min(headers.size(), values.size()); j++) {
          row.put(headers[j], values[j]);
        }

        result.add(row);
      }
    } catch (Exception e) {
      throw new AuraHandledException('Error parsing CSV: ' + e.getMessage());
    }

    return result;
  }

  /**
   * @description Parses a single CSV line, handling quoted values
   * @param line The CSV line to parse
   * @return List<String> List of parsed values
   */
  private static List<String> parseCsvLine(String line) {
    List<String> values = new List<String>();
    String currentValue = '';
    Boolean inQuotes = false;

    for (Integer i = 0; i < line.length(); i++) {
      String ch = line.substring(i, i + 1);

      if (ch == '"') {
        // Handle escaped quotes ("")
        if (i < line.length() - 1 && line.substring(i + 1, i + 2) == '"') {
          currentValue += '"';
          i++; // Skip next quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        values.add(currentValue);
        currentValue = '';
      } else {
        currentValue += ch;
      }
    }

    // Add the last value
    values.add(currentValue);

    return values;
  }

  /**
   * @description Retrieves the content of a CSV file from a ContentDocument
   * @param contentDocId The ID of the ContentDocument
   * @return String The file contents as a string
   */
  @AuraEnabled(cacheable=false)
  public static String getCsvFileContents(Id contentDocId) {
    try {
      if (contentDocId == null) {
        // In Salesforce, the message in AuraHandledException is not passed to the client for security reasons
        // But we need to make it testable, so we'll set a custom message that our tests can assert on
        AuraHandledException e = new AuraHandledException('ID is required');
        e.setMessage('ID is required');
        throw e;
      }

      // Query the ContentVersion to get the file content
      List<ContentVersion> versions = [
        SELECT VersionData
        FROM ContentVersion
        WHERE ContentDocumentId = :contentDocId AND IsLatest = TRUE
        LIMIT 1
      ];

      if (versions.isEmpty()) {
        throw new AuraHandledException('File not found');
      }

      // Convert the Blob to a String
      return versions[0].VersionData.toString();
    } catch (Exception e) {
      throw new AuraHandledException('Error reading file: ' + e.getMessage());
    }
  }

  /**
   * @description Retrieves available Lead fields with their metadata
   * @return List<LeadFieldInfo> List of Lead field information
   */
  @AuraEnabled(cacheable=true)
  public static List<LeadFieldInfo> getLeadFields() {
    try {
      List<LeadFieldInfo> fields = new List<LeadFieldInfo>();
      Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Lead.fields.getMap();

      for (String fieldName : fieldMap.keySet()) {
        Schema.SObjectField field = fieldMap.get(fieldName);
        Schema.DescribeFieldResult describe = field.getDescribe();

        // Skip fields that cannot be created/updated
        if (!describe.isCreateable())
          continue;

        LeadFieldInfo fieldInfo = new LeadFieldInfo();
        fieldInfo.apiName = describe.getName();
        fieldInfo.label = describe.getLabel();
        fieldInfo.type = String.valueOf(describe.getType());
        fieldInfo.required =
          !describe.isNillable() && !describe.isDefaultedOnCreate();

        fields.add(fieldInfo);
      }

      return fields;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving Lead fields: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Returns a sample CSV template for Lead import
   * @return String The sample CSV template content
   */
  @AuraEnabled(cacheable=true)
  public static String getSampleTemplate() {
    // Headers for common Lead fields
    List<String> headers = new List<String>{
      'FirstName',
      'LastName',
      'Company',
      'Title',
      'Phone',
      'Email',
      'Street',
      'City',
      'State',
      'PostalCode',
      'Country',
      'Industry',
      'Rating',
      'LeadSource',
      'Status'
    };

    // Sample data rows
    List<List<String>> rows = new List<List<String>>{
      new List<String>{
        'John',
        'Doe',
        'Acme Inc',
        'CEO',
        '555-123-4567',
        'john.doe@example.com',
        '123 Main St',
        'San Francisco',
        'CA',
        '94105',
        'USA',
        'Technology',
        'Hot',
        'Web',
        'Open - Not Contacted'
      },
      new List<String>{
        'Jane',
        'Smith',
        'Global Corp',
        'CTO',
        '555-987-6543',
        'jane.smith@example.com',
        '456 Market St',
        'New York',
        'NY',
        '10001',
        'USA',
        'Finance',
        'Warm',
        'Phone Inquiry',
        'Working - Contacted'
      }
    };

    // Build CSV string
    String csv = String.join(headers, ',') + '\n';
    for (List<String> row : rows) {
      csv += String.join(row, ',') + '\n';
    }

    return csv;
  }

  /**
   * @description Processes Lead data from CSV import
   * @param leadsData JSON string containing Lead records
   * @return ProcessResult Results of the import process
   */
  @AuraEnabled(cacheable=false)
  public static ProcessResult processLeadData(String leadsData) {
    ProcessResult result = new ProcessResult();
    result.successes = new List<SuccessResult>();
    result.errors = new List<ErrorResult>();

    if (String.isBlank(leadsData)) {
      // Create exception with proper message for test assertions
      AuraHandledException e = new AuraHandledException('No data provided');
      e.setMessage('No data provided');
      throw e;
    }

    try {
      // Deserialize the lead data
      List<Object> parsedData;
      try {
        parsedData = (List<Object>) JSON.deserializeUntyped(leadsData);
      } catch (JSONException e) {
        // Re-throw as AuraHandledException for consistent error handling
        AuraHandledException auraEx = new AuraHandledException(
          'Invalid JSON format'
        );
        auraEx.setMessage('Invalid JSON format');
        throw auraEx;
      }

      List<Map<String, Object>> records = new List<Map<String, Object>>();
      for (Object obj : parsedData) {
        if (obj instanceof Map<String, Object>) {
          records.add((Map<String, Object>) obj);
        }
      }

      List<Lead> leadsToInsert = new List<Lead>();

      // Process each record
      for (Integer i = 0; i < records.size(); i++) {
        try {
          Map<String, Object> recordMap = records[i];
          Lead newLead = new Lead();

          // Apply field values
          for (String fieldName : recordMap.keySet()) {
            if (recordMap.get(fieldName) != null) {
              try {
                newLead.put(fieldName, recordMap.get(fieldName));
              } catch (Exception e) {
                // Skip fields that cannot be set
                System.debug(
                  'Cannot set field ' + fieldName + ': ' + e.getMessage()
                );
              }
            }
          }

          // Validate required fields
          if (String.isBlank(newLead.LastName)) {
            throw new AuraHandledException('Last Name is required');
          }
          if (String.isBlank(newLead.Company)) {
            throw new AuraHandledException('Company is required');
          }

          leadsToInsert.add(newLead);
        } catch (Exception e) {
          // Record individual record errors
          ErrorResult err = new ErrorResult();
          err.index = i;
          err.message = e.getMessage();
          result.errors.add(err);
        }
      }

      // Insert records with partial success allowed
      if (!leadsToInsert.isEmpty()) {
        List<Database.SaveResult> saveResults = Database.insert(
          leadsToInsert,
          false
        );

        for (Integer i = 0; i < saveResults.size(); i++) {
          Database.SaveResult sr = saveResults[i];
          if (sr.isSuccess()) {
            SuccessResult success = new SuccessResult();
            success.recordId = sr.getId();
            success.index = i;
            result.successes.add(success);
          } else {
            ErrorResult err = new ErrorResult();
            err.index = i;
            err.message = sr.getErrors()[0].getMessage();
            result.errors.add(err);
          }
        }
      }

      return result;
    } catch (JSONException e) {
      // This covers the invalid JSON test case
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error processing lead data: ' + e.getMessage()
      );
    }
  }
}
