import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    defectId: String,
    checkUrl: String,
    saveUrl: String 
  }
  
  static targets = ["editor", "draftAlert"]
  
  connect() {
    console.log('Draft controller connected for defect:', this.defectIdValue)
    this.editor = this.editorTarget.querySelector("trix-editor")
    this.setupAutoSave()
    this.checkForExistingDraft()
    this.setupBeforeUnload()
  }
  
  disconnect() {
    this.clearTimers()
  }
  
  setupAutoSave() {
    console.log('Setting up auto-save...')
    
    // Save to localStorage on every input (immediate)
    this.editor.addEventListener("input", () => {
      this.debouncedLocalSave()
    })
    
    // Save to server every 3 seconds
    this.serverSaveInterval = setInterval(() => {
      this.saveToServer()
    }, 3000)
    
    // Listen for attachment additions
    this.editor.addEventListener("trix-attachment-add", (event) => {
      console.log('Attachment added, saving to server...')
      if (event.attachment.file) {
        setTimeout(() => this.saveToServer(), 1000)
      }
    })
  }
  
  debouncedLocalSave() {
    if (this.localSaveTimeout) {
      clearTimeout(this.localSaveTimeout)
    }
    this.localSaveTimeout = setTimeout(() => {
      this.saveToLocalStorage()
    }, 500)
  }
  
  saveToLocalStorage() {
    const content = this.editor.innerHTML
    if (content && content.length > 0 && content !== '<div><br></div>') {
      const draft = {
        content: content,
        defect_id: this.defectIdValue,
        updated_at: new Date().toISOString()
      }
      localStorage.setItem(this.localStorageKey, JSON.stringify(draft))
      console.log('Draft saved to localStorage')
    }
  }
  
  async saveToServer() {
    const content = this.editor.innerHTML
    if (!content || content.length === 0 || content === '<div><br></div>') return
    
    try {
      console.log('Saving draft to server...')
      const response = await fetch(this.saveUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        },
        body: JSON.stringify({
          draft_defect_message: {
            content: content
          }
        })
      })
      
      if (response.ok) {
        console.log('Draft saved to server successfully')
        // Don't clear localStorage - keep both for redundancy
      } else {
        console.error('Failed to save draft to server:', response.status)
      }
    } catch (error) {
      console.error("Failed to save draft to server:", error)
    }
  }
  
  async checkForExistingDraft() {
    console.log('Checking for existing drafts...')
    
    // Check localStorage first (fast)
    const localDraft = this.getLocalDraft()
    
    // Then check server
    try {
      const response = await fetch(this.checkUrlValue)
      const data = await response.json()
      console.log('Server draft check:', data)
      
      if (data.has_draft || localDraft) {
        this.showDraftAlert(data, localDraft)
      }
    } catch (error) {
      console.error("Failed to check for drafts:", error)
      if (localDraft) {
        this.showDraftAlert(null, localDraft)
      }
    }
  }
  
  getLocalDraft() {
    const stored = localStorage.getItem(this.localStorageKey)
    if (stored) {
      try {
        return JSON.parse(stored)
      } catch {
        return null
      }
    }
    return null
  }
  
  showDraftAlert(serverDraft, localDraft) {
    let alert = this.draftAlertTarget
    if (!alert) {
      alert = this.createDraftAlert()
    }
    
    alert.style.display = "block"
    
    if (serverDraft && localDraft) {
      alert.innerHTML = this.bothDraftsTemplate(serverDraft, localDraft)
    } else if (serverDraft) {
      alert.innerHTML = this.serverDraftTemplate(serverDraft)
    } else {
      alert.innerHTML = this.localDraftTemplate(localDraft)
    }
    
    this.setupDraftAlertEvents(alert, serverDraft, localDraft)
  }
  
  createDraftAlert() {
    const alert = document.createElement("div")
    alert.setAttribute("data-draft-controller-target", "draftAlert")
    alert.className = "p-4 mb-4 bg-yellow-50 border border-yellow-200 rounded-lg"
    this.element.appendChild(alert)
    return alert
  }
  
  bothDraftsTemplate(serverDraft, localDraft) {
    const serverTime = new Date(serverDraft.updated_at).toLocaleString()
    const localTime = new Date(localDraft.updated_at).toLocaleString()
    
    return `
      <div class="flex items-center justify-between">
        <div>
          <strong>💾 Multiple drafts found:</strong>
          <ul class="list-disc list-inside ml-4 mt-1">
            <li>Server draft (${serverTime})</li>
            <li>Local draft (${localTime})</li>
          </ul>
        </div>
        <div class="flex gap-2">
          <button type="button" data-action="click->draft#loadServerDraft" 
                  class="px-3 py-1 bg-blue-600 text-white rounded text-sm">
            Use Server Draft
          </button>
          <button type="button" data-action="click->draft#loadLocalDraft"
                  class="px-3 py-1 bg-green-600 text-white rounded text-sm">
            Use Local Draft
          </button>
          <button type="button" data-action="click->draft#discardAllDrafts"
                  class="px-3 py-1 bg-gray-600 text-white rounded text-sm">
            Discard All
          </button>
        </div>
      </div>
    `
  }
  
  serverDraftTemplate(serverDraft) {
    const time = new Date(serverDraft.updated_at).toLocaleString()
    return `
      <div class="flex items-center justify-between">
        <div>
          <strong>💾 Unsaved draft found</strong> (saved ${time})
        </div>
        <div class="flex gap-2">
          <button type="button" data-action="click->draft#loadServerDraft" 
                  class="px-3 py-1 bg-blue-600 text-white rounded text-sm">
            Restore Draft
          </button>
          <button type="button" data-action="click->draft#discardServerDraft"
                  class="px-3 py-1 bg-gray-600 text-white rounded text-sm">
            Discard
          </button>
        </div>
      </div>
    `
  }
  
  localDraftTemplate(localDraft) {
    const time = new Date(localDraft.updated_at).toLocaleString()
    return `
      <div class="flex items-center justify-between">
        <div>
          <strong>💾 Unsaved draft found</strong> (saved ${time})
        </div>
        <div class="flex gap-2">
          <button type="button" data-action="click->draft#loadLocalDraft" 
                  class="px-3 py-1 bg-blue-600 text-white rounded text-sm">
            Restore Draft
          </button>
          <button type="button" data-action="click->draft#discardLocalDraft"
                  class="px-3 py-1 bg-gray-600 text-white rounded text-sm">
            Discard
          </button>
        </div>
      </div>
    `
  }
  
  setupDraftAlertEvents(alert, serverDraft, localDraft) {
    const serverBtn = alert.querySelector('[data-action="click->draft#loadServerDraft"]')
    if (serverBtn) {
      serverBtn.addEventListener('click', () => this.loadServerDraft())
    }
    
    const localBtn = alert.querySelector('[data-action="click->draft#loadLocalDraft"]')
    if (localBtn) {
      localBtn.addEventListener('click', () => this.loadLocalDraft())
    }
    
    const discardServerBtn = alert.querySelector('[data-action="click->draft#discardServerDraft"]')
    if (discardServerBtn) {
      discardServerBtn.addEventListener('click', () => this.discardServerDraft())
    }
    
    const discardLocalBtn = alert.querySelector('[data-action="click->draft#discardLocalDraft"]')
    if (discardLocalBtn) {
      discardLocalBtn.addEventListener('click', () => this.discardLocalDraft())
    }
    
    const discardAllBtn = alert.querySelector('[data-action="click->draft#discardAllDrafts"]')
    if (discardAllBtn) {
      discardAllBtn.addEventListener('click', () => this.discardAllDrafts())
    }
  }
  
  async loadServerDraft() {
    try {
      const response = await fetch(this.checkUrlValue)
      const data = await response.json()
      
      if (data.content) {
        this.editor.editor.loadHTML(data.content)
        this.hideDraftAlert()
      }
    } catch (error) {
      console.error("Failed to load server draft:", error)
    }
  }

  loadLocalDraft() {
    const draft = this.getLocalDraft()
    if (draft && draft.content) {
      this.editor.editor.loadHTML(draft.content)
      this.hideDraftAlert()
    }
  }

  async discardServerDraft() {
    try {
      await fetch(this.saveUrlValue, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        }
      })
      this.hideDraftAlert()
    } catch (error) {
      console.error("Failed to discard server draft:", error)
    }
  }

  discardLocalDraft() {
    this.clearLocalStorage()
    this.hideDraftAlert()
  }

  async discardAllDrafts() {
    this.clearLocalStorage()
    await this.discardServerDraft()
  }

  clearDrafts() {
    this.clearLocalStorage()
  }

  hideDraftAlert() {
    const alert = this.draftAlertTarget
    if (alert) {
      alert.style.display = "none"
    }
  }
  
  setupBeforeUnload() {
    window.addEventListener("beforeunload", (event) => {
      if (this.editor.innerHTML && this.editor.innerHTML.length > 0 && this.editor.innerHTML !== '<div><br></div>') {
        this.saveToLocalStorage()
      }
    })
  }
  
  clearLocalStorage() {
    localStorage.removeItem(this.localStorageKey)
  }

  clearAllDrafts() {
    console.log('clearAllDrafts called - form submitted')
    
    // Clear localStorage for THIS defect
    const storageKey = `defect_${this.defectIdValue}_draft_message`
    localStorage.removeItem(storageKey)
    
    // Also clear any other potential localStorage keys
    this.clearAllLocalStorageDrafts()
    
    this.hideDraftAlert()
    
    // Manually hide the notification as backup
    const notification = document.getElementById('draft-notification')
    if (notification) {
      notification.classList.add('hidden')
    }
    
    // Reset the button
    this.resetNewMessageButton()
  }

  // Add this method to clear all possible localStorage draft keys
  clearAllLocalStorageDrafts() {
    const keysToRemove = []
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i)
      if (key && key.includes('defect_') && key.includes('_draft_message')) {
        keysToRemove.push(key)
      }
    }
    
    keysToRemove.forEach(key => {
      localStorage.removeItem(key)
    })
  }

  resetNewMessageButton() {
    const newMessageBtn = document.querySelector('[href*="/defect_messages/new"]')
    if (newMessageBtn) {
      newMessageBtn.innerHTML = '➕ New Message'
      newMessageBtn.classList.add('bg-blue-600', 'hover:bg-blue-700')
      newMessageBtn.classList.remove('bg-yellow-600', 'hover:bg-yellow-700')
    }
  }
  
  clearTimers() {
    if (this.localSaveTimeout) clearTimeout(this.localSaveTimeout)
    if (this.serverSaveInterval) clearInterval(this.serverSaveInterval)
  }
  
  get localStorageKey() {
    return `defect_${this.defectIdValue}_draft_message`
  }
}