import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ['container']

  connect() {
    this.container = this.element
    this.stars = Array.from(this.container.querySelectorAll('.star'))
    this.radios = Array.from(this.container.querySelectorAll('.star-radio'))

    this.stars.forEach(s => {
      s.addEventListener('click', (e) => {
        const val = parseInt(s.dataset.value, 10)
        this.setRating(val)
      })
      s.addEventListener('mouseenter', () => this.previewStars(parseInt(s.dataset.value, 10)))
    })
    this.container.addEventListener('mouseleave', () => this.previewStars(0))
  }

  setRating(val) {
    // set radio
    const radio = this.radios.find(r => parseInt(r.value, 10) === val)
    if (radio) radio.checked = true
    this.previewStars(val)
  }

  previewStars(val) {
    this.stars.forEach(s => {
      const v = parseInt(s.dataset.value, 10)
      if (v <= val) {
        s.classList.add('text-yellow-400')
      } else {
        s.classList.remove('text-yellow-400')
      }
    })
  }
}
