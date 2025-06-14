import { LightningElement, track, api } from "lwc";
import sendMessageToOpenAI from "@salesforce/apex/OpenAIController.sendMessageToOpenAI";
import createRecord from "@salesforce/apex/OpenAIController.createRecord";

export default class OpenAIChatbot extends LightningElement {
  // References to DOM elements
  chatMessagesContainer;
  chatMessages;
  @track messages = [];
  @track userInput = "";
  @track isLoading = false;
  @track extractedData = null;
  @track selectedObject = "Lead"; // Default object type
  @api recordId;
  @api objectApiName;

  // Lifecycle hooks
  renderedCallback() {
    // Find chat messages container once and store reference
    if (!this.chatMessagesContainer) {
      this.chatMessagesContainer = this.template.querySelector(
        ".chat-messages-container"
      );

      console.log(
        "Chat messages container:",
        this.chatMessagesContainer ? "Found" : "Not Found"
      );

      if (this.chatMessagesContainer) {
        this.renderMessages();
      }
    }
  }

  // Computed property for the disabled state of send button
  get sendButtonDisabled() {
    return this.isLoading || !this.userInput;
  }

  // Process extracted data for display
  get extractedDataFields() {
    if (!this.extractedData) return [];

    return Object.keys(this.extractedData).map((key) => {
      return {
        name: key,
        label: key
          .replace("_c", "")
          .replace(/([A-Z])/g, " $1")
          .replace(/^./, (str) => str.toUpperCase()),
        value: this.extractedData[key]
      };
    });
  }

  // Object options for record creation
  get objectOptions() {
    return [
      { label: "Lead", value: "Lead" },
      { label: "Contact", value: "Contact" },
      { label: "Account", value: "Account" },
      { label: "Opportunity", value: "Opportunity" },
      { label: "Case", value: "Case" }
    ];
  }

  // Handle object type change
  handleObjectChange(event) {
    this.selectedObject = event.detail.value;
  }

  // Handle user input change
  handleInputChange(event) {
    this.userInput = event.target.value;
  }

  // Handle when user presses Enter key
  handleKeyPress(event) {
    if (event.keyCode === 13) {
      this.handleSendMessage();
    }
  }

  // Render messages in the chat container
  renderMessages() {
    if (!this.chatMessagesContainer) {
      console.error("Cannot render messages: container not found");
      return;
    }

    // Process messages to add UI-specific properties
    const processedMessages = this.messages.map((msg) => {
      return {
        ...msg,
        messageClass: `${msg.sender}-message-container`,
        contentClass: `${msg.sender}-message`,
        senderName:
          msg.sender === "user"
            ? "You"
            : msg.sender === "ai"
              ? "AI Assistant"
              : "System"
      };
    });

    // Clear existing messages by removing all child nodes safely
    while (this.chatMessagesContainer.firstChild) {
      this.chatMessagesContainer.removeChild(
        this.chatMessagesContainer.firstChild
      );
    }

    // Create a document fragment to reduce DOM operations
    const fragment = document.createDocumentFragment();

    // Add messages using DOM API (avoiding innerHTML)
    processedMessages.forEach((msg) => {
      const messageDiv = document.createElement("div");
      messageDiv.className = msg.messageClass;
      messageDiv.setAttribute("key", msg.id); // Add key attribute for identification

      const contentDiv = document.createElement("div");
      contentDiv.className = msg.contentClass;

      const headerDiv = document.createElement("div");
      headerDiv.className = "message-header";

      const senderSpan = document.createElement("span");
      senderSpan.className = "sender";
      senderSpan.textContent = msg.senderName;

      const timestampSpan = document.createElement("span");
      timestampSpan.className = "timestamp";
      timestampSpan.textContent = msg.timestamp;

      headerDiv.appendChild(senderSpan);
      headerDiv.appendChild(timestampSpan);

      const contentTextDiv = document.createElement("div");
      contentTextDiv.className = "message-content";
      contentTextDiv.textContent = msg.content;

      contentDiv.appendChild(headerDiv);
      contentDiv.appendChild(contentTextDiv);
      messageDiv.appendChild(contentDiv);

      fragment.appendChild(messageDiv);
    });

    // Add all messages to the container at once
    this.chatMessagesContainer.appendChild(fragment);

    // Scroll to the bottom using requestAnimationFrame for proper timing
    // This avoids using setTimeout which is restricted in LWC
    if (this.chatMessagesContainer) {
      // Use Promise.resolve().then to create a microtask, which runs after rendering
      Promise.resolve().then(() => {
        this.chatMessagesContainer.scrollTop =
          this.chatMessagesContainer.scrollHeight;
      });
    }
  }

