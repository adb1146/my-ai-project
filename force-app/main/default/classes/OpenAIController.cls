/**
 * @description Controller for OpenAI chatbot integration
 * @author Cascade AI
 */
public with sharing class OpenAIController {
  /**
   * @description Send a message to OpenAI and get a response
   * @param message The current user message
   * @param objectType The type of object to extract data for (Lead, Contact, etc.)
   * @param previousMessages JSON string of previous messages for context
   * @return Wrapper with AI response and extracted data
   */
  @AuraEnabled
  public static ResponseWrapper sendMessageToOpenAI(
    String message,
    String objectType,
    String previousMessages
  ) {
    try {
      // Get the OpenAI API key from custom setting
      OpenAI_Settings__c settings = OpenAI_Settings__c.getOrgDefaults();
      System.debug('OpenAI Settings: ' + settings);

      // Check if settings exist
      if (settings == null) {
        System.debug('ERROR: OpenAI settings not found');
        throw new AuraHandledException(
          'OpenAI settings not found. Please configure the OpenAI_Settings__c custom setting.'
        );
      }

      String apiKey = settings.API_Key__c;
      System.debug(
        'API Key length: ' + (String.isBlank(apiKey) ? 0 : apiKey.length())
      );

      if (String.isBlank(apiKey)) {
        System.debug('ERROR: OpenAI API key not configured');
        throw new AuraHandledException(
          'OpenAI API key not configured. Please set up the OpenAI_Settings__c custom setting.'
        );
      }

      // Parse previous messages if provided
      List<Map<String, String>> messageHistory = new List<Map<String, String>>();
      if (String.isNotBlank(previousMessages)) {
        messageHistory = (List<Map<String, String>>) JSON.deserializeUntyped(
          previousMessages
        );
      }

      // Prepare the OpenAI API request
      HttpRequest req = new HttpRequest();
      req.setEndpoint('https://api.openai.com/v1/chat/completions');
      req.setMethod('POST');
      req.setHeader('Authorization', 'Bearer ' + apiKey);
      req.setHeader('Content-Type', 'application/json');

      // Build the messages array including system message for object extraction
      List<Map<String, String>> messages = new List<Map<String, String>>();

      // Add system message with instructions
      Map<String, String> systemMessage = new Map<String, String>();
      systemMessage.put('role', 'system');
      systemMessage.put(
        'content',
        'You are an AI assistant helping to extract information for Salesforce ' +
          objectType +
          ' records. When the user provides information that could be used to create a ' +
          objectType +
          ' record, extract the relevant fields and format them as JSON. For other queries, ' +
          'respond normally as a helpful assistant.'
      );
      messages.add(systemMessage);

      // Add message history for context
      messages.addAll(messageHistory);

      // Add the current message
      Map<String, String> userMessage = new Map<String, String>();
      userMessage.put('role', 'user');
      userMessage.put('content', message);
      messages.add(userMessage);

      // Add instruction to extract object data
      Map<String, String> extractionMessage = new Map<String, String>();
      extractionMessage.put('role', 'system');
      extractionMessage.put(
        'content',
        'If the conversation contains information that could be used to create a ' +
          objectType +
          ' record, extract that information into a JSON object with field names matching ' +
          'Salesforce ' +
          objectType +
          ' field API names. If there\'s no relevant information, return null for extractedData.'
      );
      messages.add(extractionMessage);

      // Create the request body
      Map<String, Object> requestBody = new Map<String, Object>();
      requestBody.put('model', 'gpt-4o'); // Use the more capable GPT-4o model
      requestBody.put('messages', messages);
      requestBody.put('temperature', 0.3); // Lower temperature for more factual/consistent responses
      requestBody.put('max_tokens', 1000);

      req.setBody(JSON.serialize(requestBody));

      // Debug the request information
      System.debug('OpenAI Request URL: ' + req.getEndpoint());
      System.debug('OpenAI Request Body Length: ' + req.getBody().length());

      // Send the request to OpenAI
      Http http = new Http();
      HttpResponse res;
      try {
        res = http.send(req);
        System.debug(
          'OpenAI Response Status: ' +
            res.getStatusCode() +
            ' ' +
            res.getStatus()
        );
        System.debug('OpenAI Response Size: ' + res.getBodyAsBlob().size());
      } catch (Exception e) {
        System.debug('ERROR: HTTP request failed: ' + e.getMessage());
        throw new AuraHandledException(
          'Failed to connect to OpenAI API: ' + e.getMessage()
        );
      }

      // Process the response
      if (res.getStatusCode() == 200) {
        // Try to parse the response body
        Map<String, Object> responseBody;
        try {
          System.debug('Beginning JSON parsing');
          responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
          );
          System.debug('Successfully parsed JSON response');
        } catch (Exception e) {
          System.debug(
            'ERROR: Failed to parse OpenAI response: ' + e.getMessage()
          );
          System.debug(
            'Response body sample: ' +
            res.getBody().substring(0, Math.min(300, res.getBody().length()))
          );
          throw new AuraHandledException(
            'Failed to parse OpenAI response: ' + e.getMessage()
          );
        }

        // Extract content from response
        String content;
        try {
          List<Object> choices = (List<Object>) responseBody.get('choices');
          if (choices == null || choices.isEmpty()) {
            throw new AuraHandledException('OpenAI response missing choices');
          }

          Map<String, Object> choice = (Map<String, Object>) choices[0];
          Map<String, Object> responseMessage = (Map<String, Object>) choice.get(
            'message'
          );
          content = (String) responseMessage.get('content');
          System.debug('Successfully extracted message content');

          if (content == null) {
            throw new AuraHandledException('OpenAI response missing content');
          }
        } catch (Exception e) {
          System.debug(
            'ERROR: Failed to extract content from response: ' + e.getMessage()
          );
          throw new AuraHandledException(
            'Failed to extract content: ' + e.getMessage()
          );
        }

        // Extract JSON data from the response if present
        Map<String, Object> extractedData = null;
        Pattern jsonPattern = Pattern.compile('\\{[^{}]*\\}');
        Matcher matcher = jsonPattern.matcher(content);

        if (matcher.find()) {
          String jsonStr = matcher.group(0);
          try {
            extractedData = (Map<String, Object>) JSON.deserializeUntyped(
              jsonStr
            );
            // Remove JSON from content to avoid displaying it to the user
            content = content.replace(jsonStr, '').trim();
            content = content.replace('```json', '').replace('```', '').trim();
          } catch (Exception e) {
            // If JSON parsing fails, continue without extracted data
            System.debug('Error parsing JSON: ' + e.getMessage());
          }
        }

        // Create and return the response wrapper
        ResponseWrapper wrapper = new ResponseWrapper();
        wrapper.message = content;
        wrapper.extractedData = extractedData;
        return wrapper;
      } else {
        throw new AuraHandledException(
          'OpenAI API Error: ' +
            res.getStatusCode() +
            ' ' +
            res.getStatus() +
            ' - ' +
            res.getBody()
        );
      }
    } catch (Exception e) {
      System.debug(
        'OpenAI Error: ' + e.getMessage() + '\n' + e.getStackTraceString()
      );
      throw new AuraHandledException('Error: ' + e.getMessage());
    }
  }

  /**
   * @description Create a record from extracted data
   * @param objectType The type of object to create
   * @param recordData JSON string of record data
   * @return Record ID of the created record
   */
  @AuraEnabled
  public static String createRecord(String objectType, String recordData) {
    try {
      // Deserialize the record data
      Map<String, Object> fieldsMap = (Map<String, Object>) JSON.deserializeUntyped(
        recordData
      );

      // Create the SObject dynamically
      Schema.SObjectType targetType = Schema.getGlobalDescribe()
        .get(objectType);
      if (targetType == null) {
        throw new AuraHandledException('Invalid object type: ' + objectType);
      }

      SObject newRecord = targetType.newSObject();

      // Build a map of field name to SObjectField for validation
      Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe()
        .fields.getMap();

      // Set each field value, skipping invalid fields
      for (String fieldName : fieldsMap.keySet()) {
        // Skip if field doesn't exist
        if (!fieldMap.containsKey(fieldName)) {
          continue;
        }

        Schema.SObjectField field = fieldMap.get(fieldName);
        Schema.DisplayType fieldType = field.getDescribe().getType();

        // Set field based on type
        Object value = fieldsMap.get(fieldName);
        if (value != null) {
          try {
            // Convert strings to appropriate types for certain field types
            if (
              fieldType == Schema.DisplayType.DATE && value instanceof String
            ) {
              try {
                value = Date.valueOf((String) value);
              } catch (Exception e) {
                // Skip if we can't parse the date
                continue;
              }
            } else if (
              fieldType == Schema.DisplayType.DATETIME &&
              value instanceof String
            ) {
              try {
                value = Datetime.valueOf((String) value);
              } catch (Exception e) {
                // Skip if we can't parse the datetime
                continue;
              }
            } else if (
              (fieldType == Schema.DisplayType.CURRENCY ||
              fieldType == Schema.DisplayType.DOUBLE ||
              fieldType == Schema.DisplayType.PERCENT) &&
              value instanceof String
            ) {
              try {
                value = Decimal.valueOf((String) value);
              } catch (Exception e) {
                // Skip if we can't parse the decimal
                continue;
              }
            } else if (
              fieldType == Schema.DisplayType.INTEGER && value instanceof String
            ) {
              try {
                value = Integer.valueOf((String) value);
              } catch (Exception e) {
                // Skip if we can't parse the integer
                continue;
              }
            } else if (
              fieldType == Schema.DisplayType.BOOLEAN && value instanceof String
            ) {
              String boolStr = ((String) value).toLowerCase();
              if (boolStr == 'true' || boolStr == 'yes' || boolStr == '1') {
                value = true;
              } else if (
                boolStr == 'false' ||
                boolStr == 'no' ||
                boolStr == '0'
              ) {
                value = false;
              } else {
                // Skip if we can't parse the boolean
                continue;
              }
            }

            newRecord.put(fieldName, value);
          } catch (Exception e) {
            // If there's an error setting the field, skip it
            System.debug(
              'Error setting field ' + fieldName + ': ' + e.getMessage()
            );
          }
        }
      }

      // Insert the record
      insert newRecord;
      return newRecord.Id;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error creating record: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Response wrapper class
   */
  public class ResponseWrapper {
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Object extractedData;

    public ResponseWrapper() {
      this.message = '';
      this.extractedData = null;
    }
  }
}
