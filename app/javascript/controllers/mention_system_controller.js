import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "dropdown", "input"]
  static values = { 
    defectId: String
  }

  connect() {
    this.isOpen = false
    this.currentMentionType = null
    this.currentQuery = ""
    this.mentionStartPosition = null
    this.selectedIndex = 0
    this.cachedUsers = []
    this.cachedDefects = []
    this.trixEditor = null
    
    this.setupTrixEditor()
    this.setupClickOutside()
  }

  setupTrixEditor() {
    // Find the actual Trix editor element
    const trixEditor = this.element.querySelector('trix-editor')
    if (trixEditor) {
      this.trixEditor = trixEditor
      
      // Use a debounced approach to avoid interrupting typing
      this.mentionCheckTimer = null
      
      // Listen to Trix-specific events with debouncing
      trixEditor.addEventListener('trix-change', this.debouncedMentionCheck.bind(this))
      trixEditor.addEventListener('keydown', this.handleKeyDown.bind(this))
    } else {
      // Fallback for regular editors
      if (this.hasEditorTarget) {
        this.editorTarget.addEventListener('keyup', this.debouncedMentionCheck.bind(this))
        this.editorTarget.addEventListener('keydown', this.handleKeyDown.bind(this))
      } else if (this.hasInputTarget) {
        // Handle regular input elements (like the defect search input)
        this.inputTarget.addEventListener('keyup', this.debouncedMentionCheck.bind(this))
        this.inputTarget.addEventListener('keydown', this.handleKeyDown.bind(this))
      }
    }
  }

  debouncedMentionCheck() {
    // Clear previous timer
    if (this.mentionCheckTimer) {
      clearTimeout(this.mentionCheckTimer)
    }
    
    // Set a new timer - this prevents interrupting rapid typing
    this.mentionCheckTimer = setTimeout(() => {
      this.checkForMentions()
    }, 150) // 150ms delay to allow natural typing
  }

  handleKeyDown(event) {
    if (!this.isOpen) {
      // If dropdown is not open, let normal processing happen
      return
    }

    // Only intercept navigation keys when dropdown is open
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault()
        this.moveSelection(1)
        break
      case 'ArrowUp':
        event.preventDefault()
        this.moveSelection(-1)
        break
      case 'Enter':
      case 'Tab':
        event.preventDefault()
        this.selectCurrentItem()
        break
      case 'Escape':
        event.preventDefault()
        this.closeMentionDropdown()
        break
    }
  }

  checkForMentions() {
    if (!this.trixEditor) {
      if (this.hasInputTarget) {
        this.checkForMentionsInInput()
      } else {
        this.checkForMentionsInRegularEditor()
      }
      return
    }
    
    const editor = this.trixEditor.editor
    if (!editor) return
    
    const position = editor.getPosition()
    const document = editor.getDocument()
    const text = document.toString()
    
    // Find the current text before cursor
    const textBeforeCursor = text.substring(0, position)
    
    // Check for @ mentions
    const atMatch = this.findMentionTrigger(textBeforeCursor, '@')
    if (atMatch) {
      this.currentMentionType = 'user'
      this.currentQuery = atMatch.query
      this.mentionStartPosition = atMatch.startPosition
      this.fetchUsers(atMatch.query).then(users => this.showMentionDropdown(users))
      return
    }

    // Check for # mentions  
    const hashMatch = this.findMentionTrigger(textBeforeCursor, '#')
    if (hashMatch) {
      this.currentMentionType = 'defect'
      this.currentQuery = hashMatch.query
      this.mentionStartPosition = hashMatch.startPosition
      this.fetchDefects(hashMatch.query).then(defects => this.showMentionDropdown(defects))
      return
    }

    // Close dropdown if no mention found
    if (this.isOpen) {
      this.closeMentionDropdown()
    }
  }

  findMentionTrigger(text, trigger) {
    // Find the last occurrence of trigger
    const lastTriggerIndex = text.lastIndexOf(trigger)
    
    if (lastTriggerIndex === -1) return null
    
    // Check if trigger is at start or preceded by whitespace
    if (lastTriggerIndex > 0 && !/\s/.test(text[lastTriggerIndex - 1])) {
      return null
    }
    
    // Get text after trigger
    const afterTrigger = text.substring(lastTriggerIndex + 1)
    
    // Check if there's whitespace after trigger (which means mention is complete)
    if (/\s/.test(afterTrigger)) return null
    
    return {
      startPosition: lastTriggerIndex,
      query: afterTrigger,
      trigger: trigger
    }
  }

  checkForMentionsInInput() {
    if (!this.hasInputTarget) return
    
    const input = this.inputTarget
    const text = input.value
    const cursorPos = input.selectionStart

    // Check for @ mention (users)
    const atMatch = this.findMentionTriggerInText(text, cursorPos, '@')
    if (atMatch) {
      this.currentMentionType = 'user'
      this.currentQuery = atMatch.query
      this.fetchUsers(atMatch.query).then(users => this.showMentionDropdown(users))
      return
    }

    // Check for # defect reference
    const hashMatch = this.findMentionTriggerInText(text, cursorPos, '#')
    if (hashMatch) {
      this.currentMentionType = 'defect'
      this.currentQuery = hashMatch.query
      this.fetchDefects(hashMatch.query).then(defects => this.showMentionDropdown(defects))
      return
    }

    // Close dropdown if no mention found
    if (this.isOpen) {
      this.closeMentionDropdown()
    }
  }

  checkForMentionsInRegularEditor() {
    if (!this.hasEditorTarget || this.trixEditor) return
    
    const selection = window.getSelection()
    if (selection.rangeCount === 0) return

    const range = selection.getRangeAt(0)
    const textNode = range.startContainer
    
    if (textNode.nodeType !== Node.TEXT_NODE) return

    const text = textNode.textContent
    const cursorPos = range.startOffset

    // Check for @ mention (users)
    const atMatch = this.findMentionTriggerInText(text, cursorPos, '@')
    if (atMatch) {
      this.currentMentionType = 'user'
      this.currentQuery = atMatch.query
      this.fetchUsers(atMatch.query).then(users => this.showMentionDropdown(users))
      return
    }

    // Check for # defect reference
    const hashMatch = this.findMentionTriggerInText(text, cursorPos, '#')
    if (hashMatch) {
      this.currentMentionType = 'defect'
      this.currentQuery = hashMatch.query
      this.fetchDefects(hashMatch.query).then(defects => this.showMentionDropdown(defects))
      return
    }

    // Close dropdown if no mention found
    if (this.isOpen) {
      this.closeMentionDropdown()
    }
  }

  findMentionTriggerInText(text, cursorPos, trigger) {
    // Find the last occurrence of trigger before cursor
    let triggerPos = -1
    for (let i = cursorPos - 1; i >= 0; i--) {
      if (text[i] === trigger) {
        // Check if it's at start or preceded by whitespace
        if (i === 0 || /\s/.test(text[i - 1])) {
          triggerPos = i
          break
        }
      } else if (/\s/.test(text[i])) {
        // Stop at whitespace
        break
      }
    }

    if (triggerPos === -1) return null

    const query = text.slice(triggerPos + 1, cursorPos)
    // Don't show dropdown for whitespace in query
    if (/\s/.test(query)) return null

    return {
      start: triggerPos,
      query: query
    }
  }

  async fetchUsers(query = '') {
    try {
      const url = new URL('/mention/users', window.location.origin)
      url.searchParams.append('query', query)
      url.searchParams.append('defect_id', this.defectIdValue)
      
      const response = await fetch(url, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (!response.ok) throw new Error('Failed to fetch users')
      
      const users = await response.json()
      this.cachedUsers = users
      return users
    } catch (error) {
      console.error('Error fetching users:', error)
      return []
    }
  }

  async fetchDefects(query = '') {
    try {
      // Always use the mention defects endpoint for consistent behavior
      const url = new URL('/mention/defects', window.location.origin)
      url.searchParams.append('query', query)
      url.searchParams.append('current_defect_id', this.defectIdValue)
      
      const response = await fetch(url, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (!response.ok) throw new Error('Failed to fetch defects')
      
      const defects = await response.json()
      this.cachedDefects = defects
      return defects
    } catch (error) {
      console.error('Error fetching defects:', error)
      return []
    }
  }

  showMentionDropdown(items) {
    if (items.length === 0) {
      this.closeMentionDropdown()
      return
    }

    this.selectedIndex = 0
    this.renderDropdown(items)
    this.positionDropdown()
    this.isOpen = true
    this.dropdownTarget.classList.remove('hidden')
    this.dropdownTarget.style.display = 'block'
  }

  renderDropdown(items) {
    const html = items.map((item, index) => {
      if (this.currentMentionType === 'user') {
        return `
          <div class="mention-item ${index === this.selectedIndex ? 'selected' : ''}" 
               data-index="${index}" 
               data-action="click->mention-system#selectItem"
               data-id="${item.id}"
               data-name="${item.name}"
               data-type="user">
            <div class="flex items-center space-x-2 p-2 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer">
              <div class="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center text-white text-xs">
                ${item.name.charAt(0).toUpperCase()}
              </div>
              <div>
                <div class="font-medium text-gray-900 dark:text-white">${item.name}</div>
                <div class="text-xs text-gray-500 dark:text-gray-400">${item.email}</div>
              </div>
            </div>
          </div>
        `
      } else {
        return `
          <div class="mention-item ${index === this.selectedIndex ? 'selected' : ''}" 
               data-index="${index}" 
               data-action="click->mention-system#selectItem"
               data-id="${item.id}"
               data-name="${item.defect_unique}"
               data-summary="${item.summary}"
               data-type="defect">
            <div class="flex items-center space-x-2 p-2 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer">
              <div class="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center text-white text-xs">
                #
              </div>
              <div>
                <div class="font-medium text-gray-900 dark:text-white">${item.defect_unique}</div>
                <div class="text-xs text-gray-500 dark:text-gray-400">${item.summary}</div>
              </div>
            </div>
          </div>
        `
      }
    }).join('')

    this.dropdownTarget.innerHTML = html
  }

  positionDropdown() {
    let targetElement = null
    
    if (this.trixEditor) {
      targetElement = this.trixEditor
    } else if (this.hasInputTarget) {
      targetElement = this.inputTarget
    } else if (this.hasEditorTarget) {
      targetElement = this.editorTarget
    }
    
    if (!targetElement) return

    // Get the current selection position to place dropdown
    const rect = targetElement.getBoundingClientRect()
    const editorRect = this.element.getBoundingClientRect()

    this.dropdownTarget.style.position = 'absolute'
    this.dropdownTarget.style.left = `10px`
    this.dropdownTarget.style.top = `${rect.bottom - editorRect.top + 5}px`
    this.dropdownTarget.style.zIndex = '1000'
  }

  moveSelection(direction) {
    const items = this.dropdownTarget.querySelectorAll('.mention-item')
    if (items.length === 0) return

    // Remove current selection
    items[this.selectedIndex]?.classList.remove('selected')

    // Update selected index
    this.selectedIndex += direction
    if (this.selectedIndex < 0) this.selectedIndex = items.length - 1
    if (this.selectedIndex >= items.length) this.selectedIndex = 0

    // Add new selection
    items[this.selectedIndex]?.classList.add('selected')
    items[this.selectedIndex]?.scrollIntoView({ block: 'nearest' })
  }

  selectItem(event) {
    const item = event.currentTarget
    const id = item.dataset.id
    const name = item.dataset.name
    const summary = item.dataset.summary
    const type = item.dataset.type

    // Check if this is being used in a linking context (has special target)
    if (this.hasInputTarget && this.inputTarget.id === 'defectSearchInput') {
      // Emit custom event for linking modal
      const customEvent = new CustomEvent('mention:selected', {
        detail: { 
          id: id, 
          defect_unique: name, 
          summary: summary,
          type: type 
        },
        bubbles: true
      });
      this.inputTarget.dispatchEvent(customEvent);
      this.closeMentionDropdown();
      return;
    }

    this.insertMention(id, name, type, summary)
    this.closeMentionDropdown()
  }

  selectCurrentItem() {
    const selectedItem = this.dropdownTarget.querySelector('.mention-item.selected')
    if (selectedItem) {
      this.selectItem({ currentTarget: selectedItem })
    }
  }

  insertMention(id, name, type, summary = null) {
    if (!this.trixEditor || this.mentionStartPosition === null) return

    const editor = this.trixEditor.editor
    const document = editor.getDocument()
    const currentPosition = editor.getPosition()
    
    // Calculate positions
    const startPos = this.mentionStartPosition
    const endPos = currentPosition
    
    // Create the mention text - include summary for defects
    let mentionText
    if (type === 'user') {
      mentionText = `@${name}`
    } else {
      // For defects, include summary if available
      mentionText = summary ? `#${name}: ${summary}` : `#${name}`
    }
    
    // Replace the trigger and query text with the mention
    editor.setSelectedRange([startPos, endPos])
    
    // Insert the mention as a link with special attributes
    const mentionAttributes = {
      href: type === 'user' ? `/users/${id}` : `/defect/${id}`,
      'data-mention-id': id,
      'data-mention-type': type,
      'class': `mention mention-${type}`,
      'contenteditable': 'false'
    }
    
    editor.insertHTML(`<a ${Object.entries(mentionAttributes).map(([key, value]) => `${key}="${value}"`).join(' ')}>${mentionText}</a>&nbsp;`)
    
    // Focus back on editor
    this.trixEditor.focus()
  }

  closeMentionDropdown() {
    this.isOpen = false
    this.currentMentionType = null
    this.currentQuery = ""
    this.mentionStartPosition = null
    this.selectedIndex = 0
    this.dropdownTarget.classList.add('hidden')
    this.dropdownTarget.style.display = 'none'
    this.dropdownTarget.innerHTML = ''
  }

  setupClickOutside() {
    document.addEventListener('click', (event) => {
      if (this.isOpen && !this.element.contains(event.target)) {
        this.closeMentionDropdown()
      }
    })
  }

  // Helper method to extract mentions from content before form submission
  extractMentions() {
    const mentions = []
    const mentionElements = this.element.querySelectorAll('[data-mention-id]')
    
    mentionElements.forEach(element => {
      mentions.push({
        id: element.dataset.mentionId,
        type: element.dataset.mentionType,
        name: element.textContent
      })
    })

    // Add mentions data to a hidden input for form submission
    if (this.hasInputTarget) {
      this.inputTarget.value = JSON.stringify(mentions)
    }

    return mentions
  }

  // Method called before form submission
  beforeSubmit(event) {
    const mentions = this.extractMentions()
    return mentions
  }
}