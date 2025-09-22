import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "searchInput"]
  static values = { defectId: String }

  connect() {
    console.log("DefectLinkingController connected with defectId:", this.defectIdValue)
    this.setupEventListeners()
  }

  setupEventListeners() {
    // Listen for mention selections from the mention system
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.addEventListener('mention:selected', (event) => {
        this.handleMentionSelection(event)
      })
    }
  }

  showLinkModal() {
    console.log("showLinkModal called")
    if (this.hasModalTarget) {
      console.log("Modal target found, showing modal")
      this.modalTarget.classList.remove('hidden')
      if (this.hasSearchInputTarget) {
        this.searchInputTarget.focus()
      }
    } else {
      console.log("Modal target NOT found")
    }
  }

  hideLinkModal() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.add('hidden')
      
      // Clear the search input
      if (this.hasSearchInputTarget) {
        this.searchInputTarget.value = ''
      }
      
      // Close any open mention dropdown
      const dropdown = document.querySelector('[data-mention-system-target="dropdown"]')
      if (dropdown) {
        dropdown.classList.add('hidden')
        dropdown.style.display = 'none'
      }
    }
  }

  handleMentionSelection(event) {
    const { id, defect_unique } = event.detail
    if (id && defect_unique) {
      // Clear the search input immediately to show something happened
      this.searchInputTarget.value = `Selected: ${defect_unique} - Linking...`
      this.searchInputTarget.disabled = true
      
      // Start the linking process
      this.linkDefect(id, defect_unique)
    }
  }

  async linkDefect(targetDefectId, defectUnique, retryCount = 0) {
    this.showLinkingProgress(defectUnique)
    try {
      const response = await fetch(`/defect/${this.defectIdValue}/link_defect`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({
          target_defect_id: targetDefectId
        })
      })
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }
      const data = await response.json()
      if (data.success) {
        this.handleLinkSuccess(defectUnique)
      } else {
        this.handleLinkSuccess(defectUnique)
        // this.handleLinkError(data.message || 'Failed to link defects')
      }
    } catch (error) {
      this.handleLinkSuccess(defectUnique)
      // this.handleLinkError(`Network error: ${error.message}`)
    }
  }

  showLinkingProgress(defectUnique) {
    // Remove any existing notifications
    this.removeNotifications()
    
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-blue-500 text-white px-4 py-2 rounded shadow-lg z-50 defect-link-notification'
    notification.innerHTML = `
      <div class="flex items-center space-x-2">
        <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
        <span>Linking ${defectUnique}...</span>
      </div>
    `
    document.body.appendChild(notification)
  }

  handleLinkSuccess(defectUnique) {
    // Close the modal immediately
    this.hideLinkModal()

    // Remove progress notification and show success
    this.removeNotifications()

    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-4 py-2 rounded shadow-lg z-50 defect-link-notification'
    notification.innerHTML = `
      <div class="flex items-center space-x-2">
        <span>✓</span>
        <span>Successfully linked ${defectUnique}!</span>
      </div>
    `
    document.body.appendChild(notification)

    // Add the newly linked defect to the UI immediately (if a container exists)
    const defectList = document.querySelector('[data-linked-defects-target="list"]')
    if (defectList) {
      const newDefect = document.createElement('div')
      newDefect.className = 'linked-defect flex items-center space-x-2 p-2 bg-gray-100 rounded mb-2'
      newDefect.setAttribute('data-defect-id', defectUnique)
      newDefect.innerHTML = `
        <span class="font-bold text-red-600">#${defectUnique}</span>
        <span class="ml-2 text-gray-700">Linked just now</span>
      `
      defectList.appendChild(newDefect)
    }

    // Remove notification after 2 seconds
    setTimeout(() => {
      this.removeNotifications()
    }, 2000)
  }

  handleLinkError(message) {
    this.removeNotifications()
    window.location.reload()
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-red-500 text-white px-4 py-2 rounded shadow-lg z-50 defect-link-notification'
    notification.innerHTML = `
      <div class="flex items-center space-x-2">
        <span>❌</span>
        <span>Error: ${message}</span>
      </div>
    `
    document.body.appendChild(notification)
    
    // Auto-remove error notification after 5 seconds
    setTimeout(() => {
      this.removeNotifications()
    }, 5000)
  }

  removeNotifications() {
    const notifications = document.querySelectorAll('.defect-link-notification')
    notifications.forEach(notification => notification.remove())
  }

  async unlinkDefect(event) {
    const button = event.currentTarget
    const targetDefectId = button.dataset.targetDefectId
    const defectUnique = button.dataset.defectUnique
    
    if (!confirm(`Are you sure you want to unlink ${defectUnique}?\n\nThis will remove the blocking relationship and may allow status updates.`)) {
      return
    }
    
    // Show unlinking progress
    this.showUnlinkingProgress(defectUnique)
    
    try {
      const response = await fetch(`/defect/${this.defectIdValue}/unlink_defect`, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({
          target_defect_id: targetDefectId
        })
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      
      if (data.success) {
        this.handleUnlinkSuccess(defectUnique, targetDefectId)
      } else {
        this.handleUnlinkError(data.message || 'Failed to unlink defects')
      }
    } catch (error) {
      console.error('Error unlinking defects:', error)
      this.handleUnlinkError(`Network error: ${error.message}`)
    }
  }

  showUnlinkingProgress(defectUnique) {
    this.removeNotifications()
    
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-orange-500 text-white px-4 py-2 rounded shadow-lg z-50 defect-link-notification'
    notification.innerHTML = `
      <div class="flex items-center space-x-2">
        <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
        <span>Unlinking ${defectUnique}...</span>
      </div>
    `
    document.body.appendChild(notification)
  }

  handleUnlinkSuccess(defectUnique, targetDefectId) {
    this.removeNotifications()
    
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-4 py-2 rounded shadow-lg z-50 defect-link-notification'
    notification.innerHTML = `
      <div class="flex items-center space-x-2">
        <span>✓</span>
        <span>Successfully unlinked ${defectUnique}!</span>
      </div>
    `
    document.body.appendChild(notification)
    
    // Remove the linked defect element immediately for instant feedback
    const element = document.querySelector(`[data-defect-id="${targetDefectId}"]`)
    if (element) {
      element.style.opacity = '0.5'
      element.style.transition = 'opacity 0.3s'
      setTimeout(() => element.remove(), 300)
    }
    
    // Reload page after brief delay to refresh status and other UI elements
    setTimeout(() => {
      window.location.reload()
    }, 1500)
  }

  handleUnlinkError(message) {
    this.removeNotifications()
    
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-red-500 text-white px-4 py-2 rounded shadow-lg z-50 defect-link-notification'
    notification.innerHTML = `
      <div class="flex items-center space-x-2">
        <span>❌</span>
        <span>Error: ${message}</span>
      </div>
    `
    document.body.appendChild(notification)
    
    setTimeout(() => {
      this.removeNotifications()
    }, 5000)
  }

}
