import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inputContainer", "input", "dropdown", "hiddenField", "carret"]

  connect() {
    console.log("Assignee opened")
    this.handleClickOutside = this.handleClickOutside.bind(this)
    this.allUsers = Array.from(this.dropdownTarget.querySelectorAll(".dropdown-item"))
    document.addEventListener("turbo:frame-load", (e) => {
      if (e.target && e.target.id === "assignee_section") {
        this.hideInput()
      }
    })
  }

  openInput() {
    console.log('Opening assignee input')
    
    // Show the input container
    this.inputContainerTarget.classList.remove("hidden")
    
    // Immediately show the dropdown and all users
    this.dropdownTarget.classList.remove("hidden")
    this.allUsers.forEach(item => {
      item.classList.remove("hidden")
    })
    
    // Rotate caret
    this.carretTarget.style.transform = 'rotate(180deg)'
    
    // Focus the input
    setTimeout(() => {
      this.inputTarget.focus()
      console.log('Input focused, dropdown should be visible')
    }, 50)
    
    document.addEventListener("click", this.handleClickOutside)
  }

  hideInput() {
    this.inputContainerTarget.classList.add("hidden")
    this.dropdownTarget.classList.add("hidden")
    this.inputTarget.value = ""
    this.hiddenFieldTarget.value = ""
    // Reset carret when closing
    this.carretTarget.style.transform = 'rotate(0deg)'
    document.removeEventListener("click", this.handleClickOutside)
  }

  keydown(e) {
    if (e.key === "Escape") {
      e.preventDefault()
      this.hideInput()
    } else if (e.key === "Enter" && this.inputTarget.value.trim() === "") {
      // If user presses Enter with empty input, ensure all users are shown
      e.preventDefault()
      this.showAllUsers()
    }
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    
    if (query === "") {
      // If input is empty, show all users
      this.showAllUsers()
      return
    }

    let hasMatch = false
    this.allUsers.forEach(item => {
      const userName = item.dataset.userName.toLowerCase()
      if (userName.includes(query)) {
        item.classList.remove("hidden")
        hasMatch = true
      } else {
        item.classList.add("hidden")
      }
    })
    
    // Always show dropdown when filtering
    this.dropdownTarget.classList.remove("hidden")
    
    // Show no results message if no matches
    this.updateNoResultsMessage(!hasMatch)
    
    // Keep carret rotated when filtering
    this.carretTarget.style.transform = 'rotate(180deg)'
  }

  showAllUsers() {
    // Show all users immediately
    this.allUsers.forEach(item => {
      item.classList.remove("hidden")
    })
    this.dropdownTarget.classList.remove("hidden")
    
    // Remove any existing no results message
    this.updateNoResultsMessage(false)
    
    // Rotate carret to indicate open state
    this.carretTarget.style.transform = 'rotate(180deg)'
  }

  updateNoResultsMessage(showMessage) {
    // Remove existing no results message
    const existingMessage = this.dropdownTarget.querySelector('.no-results-message')
    if (existingMessage) {
      existingMessage.remove()
    }

    if (showMessage) {
      const noResults = document.createElement('div')
      noResults.className = 'no-results-message px-4 py-2 text-gray-500 dark:text-gray-400 italic border-b border-gray-100 dark:border-gray-600'
      noResults.textContent = 'No users found matching your search'
      this.dropdownTarget.appendChild(noResults)
    }
  }

  select(e) {
    const el = e.currentTarget
    const userId = el.dataset.userId
    const userName = el.dataset.userName

    this.inputTarget.value = userName
    this.hiddenFieldTarget.value = userId
    this.dropdownTarget.classList.add("hidden")
    
    // Reset carret
    this.carretTarget.style.transform = 'rotate(0deg)'

    // Auto-submit form
    this.element.querySelector("form").requestSubmit()
  }

  handleClickOutside(e) {
    if (!this.element.contains(e.target)) {
      this.hideInput()
    }
  }

  // Cleanup
  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
  }
}