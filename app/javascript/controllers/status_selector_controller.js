import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select"]

  connect() {
    this.select = this.hasSelectTarget ? this.selectTarget : this.element.querySelector("select")
  }

  // wired with data-action="change->status-selector#change"
  change(event) {
    event.preventDefault()
    const form = this.element.tagName === "FORM" ? this.element : this.select.closest("form")
    if (!form) return console.error("status-selector: form not found")

    const tokenEl = document.querySelector("meta[name='csrf-token']")
    const token = tokenEl ? tokenEl.getAttribute("content") : ""

    fetch(form.action, {
      method: (form.method || "post").toUpperCase(),
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token
      },
      body: new URLSearchParams(new FormData(form)),
      credentials: "same-origin"
    })
    .then(response => {
      if (!response.ok) throw new Error("Network response was not ok")
      return response.text()
    })
    .then(body => {
      // Let Turbo apply the returned turbo-streams
      if (window.Turbo && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(body)
      } else {
        // Fallback: replace #modal with returned HTML (non-stream)
        const modal = document.getElementById("modal")
        if (modal) modal.innerHTML = body
      }
    })
    .catch(err => {
      console.error("status-selector change failed:", err)
      // optional: show toast/notice
    })
  }
}
