import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";

// Import Apex methods
import getCsvFileContents from "@salesforce/apex/LeadDataLoaderController.getCsvFileContents";
import parseCsvData from "@salesforce/apex/LeadDataLoaderController.parseCsvData";
import getLeadFields from "@salesforce/apex/LeadDataLoaderController.getLeadFields";
import processLeadData from "@salesforce/apex/LeadDataLoaderController.processLeadData";

// Import field mapping service
import { generateFieldMappings } from "c/fieldMappingService";

export default class LeadDataLoader extends NavigationMixin(LightningElement) {
  @api recordId;

  // Track component state
  @track currentStep = "upload";
  @track csvData = [];
  @track csvHeaders = [];
  @track previewData = [];
  @track mappings = {};
  @track leadFields = [];
  @track isProcessing = false;
  @track _testReadyForProcessing = false;

  // API methods for testing
  @api testGetCurrentStep() {
    return this.currentStep;
  }
  @api testGetIsProcessing() {
    if (this._forceIsProcessing === true) return true;
    if (this._forceIsProcessing === false) return false;
    return this.isProcessing;
  }
  @api testGetCsvHeaders() {
    return this.csvHeaders;
  }
  @api testGetLeadFields() {
    return this.leadFields || [];
  }
  @api testGetMappings() {
    return this.mappings;
  }
  @api testGetErrors() {
    return this.errors;
  }
  @api testGetAISuggestedMappings() {
    return this.aiSuggestedMappings || {};
  }
  @api testGetMappingConfidence() {
    return this.mappingConfidence || {};
  }
  @api testGetCsvData() {
    return this.csvData;
  }
  @api testAutoMapFields() {
    return this.autoMapFields();
  }
  @api testAcceptAiMappings() {
    return this.acceptAiMappings();
  }

  @api testSetupData(testData) {
    if (testData) {
      if (testData.csvData) this.csvData = testData.csvData;
      if (testData.csvHeaders) this.csvHeaders = testData.csvHeaders;
      if (testData.leadFields) this.leadFields = testData.leadFields;
      if (testData.mappings) this.mappings = testData.mappings;
      if (testData.currentStep) this.currentStep = testData.currentStep;
      if (testData.previewData) this.previewData = testData.previewData;
    }
  }

  @track leadFieldOptions = [];
  @track uploadedFileId;
  @track fileName;
  @track importProgress = 0;
  @track processedRecords = 0;
  @track totalRecords = 0;
  @track successCount = 0;
  @track errorCount = 0;
  @track errors = [];
  @track aiSuggestedMappings = {};
  @track showMappingSuggestions = false;
  @track mappingConfidence = {};

  acceptedFormats = [".csv"];

  // Computed getters for template
  get isUploadStep() {
    return this.currentStep === "upload";
  }
  get isMappingStep() {
    return this.currentStep === "mapping";
  }
  get isImportStep() {
    return this.currentStep === "import";
  }
  get isResultsStep() {
    return this.currentStep === "results";
  }

  // Getter that formats preview data for the template display
  // This creates a proper format that doesn't require computed property access in the template
  get formattedPreviewData() {
    if (!this.previewData || !this.csvHeaders) {
      return [];
    }

    return this.previewData.map((row, index) => {
      // Create a row object with a unique ID and cell values array
      const formattedRow = {
        uniqueId: row._uniqueId || `row-${index}`,
        cells: this.csvHeaders.map((header) => ({
          header,
          value: row[header] || "",
          key: `${row._uniqueId || index}-${header}`
        }))
      };
      return formattedRow;
    });
  }

  connectedCallback() {
    this.loadLeadFields();
    this.currentStep = "upload";
    this.isProcessing = false;
    this.mappings = {};
  }

