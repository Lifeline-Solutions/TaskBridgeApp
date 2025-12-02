import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "suggestions"]

    connect() {
        this.timeout = null
        this.selectedIndex = -1

        // Close suggestions when clicking outside
        this.clickOutside = this.clickOutside.bind(this)
        document.addEventListener('click', this.clickOutside)
    }

    disconnect() {
        document.removeEventListener('click', this.clickOutside)
        if (this.timeout) {
            clearTimeout(this.timeout)
        }
    }

    handleInput(event) {
        const query = event.target.value.trim()

        // Clear previous timeout
        if (this.timeout) {
            clearTimeout(this.timeout)
        }

        // Hide suggestions if query is empty
        if (query.length < 1) {
            this.hideSuggestions()
            return
        }

        // Debounce the search
        this.timeout = setTimeout(() => {
            this.fetchSuggestions(query)
        }, 300)
    }

    handleKeydown(event) {
        const { key } = event

        // Handle arrow keys for navigation
        if (key === 'ArrowDown') {
            event.preventDefault()
            this.navigateDown()
        } else if (key === 'ArrowUp') {
            event.preventDefault()
            this.navigateUp()
        } else if (key === 'Enter') {
            // If a suggestion is selected, navigate to it
            if (this.selectedIndex >= 0) {
                event.preventDefault()
                this.selectCurrent()
            }
            // Otherwise, let the form submit normally
        } else if (key === 'Escape') {
            this.hideSuggestions()
        }
    }

    async fetchSuggestions(query) {
        try {
            const response = await fetch(`/search/autocomplete?query=${encodeURIComponent(query)}`, {
                headers: {
                    'Accept': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            })

            if (!response.ok) {
                throw new Error('Search request failed')
            }

            const suggestions = await response.json()
            this.displaySuggestions(suggestions)
        } catch (error) {
            console.error('Error fetching suggestions:', error)
            this.hideSuggestions()
        }
    }

    displaySuggestions(suggestions) {
        if (!suggestions || suggestions.length === 0) {
            this.hideSuggestions()
            return
        }

        this.selectedIndex = -1
        const html = suggestions.map((suggestion, index) => this.renderSuggestion(suggestion, index)).join('')

        this.suggestionsTarget.innerHTML = html
        this.suggestionsTarget.classList.remove('hidden')
    }

    renderSuggestion(suggestion, index) {
        const typeColor = suggestion.type === 'ticket' ? 'blue' : 'red'
        const typeIcon = suggestion.type === 'ticket'
            ? '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/></svg>'
            : '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>'

        const location = suggestion.type === 'ticket' ? suggestion.project : suggestion.product

        return `
      <a href="${suggestion.url}" 
         class="block px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 border-b border-gray-100 dark:border-gray-600 last:border-b-0 suggestion-item"
         data-index="${index}"
         data-action="click->global-search#selectSuggestion">
        <div class="flex items-start gap-3">
          <div class="flex-shrink-0 mt-1 text-${typeColor}-600 dark:text-${typeColor}-400">
            ${typeIcon}
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-${typeColor}-100 text-${typeColor}-800 dark:bg-${typeColor}-900 dark:text-${typeColor}-200">
                ${suggestion.key}
              </span>
              <span class="text-xs text-gray-500 dark:text-gray-400">${suggestion.type}</span>
            </div>
            <p class="text-sm font-medium text-gray-900 dark:text-white truncate">
              ${this.escapeHtml(suggestion.title)}
            </p>
            ${location ? `<p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">${this.escapeHtml(location)}</p>` : ''}
          </div>
        </div>
      </a>
    `
    }

    navigateDown() {
        const items = this.suggestionsTarget.querySelectorAll('.suggestion-item')
        if (items.length === 0) return

        this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
        this.updateSelection(items)
    }

    navigateUp() {
        const items = this.suggestionsTarget.querySelectorAll('.suggestion-item')
        if (items.length === 0) return

        this.selectedIndex = Math.max(this.selectedIndex - 1, -1)
        this.updateSelection(items)
    }

    updateSelection(items) {
        items.forEach((item, index) => {
            if (index === this.selectedIndex) {
                item.classList.add('bg-gray-100', 'dark:bg-gray-700')
            } else {
                item.classList.remove('bg-gray-100', 'dark:bg-gray-700')
            }
        })
    }

    selectCurrent() {
        const items = this.suggestionsTarget.querySelectorAll('.suggestion-item')
        if (this.selectedIndex >= 0 && items[this.selectedIndex]) {
            items[this.selectedIndex].click()
        }
    }

    selectSuggestion(event) {
        // Let the link handle navigation
        this.hideSuggestions()
    }

    hideSuggestions() {
        this.suggestionsTarget.classList.add('hidden')
        this.suggestionsTarget.innerHTML = ''
        this.selectedIndex = -1
    }

    clickOutside(event) {
        if (!this.element.contains(event.target)) {
            this.hideSuggestions()
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div')
        div.textContent = text
        return div.innerHTML
    }
}
