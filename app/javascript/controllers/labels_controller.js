import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="labels"
export default class extends Controller {
  static targets = ["input", "select", "chips"]

  async add(event) {
    if (event.type === "keydown" && event.key !== "Enter") return
    event.preventDefault()

    const value = this.inputTarget.value.trim()
    if (!value) return

    // Check if already exists in hidden select
    let option = Array.from(this.selectTarget.options).find(opt => opt.text === value)
    if (option) {
      option.selected = true
      this.inputTarget.value = ""
      this.renderChips()
      return
    }

    try {
      // Create label in backend
      const response = await fetch("/labels", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({ name: value })
      })

      if (!response.ok) throw new Error("Failed to create label")
      const data = await response.json()

      // Add option with returned ID
      const newOption = new Option(data.name, data.id, true, true)
      this.selectTarget.add(newOption)

      this.inputTarget.value = ""
      this.renderChips()
    } catch (e) {
      console.error("Error creating label:", e)
    }
  }

  remove(event) {
    const id = event.currentTarget.dataset.id

    // Unselect from hidden select
    let option = Array.from(this.selectTarget.options).find(opt => opt.value == id)
    if (option) option.selected = false

    this.renderChips()
  }

  renderChips() {
    this.chipsTarget.innerHTML = ""

    Array.from(this.selectTarget.selectedOptions).forEach(opt => {
      const span = document.createElement("span")
      span.className =
        "px-2 py-1 bg-gray-200 text-gray-800 rounded-md text-xs font-medium flex items-center gap-1 rounded"
      span.innerHTML = `
        ${opt.text}
        <button type="button"
                class="ml-1 text-red-500 hover:text-red-700 text-xs font-bold cursor-pointer"
                data-action="click->labels#remove"
                data-id="${opt.value}">
          ✕
        </button>
      `
      this.chipsTarget.appendChild(span)
    })
  }
}
