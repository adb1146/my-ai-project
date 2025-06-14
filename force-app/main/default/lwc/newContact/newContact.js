import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import { createRecord } from "lightning/uiRecordApi";

export default class NewContact extends NavigationMixin(LightningElement) {
  @api recordId; // This will receive the AccountId from the page
  accountRecordId;
  @track isFormVisible = true;

  // Form fields
  @track firstName = "";
  @track lastName = "";
  @track email = "";
  @track phone = "";

  // Compute the toggle icon based on form visibility
  get toggleIcon() {
    return this.isFormVisible ? "utility:chevronup" : "utility:chevrondown";
  }

  connectedCallback() {
    // Set the AccountId from the page context
    this.accountRecordId = this.recordId;
  }

  toggleForm() {
    this.isFormVisible = !this.isFormVisible;
  }

  handleInputChange(event) {
    const field = event.target.name;
    const value = event.target.value;

    // Update the field value
    this[field] = value;

    // Clear custom validity if user starts typing (optional, but good practice)
    const inputField = this.template.querySelector(
      `lightning-input[name='${field}']`
    );
    if (inputField) {
      inputField.setCustomValidity("");
      inputField.reportValidity();
    }
  }

  validateForm() {
    const allInputs = this.template.querySelectorAll("lightning-input");
    let isValid = true;
    allInputs.forEach((input) => {
      if (!input.reportValidity()) {
        isValid = false;
      }
    });
    return isValid;
  }

  handleSubmit() {
    if (this.validateForm()) {
      // Create the contact record
      const fields = {
        FirstName: this.firstName,
        LastName: this.lastName,
        Email: this.email,
        Phone: this.phone
      };

      // Set AccountId if available
      if (this.accountRecordId) {
        fields.AccountId = this.accountRecordId;
      }

      const recordInput = {
        apiName: "Contact",
        fields
      };

      createRecord(recordInput)
        .then((contact) => {
          this.handleSuccess(contact.id);
        })
        .catch((error) => {
          this.handleError(error);
        });
    }
  }

  handleSuccess(recordId) {
    // Show success message
    const toastEvent = new ShowToastEvent({
      title: "Success",
      message: "Contact created successfully!",
      variant: "success"
    });
    this.dispatchEvent(toastEvent);

    // Reset the form
    this.resetForm();
    this.isFormVisible = true;

    // Navigate to the new contact record
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: recordId,
        actionName: "view"
      }
    });
  }

  handleError(error) {
    let message = "Unknown error";
    if (error.body) {
      if (Array.isArray(error.body)) {
        message = error.body.map((e) => e.message).join(", ");
      } else if (typeof error.body.message === "string") {
        message = error.body.message;
      }
    }

    // Show error message
    const toastEvent = new ShowToastEvent({
      title: "Error",
      message,
      variant: "error"
    });
    this.dispatchEvent(toastEvent);
  }

  resetForm() {
    this.firstName = "";
    this.lastName = "";
    this.email = "";
    this.phone = "";
  }
}
