import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  connect() {
    this.modal = this.element
    this.boundClose = this.close.bind(this)
    this.boundOpen = this.open.bind(this)
    this.boundHandleDefaultAssignee = this.handleDefaultAssigneeClick.bind(this)
    
    // Find and attach to the external button
    const button = document.getElementById("actionsMenuButton")
    if (button) {
      button.addEventListener("click", this.boundOpen)
    }

    // Handle default assignee link
    const defaultAssigneeLink = document.getElementById("defaultAssigneeLink")
    if (defaultAssigneeLink) {
      defaultAssigneeLink.addEventListener("click", this.boundHandleDefaultAssignee)
    }

    // Listen for turbo frame load to close modal
    document.addEventListener("turbo:frame-load", this.boundClose)
  }

  disconnect() {
    // Clean up event listeners
    const button = document.getElementById("actionsMenuButton")
    if (button) {
      button.removeEventListener("click", this.boundOpen)
    }

    const defaultAssigneeLink = document.getElementById("defaultAssigneeLink")
    if (defaultAssigneeLink) {
      defaultAssigneeLink.removeEventListener("click", this.boundHandleDefaultAssignee)
    }

    document.removeEventListener("turbo:frame-load", this.boundClose)
  }

  handleDefaultAssigneeClick(event) {
    // Let the link work normally, but close modal after a short delay
    // This allows the turbo frame to start loading
    setTimeout(() => {
      this.close()
    }, 100)
  }

  open(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    this.modal.classList.remove("hidden")
    
    // Add animation
    setTimeout(() => {
      this.contentTarget.classList.remove("scale-95", "opacity-0")
      this.contentTarget.classList.add("scale-100", "opacity-100")
    }, 10)
  }

  close(event) {
    // Don't prevent default for turbo events
    if (event?.preventDefault && event.type !== "turbo:frame-load") {
      event.preventDefault()
      event.stopPropagation()
    }
    
    // Animate out
    this.contentTarget.classList.remove("scale-100", "opacity-100")
    this.contentTarget.classList.add("scale-95", "opacity-0")
    
    // Hide after animation
    setTimeout(() => {
      this.modal.classList.add("hidden")
    }, 200)
  }

  closeOnBackdrop(event) {
    // Only close if clicking the backdrop itself, not the content
    if (event.target === this.modal) {
      this.close(event)
    }
  }
}
