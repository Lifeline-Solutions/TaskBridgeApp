import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["projectSelect", "moduleSelect", "submoduleSelect"]
  static values = { 
    modulesUrl: String,
    noModulesMessage: { type: String, default: "No modules available" },
    selectPrompt: { type: String, default: "Select Module" }
  }

  connect() {
    this.initializeSelects()
  }

  initializeSelects() {
    const projectId = this.projectSelectTarget.value
    this.toggleModuleSelect(projectId)
  }

  loadModules() {
    const projectId = this.projectSelectTarget.value
    
    this.toggleModuleSelect(projectId)
    
    if (projectId) {
      this.fetchModules(projectId)
    }
  }

  toggleModuleSelect(projectId) {
    if (projectId) {
      this.moduleSelectTarget.disabled = false
      this.moduleSelectTarget.innerHTML = '<option value="">Loading modules...</option>'
    } else {
      this.moduleSelectTarget.disabled = true
      this.moduleSelectTarget.innerHTML = `<option value="">${this.selectPromptValue}</option>`
      this.clearSubmodules()
    }
  }

  async fetchModules(projectId) {
    try {
      const response = await fetch(`${this.modulesUrlValue}?product_id=${projectId}`)
      const modules = await response.json()
      
      this.updateModuleSelect(modules)
    } catch (error) {
      console.error('Error fetching modules:', error)
      this.moduleSelectTarget.innerHTML = `<option value="">Error loading modules</option>`
    }
  }

  updateModuleSelect(modules) {
    let options = `<option value="">${this.selectPromptValue}</option>`
    
    if (modules.length === 0) {
      options = `<option value="">${this.noModulesMessageValue}</option>`
    } else {
      modules.forEach(module => {
        options += `<option value="${module.id}">${module.name}</option>`
      })
    }
    
    this.moduleSelectTarget.innerHTML = options
    this.clearSubmodules()
  }

  clearSubmodules() {
    if (this.hasSubmoduleSelectTarget) {
      this.submoduleSelectTarget.innerHTML = '<option value="">Select Sub-Module</option>'
    }
  }
}