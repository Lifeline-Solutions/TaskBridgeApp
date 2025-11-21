import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        url: String
    }

    async remove(event) {
        event.preventDefault()

        if (!confirm("Are you sure you want to delete this file?")) {
            return
        }

        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        try {
            const response = await fetch(this.urlValue, {
                method: "DELETE",
                headers: {
                    "X-CSRF-Token": csrfToken,
                    "Accept": "application/json"
                }
            })

            if (response.ok) {
                this.element.remove()
            } else {
                alert("Failed to delete attachment. Please try again.")
            }
        } catch (error) {
            console.error("Error deleting attachment:", error)
            alert("An error occurred. Please try again.")
        }
    }
}
