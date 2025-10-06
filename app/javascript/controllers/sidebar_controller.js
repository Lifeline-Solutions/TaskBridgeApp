import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "logo", "mainMenuHeading"]
  static values = { collapsed: Boolean }
  
  connect() {
    this.initializeSidebarState()
    this.setupEventListeners()
  }

  initializeSidebarState() {
    // Get stored state from localStorage, default to collapsed on mobile
    const storedState = localStorage.getItem('sidebarCollapsed')
    const isMobile = window.innerWidth < 1024
    
    // If no stored state, use default: collapsed on mobile, expanded on desktop
    const shouldCollapse = storedState !== null ? storedState === 'true' : isMobile
    
    if (shouldCollapse) {
      this.collapseSidebar(false) // false = don't save to localStorage during init
    } else {
      this.expandSidebar(false) // false = don't save to localStorage during init
    }
  }

  setupEventListeners() {
    // Handle window resize for responsiveness
    window.addEventListener('resize', () => {
      this.removeTooltip()
      
      if (window.innerWidth < 1024 && !this.isCollapsed()) {
        // On mobile, auto-collapse if expanded
        this.collapseSidebar()
      } else if (window.innerWidth >= 1024) {
        // On desktop, hide backdrop if visible
        if (this.hasBackdropTarget && !this.backdropTarget.classList.contains('hidden')) {
          this.backdropTarget.classList.add('hidden')
        }
        // Ensure main content margin is correct on resize
        this.updateMainContentMargin()
      }
    })

    // Close sidebar when clicking backdrop on mobile
    if (this.hasBackdropTarget) {
      this.backdropTarget.addEventListener('click', () => {
        if (window.innerWidth < 1024) {
          this.collapseSidebar()
        }
      })
    }
  }

  toggle() {
    if (this.isCollapsed()) {
      this.expandSidebar()
    } else {
      this.collapseSidebar()
    }
  }

  expandSidebar(saveState = true) {
    const sidebarMain = this.element
    
    sidebarMain.classList.remove('w-16')
    sidebarMain.classList.add('w-64')
    
    // Show backdrop on mobile
    if (window.innerWidth < 1024 && this.hasBackdropTarget) {
      this.backdropTarget.classList.remove('hidden')
    }
    
    // Remove any existing tooltips
    this.removeTooltip()
    
    // Update main content margin only on desktop
    if (window.innerWidth >= 1024) {
      this.updateMainContentMargin()
    }
    
    // Show logo container
    if (this.hasLogoTarget) {
      this.logoTarget.classList.remove('hidden')
    }
    
    // Show main menu heading
    if (this.hasMainMenuHeadingTarget) {
      this.mainMenuHeadingTarget.classList.remove('hidden')
    }
    
    // Show all menu items
    const menuItems = document.querySelectorAll('#sidebar > ul')
    menuItems.forEach(menu => {
      menu.classList.remove('hidden')
    })
    
    // Show all text labels
    const textElements = document.querySelectorAll('#sidebar-wrapper .whitespace-nowrap')
    textElements.forEach(el => el.classList.remove('hidden'))
    
    // Show counters
    const counters = document.querySelectorAll('#sidebar-wrapper .rounded-full')
    counters.forEach(counter => counter.classList.remove('hidden'))
    
    // Save state to localStorage
    if (saveState) {
      localStorage.setItem('sidebarCollapsed', 'false')
    }
  }

  collapseSidebar(saveState = true) {
    const sidebarMain = this.element
    
    sidebarMain.classList.remove('w-64')
    sidebarMain.classList.add('w-16')
    
    // Hide backdrop
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.add('hidden')
    }
    
    // Update main content margin only on desktop
    if (window.innerWidth >= 1024) {
      this.updateMainContentMargin()
    }
    
    // Hide dropdown menu if it's currently visible
    const dropdownMenu = document.getElementById('dropdownMenu')
    if (dropdownMenu && !dropdownMenu.classList.contains('hidden')) {
      dropdownMenu.classList.add('hidden')
    }
    
    // Hide logo container completely
    if (this.hasLogoTarget) {
      this.logoTarget.classList.add('hidden')
    }
    
    // Hide main menu heading
    if (this.hasMainMenuHeadingTarget) {
      this.mainMenuHeadingTarget.classList.add('hidden')
    }
    
    // Hide all text labels and counters, but keep icons visible
    const textElements = document.querySelectorAll('#sidebar-wrapper .whitespace-nowrap')
    textElements.forEach(el => el.classList.add('hidden'))
    const counters = document.querySelectorAll('#sidebar-wrapper .rounded-full')
    counters.forEach(counter => counter.classList.add('hidden'))
    
    // Show all menu items (so icons remain visible)
    const menuItems = document.querySelectorAll('#sidebar > ul')
    menuItems.forEach(menu => {
      menu.classList.remove('hidden')
      // Add tooltip listeners to main menu items
      const menuLinks = menu.querySelectorAll('li .group')
      menuLinks.forEach(link => {
        this.addTooltipToElement(link)
      })
    })
    
    // Add tooltip to dropdown button
    const dropdownBtn = document.querySelector('.relative.group .flex.items-center')
    if (dropdownBtn) {
      this.addTooltipToElement(dropdownBtn)
    }
    
    // Save state to localStorage
    if (saveState) {
      localStorage.setItem('sidebarCollapsed', 'true')
    }
  }

  isCollapsed() {
    return this.element.classList.contains('w-16')
  }

  updateMainContentMargin() {
    const mainContent = document.getElementById('mainContent')
    if (mainContent) {
      if (this.isCollapsed()) {
        mainContent.style.marginLeft = '4rem' // 64px
      } else {
        mainContent.style.marginLeft = '16rem' // 256px
      }
    }
  }

  // Tooltip functionality
  createTooltip(text, targetElement) {
    // Remove any existing tooltip
    this.removeTooltip()
    
    const tooltip = document.createElement('div')
    tooltip.className = 'fixed bg-gray-800 text-white px-3 py-2 rounded-md shadow-lg z-50 text-sm whitespace-nowrap pointer-events-none'
    tooltip.textContent = text
    tooltip.id = 'sidebar-tooltip'
    
    // Position tooltip to the right of the sidebar
    const rect = targetElement.getBoundingClientRect()
    tooltip.style.left = (rect.right + 8) + 'px'
    tooltip.style.top = (rect.top + (rect.height / 2) - 12) + 'px'
    
    document.body.appendChild(tooltip)
  }
  
  removeTooltip() {
    const tooltip = document.getElementById('sidebar-tooltip')
    if (tooltip) {
      tooltip.remove()
    }
  }

  addTooltipToElement(element) {
    element.addEventListener('mouseenter', (e) => {
      if (this.isCollapsed()) { // Only show tooltip when collapsed
        const span = element.querySelector('.whitespace-nowrap')
        if (span) {
          this.createTooltip(span.textContent.trim(), element)
        }
      }
    })
    
    element.addEventListener('mouseleave', () => {
      this.removeTooltip()
    })
  }
}