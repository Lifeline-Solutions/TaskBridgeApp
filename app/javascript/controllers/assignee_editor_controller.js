import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inputContainer", "input", "dropdown", "hiddenField"]

  connect() {
    this.handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("turbo:frame-load", (e) => {
      if (e.target && e.target.id === "assignee_section") {
        this.hideInput()
      }
    })
  }

  openInput() {
    this.inputContainerTarget.classList.remove("hidden")
    setTimeout(() => this.inputTarget.focus(), 10)
    document.addEventListener("click", this.handleClickOutside)
  }

  hideInput() {
    this.inputContainerTarget.classList.add("hidden")
    this.dropdownTarget.classList.add("hidden")
    this.inputTarget.value = ""
    document.removeEventListener("click", this.handleClickOutside)
  }

  keydown(e) {
    if (e.key === "Escape") {
      e.preventDefault()
      this.hideInput()
    }
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase()
    let hasMatch = false
    this.dropdownTarget.querySelectorAll(".dropdown-item").forEach(item => {
      const text = item.textContent.toLowerCase()
      if (text.includes(query)) {
        item.classList.remove("hidden")
        hasMatch = true
      } else {
        item.classList.add("hidden")
      }
    })
    this.dropdownTarget.classList.toggle("hidden", !hasMatch)
  }

  select(e) {
    const el = e.currentTarget
    const userId = el.dataset.userId
    const userName = el.textContent.trim()

    this.inputTarget.value = userName
    this.hiddenFieldTarget.value = userId
    this.dropdownTarget.classList.add("hidden")

    // auto-submit form
    this.element.querySelector("form").requestSubmit()
  }

  handleClickOutside(e) {
    if (!this.element.contains(e.target)) {
      this.hideInput()
    }
  }
}