  // Send message to OpenAI
  handleSendMessage() {
    if (this.userInput.trim() === "") return;

    // Add user message to chat
    const userMessage = {
      id: Date.now(),
      sender: "user",
      content: this.userInput,
      timestamp: new Date().toLocaleTimeString()
    };

    this.messages = [...this.messages, userMessage];
    this.renderMessages();

    // Clear input and set loading state
    const input = this.userInput;
    this.userInput = "";
    this.isLoading = true;

    // Log request details for debugging
    console.log("Sending request to OpenAI:", {
      message: input,
      objectType: this.selectedObject,
      previousMessagesCount: this.messages.length
    });

    // Send to OpenAI
    sendMessageToOpenAI({
      message: input,
      objectType: this.selectedObject,
      previousMessages: JSON.stringify(
        this.messages.map((msg) => ({
          role: msg.sender === "user" ? "user" : "assistant",
          content: msg.content
        }))
      )
    })
      .then((result) => {
        // Add AI response to chat
        const aiMessage = {
          id: Date.now(),
          sender: "ai",
          content: result.message,
          timestamp: new Date().toLocaleTimeString()
        };

        this.messages = [...this.messages, aiMessage];
        this.renderMessages();

        // If data was extracted, show it for confirmation
        if (result.extractedData) {
          this.extractedData = result.extractedData;
        }
      })
      .catch((error) => {
        console.error("Error communicating with OpenAI:", error);
        // Add detailed error info to the console for debugging
        if (error.body && error.body.message) {
          console.error("Error details:", error.body.message);
        }

        // Extract a more user-friendly error message
        let userFriendlyMessage =
          "Sorry, there was an error processing your request.";
        let detailedError = "";

        if (error.body && error.body.message) {
          detailedError = error.body.message;

          // Check for common errors and provide helpful messages
          if (error.body.message.includes("API key")) {
            userFriendlyMessage =
              "OpenAI API key issue. Please contact your administrator to verify the API key is correct.";
          } else if (error.body.message.includes("OpenAI API Error")) {
            userFriendlyMessage =
              "Unable to connect to OpenAI. Please try again in a few moments.";
          } else if (error.body.message.includes("Script-thrown")) {
            userFriendlyMessage =
              "An internal script error occurred. Please try a simpler message or contact support.";
          }
        }

        // Add error message to chat
        const errorMessage = {
          id: Date.now(),
          sender: "system",
          content: `${userFriendlyMessage}\n\nTechnical details: ${detailedError || error.message || "Unknown error"}`,
          timestamp: new Date().toLocaleTimeString()
        };

        this.messages = [...this.messages, errorMessage];
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  // Create record from extracted data
  handleCreateRecord() {
    if (!this.extractedData) return;

    this.isLoading = true;

    createRecord({
      objectType: this.selectedObject,
      recordData: JSON.stringify(this.extractedData)
    })
      .then((result) => {
        // Add success message to chat
        const successMessage = {
          id: Date.now(),
          sender: "system",
          content: `Successfully created ${this.selectedObject}: ${result}`,
          timestamp: new Date().toLocaleTimeString()
        };

        this.messages = [...this.messages, successMessage];
        this.renderMessages();

        // Clear extracted data
        this.extractedData = null;
      })
      .catch((error) => {
        console.error("Error creating record:", error);
        // Add error message to chat
        const errorMessage = {
          id: Date.now(),
          sender: "system",
          content: `Error creating record: ${error.body?.message || "Unknown error"}`,
          timestamp: new Date().toLocaleTimeString()
        };

        this.messages = [...this.messages, errorMessage];
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  // Cancel record creation
  handleCancelRecord() {
    this.extractedData = null;
  }
}
