import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["star", "radio", "counter"]

  connect() {
    this.current = 0

    // if a radio is pre-checked, initialize from it
    if (this.hasRadioTarget) {
      const checked = this.radioTargets.find(r => r.checked)
      if (checked) {
        this.setRating(Number(checked.value))
        return
      }
    }

    // default state
    this.previewStars(0)
    this.updateCounter(0)
  }

  // called when user clicks an SVG star
  onStarClick(event) {
    const val = Number(event.currentTarget.dataset.value)
    this.setRating(val)
  }

  // called when user hovers over a star
  onStarEnter(event) {
    const val = Number(event.currentTarget.dataset.value)
    this.previewStars(val)
    this.updateCounter(val)
  }

  // called when a radio input changes (e.g., label click)
  onRadioChange(event) {
    const val = Number(event.currentTarget.value)
    this.setRating(val)
  }

  // restore to the selected rating when leaving the container
  restore() {
    this.previewStars(this.current)
    this.updateCounter(this.current)
  }

  setRating(val) {
    this.current = val

    // check the corresponding radio so the form submits the value
    if (this.hasRadioTarget) {
      const radio = this.radioTargets.find(r => Number(r.value) === val)
      if (radio) radio.checked = true
    }

    this.previewStars(val)
    this.updateCounter(val)
  }

  previewStars(val) {
    if (!this.hasStarTarget) return

    this.starTargets.forEach((s) => {
      const v = Number(s.dataset.value)
      if (v <= val) {
        s.classList.add('text-yellow-400')
        s.classList.remove('text-gray-300')
      } else {
        s.classList.add('text-gray-300')
        s.classList.remove('text-yellow-400')
      }
    })
  }

  updateCounter(val) {
    if (!this.hasCounterTarget) return
    this.counterTarget.textContent = `${val}/5`
  }
}