import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['modalContainer'];

  connect() {
    document.body.classList.add('overflow-hidden');

    // ✅ Bind once and store references
    this.boundCloseWithKey = this.closeWithKey.bind(this);
    this.boundCloseOnClickOutside = this.closeOnBackdrop.bind(this);
    this.boundTrapFocus = this.trapFocus.bind(this);

    document.addEventListener('keydown', this.boundCloseWithKey);
    // this.element.addEventListener('click', this.boundCloseOnClickOutside);

    document.addEventListener('keydown', this.boundTrapFocus, true);

    // Initial focus
    this.focusFirstElement();
  }

  disconnect() {
    document.body.classList.remove('overflow-hidden');

    // ✅ Use stored reference when removing
    document.removeEventListener('keydown', this.boundCloseWithKey);
    // this.element.removeEventListener('click', this.boundCloseOnClickOutside);
    document.removeEventListener('keydown', this.boundTrapFocus, true);
  }

  async close() {
    const panel = this.element.querySelector('.fixed.inset-y-0.right-0');
    if (panel) panel.classList.add('slide-out');

    await new Promise((resolve) => setTimeout(resolve, 300));

    this.element.remove();
    const frame = this.element.closest('turbo-frame');
    if (frame) frame.removeAttribute('src');
  }

  closeOnClickOutside(event) {
    if (event.target === this.element) {
      this.close();
    }
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) {
      this.close();
    }
  }

  closeWithKey(event) {
    if (event.key === 'Escape') {
      event.preventDefault();
      this.close();
    }
  }

  focusableSelectors() {
    return [
      'a[href]','area[href]','input:not([disabled])','select:not([disabled])',
      'textarea:not([disabled])','button:not([disabled])','iframe','object','embed',
      '[contenteditable]','[tabindex]:not([tabindex="-1"])'
    ].join(',');
  }

  focusFirstElement() {
    const focusables = this.element.querySelectorAll(this.focusableSelectors());
    if (focusables.length) {
      focusables[0].focus();
    } else {
      this.element.setAttribute('tabindex','-1');
      this.element.focus();
    }
  }

  trapFocus(event) {
    if (event.key !== 'Tab') return;
    const focusables = Array.from(this.element.querySelectorAll(this.focusableSelectors())).filter(el => el.offsetParent !== null);
    if (!focusables.length) return;
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }
}