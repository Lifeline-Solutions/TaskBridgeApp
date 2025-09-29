import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inputContainer", "input"]

  connect() {
    // Bind so we can remove listener later
    this.handleClickOutside = this.handleClickOutside.bind(this)

    // After Turbo frame replacement, hide editor & remove icons
    document.addEventListener("turbo:frame-load", (e) => {
      if (e.target && e.target.id === "labels_section") {
        this.hideInput()
        this.hideRemoveButtons()
      }
    })
  }

  // Called when clicking the labels row
  openInput(event) {
    // If user clicked a remove button or a submit inside labels area, ignore open
    if (event && event.target && (event.target.closest("form") || (event.target.tagName === "BUTTON" && event.target.type === "submit"))) {
      return
    }

    // Show input container
    this.showInput()
    // Show remove icons next to each label
    this.showRemoveButtons()

    // focus input next tick
    setTimeout(() => {
      if (this.hasInputTarget) {
        this.inputTarget.focus()
        this.inputTarget.select()
      }
    }, 10)

    // start listening for outside clicks
    document.addEventListener("click", this.handleClickOutside)
  }

  // Show the input container
  showInput() {
    if (this.hasInputContainerTarget) {
      this.inputContainerTarget.classList.remove("hidden")
    }
  }

  // Hide the input container
  hideInput() {
    if (this.hasInputContainerTarget) {
      this.inputContainerTarget.classList.add("hidden")
      if (this.hasInputTarget) this.inputTarget.value = ""
    }
    // remove outside click listener
    document.removeEventListener("click", this.handleClickOutside)
  }

  // Toggle remove icons visibility helpers
  showRemoveButtons() {
    const buttons = this.element.querySelectorAll(".label-remove")
    buttons.forEach(btn => btn.classList.remove("hidden"))
  }

  hideRemoveButtons() {
    const buttons = this.element.querySelectorAll(".label-remove")
    buttons.forEach(btn => btn.classList.add("hidden"))
  }

  // Cancel (close) clicked
  cancel(e) {
    e.preventDefault()
    this.hideInput()
    this.hideRemoveButtons()
  }

  // Handle key presses inside input
  keydown(e) {
    // Enter -> allow Turbo to submit form
    if (e.key === "Enter") {
      return
    }
    // Esc -> hide
    if (e.key === "Escape") {
      e.preventDefault()
      this.hideInput()
      this.hideRemoveButtons()
    }
  }

  // When clicking outside the labels editor, close it
  handleClickOutside(e) {
    // if the click is inside this element do nothing
    if (this.element.contains(e.target)) return
    this.hideInput()
    this.hideRemoveButtons()
  }

  // Confirm deletion before submitting the remove form
  confirmRemove(e) {
    // e.target is the button inside a form created by button_to
    e.preventDefault()

    const labelName = this._closestLabelName(e.target)
    const confirmed = window.confirm(`Remove label ${labelName || ""}? This cannot be undone.`)

    if (confirmed) {
      // submit the closest form (will respect data-turbo-frame on the form and replace frame)
      const form = e.target.closest("form")
      if (form) {
        form.requestSubmit ? form.requestSubmit() : form.submit()
      }
    } else {
      // do nothing (cancelled)
    }
  }

  // small helper to find the label name text near the remove button
  _closestLabelName(target) {
    try {
      const labelSpan = target.closest("span") // the outer label span
      if (!labelSpan) return null
      const nameSpan = labelSpan.querySelector("span.truncate")
      return nameSpan ? nameSpan.textContent.trim() : null
    } catch (err) {
      return null
    }
  }
}