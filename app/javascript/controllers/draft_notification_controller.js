import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    defectId: String,
    checkUrl: String
  }
  
  connect() {
    console.log('Draft notification controller connected')
    // Check immediately when connected
    setTimeout(() => this.checkForDrafts(), 100)
    
    // Listen for Turbo events
    this.setupEventListeners()
  }
  
  setupEventListeners() {
    // Check when page loads
    document.addEventListener("turbo:load", () => {
      setTimeout(() => this.checkForDrafts(), 100)
    })
    
    // Check when frames load (after form submission)
    document.addEventListener("turbo:frame-load", (event) => {
      if (event.target.id === 'defect-messages') {
        setTimeout(() => this.checkForDrafts(), 100)
      }
    })
    
    // Check after form submissions
    document.addEventListener("turbo:submit-end", (event) => {
      if (event.detail.success) {
        setTimeout(() => this.checkForDrafts(), 300)
      }
    })
  }
  
  async checkForDrafts() {
    try {
      console.log('Checking for drafts...', this.checkUrlValue)
      const response = await fetch(this.checkUrlValue)
      const data = await response.json()
      
      console.log('Draft check result:', data)
      
      if (data.has_draft) {
        this.showNotification()
      } else {
        // Also check localStorage as fallback
        const localDraft = localStorage.getItem(`defect_${this.defectIdValue}_draft_message`)
        if (localDraft) {
          this.showNotification()
        } else {
          this.hideNotification()
        }
      }
    } catch (error) {
      console.error("Failed to check for drafts:", error)
      // Check localStorage as fallback
      const localDraft = localStorage.getItem(`defect_${this.defectIdValue}_draft_message`)
      if (localDraft) {
        this.showNotification()
      } else {
        this.hideNotification()
      }
    }
  }
  
  showNotification() {
    const notification = document.getElementById('draft-notification')
    if (notification) {
      notification.classList.remove('hidden')
      console.log('Draft notification shown')
    }
    
    this.updateNewMessageButton(true)
  }
  
  hideNotification() {
    const notification = document.getElementById('draft-notification')
    if (notification) {
      notification.classList.add('hidden')
    }
    
    this.updateNewMessageButton(false)
  }
  
  updateNewMessageButton(hasDraft) {
    const newMessageBtn = document.querySelector('[href*="/defect_messages/new"]')
    if (newMessageBtn) {
      if (hasDraft) {
        newMessageBtn.innerHTML = '💾 Continue Draft Message'
        newMessageBtn.classList.add('bg-yellow-600', 'hover:bg-yellow-700')
        newMessageBtn.classList.remove('bg-blue-600', 'hover:bg-blue-700')
      } else {
        newMessageBtn.innerHTML = '➕ New Message'
        newMessageBtn.classList.add('bg-blue-600', 'hover:bg-blue-700')
        newMessageBtn.classList.remove('bg-yellow-600', 'hover:bg-yellow-700')
      }
    }
  }
  
  async discardDraft() {
    if (confirm('Are you sure you want to discard your draft message?')) {
      try {
        await fetch(this.checkUrlValue.replace('/check', ''), {
          method: "DELETE",
          headers: {
            "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
          }
        })
        
        // Clear localStorage
        localStorage.removeItem(`defect_${this.defectIdValue}_draft_message`)
        
        this.hideNotification()
      } catch (error) {
        console.error("Failed to discard draft:", error)
      }
    }
  }
  
  forceRefresh() {
    this.checkForDrafts()
  }
}