  async loadLeadFields() {
    try {
      const data = await getLeadFields();
      this.leadFields = data;
      console.log("Lead fields loaded:", this.leadFields.length);

      // Generate field options for mapping dropdown
      this.leadFieldOptions = data.map((field) => ({
        label: field.label,
        value: field.apiName
      }));
    } catch (error) {
      console.error("Error loading lead fields", error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error loading Lead fields",
          message:
            error.body?.message ||
            "Please refresh the page or contact your administrator.",
          variant: "error"
        })
      );
    }
  }

  // Special method to manually set lead fields for testing
  @api testSetLeadFields(fields) {
    this.leadFields = fields;
  }

  async handleUploadFinished(event) {
    const uploadedFiles = event.detail.files;
    if (uploadedFiles.length === 0) {
      return;
    }

    try {
      // Get file details
      const file = uploadedFiles[0];
      this.uploadedFileId = file.documentId;
      this.fileName = file.name;

      // Show initial upload notification
      this.dispatchEvent(
        new ShowToastEvent({
          title: "File Uploaded",
          message: "Reading file content...",
          variant: "info"
        })
      );

      // Ensure we're using the correct parameter name (contentDocId) as expected by the Apex method
      console.log("Calling getCsvFileContents with ID:", this.uploadedFileId);
      const csvContent = await getCsvFileContents({
        contentDocId: this.uploadedFileId
      }).catch((error) => {
        console.error("Error in getCsvFileContents:", error);
        throw error;
      });

      console.log("CSV content retrieved successfully");
      const parsedData = await parseCsvData({
        csvData: csvContent
      }).catch((error) => {
        console.error("Error in parseCsvData:", error);
        throw error;
      });

      // Handle the parsed data
      this.handleParsedCsvData(parsedData);

      // Show success message
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: "CSV file processed successfully",
          variant: "success"
        })
      );
    } catch (error) {
      console.error("Error processing CSV file:", error);
      let errorMsg = "Unknown error";

      // Try to extract the most useful error message
      if (error.body && error.body.message) {
        errorMsg = error.body.message;
      } else if (error.message) {
        errorMsg = error.message;
      } else if (typeof error === "string") {
        errorMsg = error;
      }

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: "Error processing CSV file: " + errorMsg,
          variant: "error"
        })
      );
    }
  }

  handleParsedCsvData(parsedData) {
    if (!parsedData || !Array.isArray(parsedData)) {
      throw new Error("Invalid CSV data format received");
    }

    if (parsedData.length === 0) {
      throw new Error("The CSV file is empty");
    }

    try {
      console.log("CSV data parsed successfully:", parsedData.length, "rows");

      // Extract headers from the first row's keys
      this.csvHeaders = Object.keys(parsedData[0]);
      if (this.csvHeaders.length === 0) {
        throw new Error("No headers found in CSV file");
      }

      console.log("Extracted headers:", this.csvHeaders);

      // Store the parsed data
      this.csvData = parsedData;

      // Generate preview data (first 5 rows or all if less than 5)
      this.previewData = parsedData.slice(0, 5);

      // Move to mapping step
      this.currentStep = "mapping";

      // Auto-map fields if possible
      this.autoMapFields();
    } catch (error) {
      console.error("Error processing parsed data:", error);
      throw error; // Re-throw to be handled by the caller
    }
  }

  handleFieldMapping(event) {
    const header = event.target.dataset.header;
    const field = event.detail.value;

    // Update mappings using spread operator for immutability
    this.mappings = {
      ...this.mappings,
      [header]: field
    };
  }

  autoMapFields() {
    console.log("Auto-mapping fields using AI service");

    if (!this.csvHeaders || !this.leadFields) {
      console.error("Cannot perform mapping - missing headers or fields");
      return;
    }

    // Use the imported generateFieldMappings from fieldMappingService
    const mappingResult = generateFieldMappings(
      this.csvHeaders,
      this.leadFields,
      this.previewData
    );

    // Store the AI suggested mappings and confidence scores
    this.aiSuggestedMappings = mappingResult.suggestedMappings;
    this.mappingConfidence = mappingResult.confidenceScores;

    // Apply the suggestions to the actual mappings
    this.mappings = { ...mappingResult.suggestedMappings };

    // Show AI mapping suggestions panel
    this.showMappingSuggestions = true;
  }

  acceptAiMappings() {
    console.log("acceptAiMappings called");

    if (
      !this.aiSuggestedMappings ||
      Object.keys(this.aiSuggestedMappings).length === 0
    ) {
      return;
    }

    // Apply the AI suggested mappings
    this.mappings = { ...this.mappings, ...this.aiSuggestedMappings };

    // Close the suggestion panel
    this.showMappingSuggestions = false;

    // Show feedback
    this.dispatchEvent(
      new ShowToastEvent({
        title: "AI Mappings Applied",
        message: `Applied ${Object.keys(this.aiSuggestedMappings).length} field mappings`,
        variant: "success"
      })
    );
  }

  // Method to dismiss mapping suggestions and allow manual mapping
  dismissMappingSuggestions() {
    console.log("dismissMappingSuggestions called");
    // Hide the suggestions panel
    this.showMappingSuggestions = false;

    // Provide visual feedback that the user can now edit mappings manually
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Manual Mapping Mode",
        message:
          "You can now map fields manually using the dropdown menus below.",
        variant: "info"
      })
    );
  }

  validateAndStartImport() {
    console.log("validateAndStartImport called");

    // Validate that required fields are mapped
    const requiredFields = this.leadFields.filter((field) => field.required);
    const requiredFieldApiNames = requiredFields.map((field) => field.apiName);

    // Check if all required fields have mappings
    const mappedFields = Object.values(this.mappings);
    const missingRequiredFields = requiredFieldApiNames.filter(
      (apiName) => !mappedFields.includes(apiName)
    );

    // If required fields are missing, show error
    if (missingRequiredFields.length > 0) {
      const missingFieldLabels = missingRequiredFields
        .map((apiName) => this.getFieldLabelByApiName(apiName))
        .join(", ");

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Required fields not mapped",
          message: `Please map these required fields: ${missingFieldLabels}`,
          variant: "warning"
        })
      );
      return;
    }

    // If validation passes, proceed to import
    this.handleSubmit();
  }

  handleSubmit() {
    // Validate mappings before submission
    const requiredFields = this.leadFields
      .filter((field) => field.required)
      .map((field) => field.apiName);

    // Check if all required fields are mapped
    const mappedFields = Object.values(this.mappings);
    const missingRequiredFields = requiredFields.filter(
      (field) => !mappedFields.includes(field)
    );

    if (missingRequiredFields.length > 0) {
      const missingFieldLabels = missingRequiredFields.map((apiName) => {
        const field = this.leadFields.find((f) => f.apiName === apiName);
        return field ? field.label : apiName;
      });

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Required Fields Missing",
          message: `Please map these required fields: ${missingFieldLabels.join(", ")}`,
          variant: "error"
        })
      );
      return;
    }

    // Prepare data for processing
    this.isProcessing = true;
    this.currentStep = "import";
    this.importProgress = 10;
    this.totalRecords = this.csvData.length;

    // Check if we have data to process
    console.log(
      "CSV Data Length:",
      this.csvData ? this.csvData.length : "undefined"
    );
    console.log("Mappings:", JSON.stringify(this.mappings));

    if (!this.csvData || this.csvData.length === 0) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message:
            "No CSV data available. Please upload a valid CSV file first.",
          variant: "error"
        })
      );
      this.isProcessing = false;
      this.currentStep = "upload"; // Go back to upload step
      return;
    }

    // Transform data for Apex processing
    const processData = {
      mappings: this.mappings,
      records: this.csvData
    };

    // Debug the data we're sending
    console.log("Sending data to Apex:", JSON.stringify(processData));

    // Process the data using Apex
    const jsonData = JSON.stringify(processData);
    console.log(
      "JSON string length:",
      jsonData ? jsonData.length : "undefined"
    );

    // FIXED: Parameter name mismatch - Apex expects 'leadsData' not 'jsonData'
    processLeadData({ leadsData: jsonData })
      .then((result) => {
        console.log("Lead processing completed:", result);
        this.successCount = result.successCount || 0;
        this.errorCount = result.errorCount || 0;
        this.errors = result.errors || [];
        this.importProgress = 100;
        this.processedRecords = this.totalRecords;
        this.currentStep = "results";

        const message =
          `Successfully imported ${this.successCount} leads` +
          (this.errorCount > 0 ? ` with ${this.errorCount} errors` : "");

        this.dispatchEvent(
          new ShowToastEvent({
            title: "Import Complete",
            message: message,
            variant: this.errorCount > 0 ? "warning" : "success"
          })
        );
      })
      .catch((error) => {
        console.error("Error processing leads:", error);
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message: this.reduceErrors(error),
            variant: "error"
          })
        );
        this.importProgress = 0;
        this.currentStep = "mapping"; // Go back to mapping step
      })
      .finally(() => {
        this.isProcessing = false;
      });
  }

  // Helper methods
  // Helper getter for field mapping display
  // This creates a proper format that doesn't require computed property access in the template
  get formattedMappings() {
    if (!this.csvHeaders || !this.mappings) {
      return [];
    }

    return this.csvHeaders.map((header) => ({
      header,
      fieldApiName: this.mappings[header] || "",
      fieldLabel: this.getFieldLabelByApiName(this.mappings[header]),
      confidence: this.mappingConfidence[header] || 0,
      hasMapping: !!this.mappings[header],
      hasConfidence: !!this.mappingConfidence[header]
    }));
  }

  // Helper method to get a field label by API name
  getFieldLabelByApiName(apiName) {
    if (!apiName || !this.leadFields) return "";
    const field = this.leadFields.find((f) => f.apiName === apiName);
    return field ? field.label : apiName;
  }

  // Helper method to get confidence class based on score
  getConfidenceClass(score) {
    if (score >= 90) return "confidence-high";
    if (score >= 70) return "confidence-medium";
    return "confidence-low";
  }

  downloadTemplate() {
    console.log("downloadTemplate called");

    // Use NavigationMixin to navigate to our VisualForce page
    // This is a direct download approach that bypasses CSP restrictions
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: "/apex/LeadTemplateDownload"
      }
    });

    // Show feedback toast to confirm the action
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Template Download Started",
        message:
          "Your browser should start downloading the template momentarily",
        variant: "success"
      })
    );
  }

  reduceErrors(errors) {
    if (!Array.isArray(errors)) {
      errors = [errors];
    }

    return errors
      .map((error) => {
        // UI API read errors
        if (Array.isArray(error.body)) {
          return error.body.map((e) => e.message);
        }
        // UI API DML, Apex and network errors
        else if (error.body && typeof error.body.message === "string") {
          return error.body.message;
        }
        // JS errors
        else if (typeof error.message === "string") {
          return error.message;
        }
        // Unknown error shape so try HTTP status text
        return error.statusText || "Unknown error";
      })
      .join(", ");
  }
}
