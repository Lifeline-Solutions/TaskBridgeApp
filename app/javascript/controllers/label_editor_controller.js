import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inputContainer", "input"]

  connect() {
    this.handleClickOutside = this.handleClickOutside.bind(this)
    // After a turbo frame replace, hide input (successful add/remove)
    document.addEventListener("turbo:frame-load", (e) => {
      // If the frame replaced was the labels_section, hide input
      if (e.target && e.target.id === "labels_section") {
        this.hideInput()
      }
    })
  }

  openInput(event) {
    // If user clicked a remove button or a button inside the labels, ignore
    if (event && event.target && (event.target.closest("form") || event.target.tagName === "BUTTON" && event.target.type === "submit")) {
      return
    }

    this.inputContainerTarget.classList.remove("hidden")
    // focus input (after next tick so element exists)
    setTimeout(() => {
      if (this.hasInputTarget) {
        this.inputTarget.focus()
        this.inputTarget.select()
      }
    }, 10)
    document.addEventListener("click", this.handleClickOutside)
  }

  hideInput() {
    this.inputContainerTarget.classList.add("hidden")
    document.removeEventListener("click", this.handleClickOutside)
    if (this.hasInputTarget) this.inputTarget.value = ""
  }

  cancel(e) {
    e.preventDefault()
    this.hideInput()
  }

  keydown(e) {
    // Enter -> allow Turbo to submit the form
    if (e.key === "Enter") {
      // Let the form submit normally (Turbo will handle)
      return
    }
    // Esc -> cancel & hide input
    if (e.key === "Escape") {
      e.preventDefault()
      this.hideInput()
    }
  }

  handleClickOutside(e) {
    // if click is inside the input container or labels area do nothing
    if (this.element.contains(e.target)) return
    this.hideInput()
  }
}