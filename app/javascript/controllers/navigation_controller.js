import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  connect() {
    // Initialize with messages panel hidden and proper positioning
    this.initializeModal();
  }

  previous(event) {
    event.preventDefault();
    console.log('Previous clicked - hiding messages');
    this.hideMessages();
  }

  next(event) {
    event.preventDefault();
    console.log('Next clicked - showing messages');
    this.showMessages();
  }

  initializeModal() {
    const messagesPanel = document.getElementById('messages-panel');
    const mainPanel = document.getElementById('main-panel');
    const modalContainer = document.getElementById('modal-container');

    // Ensure initial state: messages hidden, main panel full width, modal narrow
    if (messagesPanel) {
      messagesPanel.classList.add('hidden');
    }

    if (mainPanel) {
      mainPanel.classList.remove('w-1/3');
      mainPanel.classList.add('w-full');
    }

    if (modalContainer) {
      // Use CSS class for width control
      modalContainer.classList.add('modal-narrow');
      modalContainer.classList.remove('modal-wide');
    }
  }

  hideMessages() {
    const messagesPanel = document.getElementById('messages-panel');
    const mainPanel = document.getElementById('main-panel');
    const modalContainer = document.getElementById('modal-container');

    // Hide messages panel
    if (messagesPanel) {
      messagesPanel.classList.add('hidden');
    }

    // Expand main panel to full width within the modal
    if (mainPanel) {
      mainPanel.classList.remove('w-1/3');
      mainPanel.classList.add('w-full');
    }

    // Shrink modal back to narrow width - CSS classes ensure right anchoring
    if (modalContainer) {
      modalContainer.classList.add('modal-narrow');
      modalContainer.classList.remove('modal-wide');
    }
  }

  showMessages() {
    console.log('showMessages called');
    const messagesPanel = document.getElementById('messages-panel');
    const mainPanel = document.getElementById('main-panel');
    const modalContainer = document.getElementById('modal-container');
    
    console.log('Elements found:', {
      messagesPanel: !!messagesPanel,
      mainPanel: !!mainPanel,
      modalContainer: !!modalContainer
    });

    // Show messages panel
    if (messagesPanel) {
      messagesPanel.classList.remove('hidden');
      console.log('Messages panel shown');
    }

    // Shrink main panel to 1/3 width to make room for messages
    if (mainPanel) {
      mainPanel.classList.remove('w-full');
      mainPanel.classList.add('w-1/3');
      console.log('Main panel resized');
    }

    // Expand modal to wide width - CSS classes ensure right anchoring
    if (modalContainer) {
      modalContainer.classList.add('modal-wide');
      modalContainer.classList.remove('modal-narrow');
      console.log('Modal expanded to wide');
    }
  }
}
