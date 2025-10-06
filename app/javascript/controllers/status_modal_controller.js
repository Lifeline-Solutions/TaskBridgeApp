import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['dropdown', 'modal'];

  connect() {
    // ✅ Bind once and reuse
    this.boundCloseWithKey = this.closeWithKey.bind(this);
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this);

    document.addEventListener('keydown', this.boundCloseWithKey);
    document.addEventListener('click', this.boundCloseOnClickOutside);
  }

  disconnect() {
    // ✅ Use the same references to remove listeners correctly
    document.removeEventListener('keydown', this.boundCloseWithKey);
    document.removeEventListener('click', this.boundCloseOnClickOutside);
  }

  // Status dropdown methods
  toggleDropdown() {
    this.dropdownTarget.classList.toggle('hidden');
  }

  closeDropdown() {
    this.dropdownTarget.classList.add('hidden');
  }

  // Modal methods
  openModal() {
    this.modalTarget.classList.remove('hidden');
    document.body.classList.add('overflow-hidden');
  }

  closeModal() {
    this.modalTarget.classList.add('hidden');
    document.body.classList.remove('overflow-hidden');
  }

  // Close when clicking outside
  closeOnClickOutside(event) {
    if (!this.element.contains(event.target) && !this.modalTarget.contains(event.target)) {
      this.closeDropdown();
      this.closeModal();
    }
  }

  // Close when pressing Escape
  closeWithKey(event) {
    if (event.key === 'Escape') {
      this.closeDropdown();
      this.closeModal();
    }
  }
}