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
    
    // Always use the most recent draft (server takes priority if both exist)
    const mostRecentDraft = this.getMostRecentDraft(serverDraft, localDraft)
    
    if (serverDraft && localDraft) {
      alert.innerHTML = this.multipleDraftsTemplate(serverDraft, localDraft, mostRecentDraft)
    } else if (serverDraft) {
      alert.innerHTML = this.singleDraftTemplate(serverDraft, 'server')
    } else {
      alert.innerHTML = this.singleDraftTemplate(localDraft, 'local')
    }
    
    this.setupDraftAlertEvents(alert, mostRecentDraft)
  }
  
  createDraftAlert() {
    const alert = document.createElement("div")
    alert.setAttribute("data-draft-controller-target", "draftAlert")
    alert.className = "p-4 mb-4 bg-yellow-50 border border-yellow-200 rounded-lg"
    this.element.appendChild(alert)
    return alert
  }
  
  getMostRecentDraft(serverDraft, localDraft) {
    if (!serverDraft) return { draft: localDraft, source: 'local' }
    if (!localDraft) return { draft: serverDraft, source: 'server' }
    
    const serverTime = new Date(serverDraft.updated_at)
    const localTime = new Date(localDraft.updated_at)
    
    return serverTime > localTime 
      ? { draft: serverDraft, source: 'server' }
      : { draft: localDraft, source: 'local' }
  }
  
  multipleDraftsTemplate(serverDraft, localDraft, mostRecentDraft) {
    const serverTime = new Date(serverDraft.updated_at).toLocaleString()
    const localTime = new Date(localDraft.updated_at).toLocaleString()
    const sourceText = mostRecentDraft.source === 'server' ? 'server' : 'local'
    
    return `
      <div class="flex items-center justify-between">
        <div>
          <strong>💾 Multiple drafts found</strong>
          <div class="text-sm text-gray-600 mt-1">
            Using most recent (${sourceText}) draft from ${mostRecentDraft.source === 'server' ? serverTime : localTime}
          </div>
          <ul class="list-disc list-inside ml-4 mt-1 text-sm text-gray-600">
            <li>Server draft (${serverTime})</li>
            <li>Local draft (${localTime})</li>
          </ul>
        </div>
        <div class="flex gap-2">
          <button type="button" data-action="click->draft#loadMostRecentDraft" 
                  class="px-3 py-1 bg-blue-600 text-white rounded text-sm hover:bg-blue-700">
            Restore Most Recent
          </button>
          <button type="button" data-action="click->draft#discardAllDrafts"
                  class="px-3 py-1 bg-gray-600 text-white rounded text-sm hover:bg-gray-700">
            Discard All
          </button>
        </div>
      </div>
    `
  }
  
  singleDraftTemplate(draft, source) {
    const time = new Date(draft.updated_at).toLocaleString()
    const sourceText = source === 'server' ? 'server' : 'local'
    
    return `
      <div class="flex items-center justify-between">
        <div>
          <strong>💾 Unsaved draft found</strong>
          <div class="text-sm text-gray-600 mt-1">
            Saved on ${sourceText} (${time})
          </div>
        </div>
        <div class="flex gap-2">
          <button type="button" data-action="click->draft#loadMostRecentDraft" 
                  class="px-3 py-1 bg-blue-600 text-white rounded text-sm hover:bg-blue-700">
            Restore Draft
          </button>
          <button type="button" data-action="click->draft#discardAllDrafts"
                  class="px-3 py-1 bg-gray-600 text-white rounded text-sm hover:bg-gray-700">
            Discard
          </button>
        </div>
      </div>
    `
  }
  
  setupDraftAlertEvents(alert, mostRecentDraft) {
    const restoreBtn = alert.querySelector('[data-action="click->draft#loadMostRecentDraft"]')
    if (restoreBtn) {
      restoreBtn.addEventListener('click', () => this.loadMostRecentDraft())
    }
    
    const discardBtn = alert.querySelector('[data-action="click->draft#discardAllDrafts"]')
    if (discardBtn) {
      discardBtn.addEventListener('click', () => this.discardAllDrafts())
    }
  }
  
  loadMostRecentDraft() {
    // Check both sources and load the most recent one
    const localDraft = this.getLocalDraft()
    
    if (localDraft) {
      // Check server to see which is more recent
      fetch(this.checkUrlValue)
        .then(response => response.json())
        .then(serverData => {
          if (serverData.has_draft) {
            const serverTime = new Date(serverData.updated_at)
            const localTime = new Date(localDraft.updated_at)
            
            if (serverTime > localTime) {
              console.log('Loading server draft (more recent)')
              this.editor.editor.loadHTML(serverData.content)
            } else {
              console.log('Loading local draft (more recent)')
              this.editor.editor.loadHTML(localDraft.content)
            }
          } else {
            console.log('Loading local draft (only option)')
            this.editor.editor.loadHTML(localDraft.content)
          }
          this.hideDraftAlert()
        })
        .catch(error => {
          console.error('Failed to check server draft, loading local:', error)
          this.editor.editor.loadHTML(localDraft.content)
          this.hideDraftAlert()
        })
    } else {
      // No local draft, try server
      this.loadServerDraft()
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

  async discardAllDrafts() {
    // Clear localStorage
    this.clearLocalStorage()
    
    // Clear server draft
    try {
      await fetch(this.saveUrlValue, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        }
      })
    } catch (error) {
      console.error("Failed to discard server draft:", error)
    }
    
    this.hideDraftAlert()
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