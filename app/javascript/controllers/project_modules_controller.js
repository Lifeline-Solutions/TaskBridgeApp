import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["projectSelect", "moduleSelect", "submoduleSelect"]
  static values = {
    modulesUrl: String,
    noModulesMessage: { type: String, default: "No modules available" },
    selectPrompt: { type: String, default: "Select Module" },
    currentModuleId: Number,
    currentSubmoduleId: Number
  }

  connect() {
    this.initializeSelects()
  }

  initializeSelects() {
    // If the server already rendered module options (more than just the blank prompt),
    // prefer those and just set the selected values. Only fetch if there are no options.
    try {
      const hasServerOptions = this.moduleSelectTarget && this.moduleSelectTarget.options.length > 1

      if (hasServerOptions) {
        // apply server-provided selected values (if any)
        if (this.currentModuleIdValue) {
          this.moduleSelectTarget.value = String(this.currentModuleIdValue)
        }

        // Ensure submodules are populated / selected:
        // If submodule select has server options, use them. Otherwise fetch submodules for the selected module.
        const hasSubOptions = this.hasSubmoduleSelectTarget && this.submoduleSelectTarget.options.length > 1
        if (this.hasSubmoduleSelectTarget && !hasSubOptions && this.moduleSelectTarget.value) {
          // fetch submodules for the selected module to populate the submodule select
          this.loadSubmodules()
        } else if (this.hasSubmoduleSelectTarget && this.currentSubmoduleIdValue) {
          this.submoduleSelectTarget.value = String(this.currentSubmoduleIdValue)
        }

        return
      }

      // If we reach here, there are no server-rendered module options:
      // load modules for the current project (if any)
      const projectId = this.hasProjectSelectTarget ? this.projectSelectTarget.value : null
      if (projectId) {
        this.loadModules()
      } else {
        this.toggleModuleSelect(null)
      }
    } catch (err) {
      console.error('project-modules initialize error', err)
    }
  }

  loadModules() {
    if (!this.hasProjectSelectTarget) return

    const projectId = this.projectSelectTarget.value
    if (!projectId) {
      this.toggleModuleSelect(null)
      return
    }

    this.toggleModuleSelect(projectId)
    this.fetchModules(projectId)
  }

  toggleModuleSelect(projectId) {
    if (projectId) {
      this.moduleSelectTarget.disabled = false
      this.moduleSelectTarget.innerHTML = `<option value="">Loading modules...</option>`
    } else {
      this.moduleSelectTarget.disabled = true
      this.moduleSelectTarget.innerHTML = `<option value="">${this.selectPromptValue}</option>`
      this.clearSubmodules()
    }
  }

  async fetchModules(projectId) {
    try {
      const url = `${this.modulesUrlValue}?product_id=${projectId}`
      console.debug('Fetching modules from', url)
      const response = await fetch(url, { headers: { "Accept": "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const modules = await response.json()
      this.updateModuleSelect(modules)
    } catch (error) {
      console.error("Error fetching modules:", error)
      this.moduleSelectTarget.innerHTML = `<option value="">Error loading modules</option>`
      this.clearSubmodules()
    }
  }

  updateModuleSelect(modules) {
    let options = `<option value="">${this.selectPromptValue}</option>`

    if (!modules || modules.length === 0) {
      options = `<option value="">${this.noModulesMessageValue}</option>`
    } else {
      modules.forEach(m => {
        options += `<option value="${m.id}">${m.name}</option>`
      })
    }

    this.moduleSelectTarget.innerHTML = options

    // Pre-select module if we have a currentModuleIdValue (edit case)
    if (this.currentModuleIdValue) {
      this.moduleSelectTarget.value = String(this.currentModuleIdValue)
    }

    // Load submodules for the current (selected) module
    this.loadSubmodules()
  }

  // Handles module select change events and programmatic calls
  async loadSubmodules(event) {
    const moduleId = event ? event.target.value : this.moduleSelectTarget.value

    if (!this.hasSubmoduleSelectTarget) return

    if (!moduleId) {
      this.submoduleSelectTarget.innerHTML = '<option value="">Select Sub-Module</option>'
      return
    }

    // If server already supplied submodule options, and they match the selected module, keep them.
    const hasServerSubOptions = this.submoduleSelectTarget.options.length > 1
    if (hasServerSubOptions && String(this.currentModuleIdValue) === String(moduleId)) {
      // server-provided submodule options already present (likely from controller preload)
      if (this.currentSubmoduleIdValue) {
        this.submoduleSelectTarget.value = String(this.currentSubmoduleIdValue)
      }
      return
    }

    // Otherwise fetch submodules dynamically
    this.submoduleSelectTarget.innerHTML = '<option value="">Loading sub-modules...</option>'

    try {
      const response = await fetch(`/qa_modules/${moduleId}/submodules`, { headers: { "Accept": "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const submodules = await response.json()

      let options = '<option value="">Select Sub-Module</option>'
      if (submodules && submodules.length > 0) {
        submodules.forEach(sm => {
          options += `<option value="${sm.id}">${sm.name}</option>`
        })
      } else {
        options = '<option value="">No sub-modules</option>'
      }

      this.submoduleSelectTarget.innerHTML = options

      // Only pre-select if we are loading the module that matches the initial state
      if (this.currentSubmoduleIdValue && String(moduleId) === String(this.currentModuleIdValue)) {
        this.submoduleSelectTarget.value = String(this.currentSubmoduleIdValue)
      }
    } catch (error) {
      console.error("Error fetching submodules:", error)
      this.submoduleSelectTarget.innerHTML = '<option value="">Error loading sub-modules</option>'
    }
  }

  clearSubmodules() {
    if (this.hasSubmoduleSelectTarget) {
      this.submoduleSelectTarget.innerHTML = '<option value="">Select Sub-Module</option>'
    }
  }
}