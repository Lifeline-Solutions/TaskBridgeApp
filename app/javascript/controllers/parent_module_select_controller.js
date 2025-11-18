import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["parentSelect", "submodulesContainer", "submodulesList"]
  static values = {
    submodulesUrl: String
  }

  connect() {
    // Load submodules on initial load if a parent is already selected
    if (this.parentSelectTarget.value) {
      this.loadSubmodules()
    }
  }

  async loadSubmodules() {
    const parentId = this.parentSelectTarget.value
    
    if (!parentId) {
      // Hide submodules container if no parent selected
      this.submodulesContainerTarget.classList.add('hidden')
      return
    }

    try {
      const url = this.submodulesUrlValue.replace(':id', parentId)
      const response = await fetch(url, {
        headers: { 'Accept': 'application/json' }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const submodules = await response.json()

      if (submodules && submodules.length > 0) {
        // Show the container
        this.submodulesContainerTarget.classList.remove('hidden')
        
        // Render submodules list
        const listHtml = submodules.map(sub => 
          `<div class="text-sm text-gray-700 dark:text-gray-300 py-1">• ${sub.name}</div>`
        ).join('')
        
        this.submodulesListTarget.innerHTML = listHtml
      } else {
        // Show container with "no submodules" message
        this.submodulesContainerTarget.classList.remove('hidden')
        this.submodulesListTarget.innerHTML = 
          '<div class="text-sm text-gray-500 dark:text-gray-400 italic">No submodules yet</div>'
      }
    } catch (error) {
      console.error('Error loading submodules:', error)
      this.submodulesContainerTarget.classList.add('hidden')
    }
  }
}
