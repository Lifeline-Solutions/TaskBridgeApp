import { Controller } from "@hotwired/stimulus"
// Ensure Chart.js is loaded globally or via import map. 
// Assuming it's available via window.Chart or previously loaded script tag as seen in application.html.erb

export default class extends Controller {
    static values = {
        type: String,
        labels: Array,
        data: Array,
        grouping: String
    }

    connect() {
        this.renderChart()
    }

    disconnect() {
        if (this.chart) {
            this.chart.destroy()
        }
    }

    renderChart() {
        const ctx = this.element.getContext('2d')

        // Default colors matching Tailwind classes roughly
        const colors = [
            '#4F46E5', // indigo-600
            '#10B981', // emerald-500
            '#F59E0B', // amber-500
            '#EF4444', // red-500
            '#3B82F6', // blue-500
            '#8B5CF6', // violet-500
            '#EC4899', // pink-500
            '#6366F1'  // indigo-500
        ]

        const config = {
            type: this.typeValue,
            data: {
                labels: this.labelsValue,
                datasets: [{
                    label: 'Count',
                    data: this.dataValue,
                    backgroundColor: colors.slice(0, this.dataValue.length),
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                onClick: (event, elements) => {
                    if (elements.length > 0) {
                        const index = elements[0].index
                        const label = this.labelsValue[index]
                        this.handleDrillDown(label)
                    }
                },
                plugins: {
                    legend: {
                        display: this.typeValue === 'pie' || this.typeValue === 'doughnut',
                        position: 'bottom'
                    }
                },
                scales: (this.typeValue === 'bar' || this.typeValue === 'line') ? {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            stepSize: 1
                        }
                    }
                } : {}
            }
        }

        // Check if Chart is available globally (from CDN in layout)
        if (typeof Chart !== 'undefined') {
            this.chart = new Chart(ctx, config)
        } else {
            console.error("Chart.js library not found")
            // Fallback text rendering if needed?
        }
    }

    handleDrillDown(label) {
        const grouping = this.groupingValue
        let params = new URLSearchParams()

        // Always adding filter_open=true to ensure filters are visible on destination
        params.set('filter_open', 'true')

        switch (grouping) {
            case 'status':
                params.set('status[]', label)
                break
            case 'priority':
                params.set('priority[]', label)
                break
            case 'assignee':
                // Assignee grouping currently returns names strings like "John Doe"
                // We can use the text search as fallback since we don't have IDs in the chart data
                params.set('query', label)
                break
            case 'created_date':
                // Label format expected: "YYYY-MM-DD" or similar
                // We can set start_date and end_date to this day
                if (Date.parse(label)) {
                    params.set('start_date', label)
                    params.set('end_date', label)
                }
                break
            default:
                // Default to text search
                params.set('query', label)
        }

        // Redirect to Defects Index
        // Assume route is /defect
        window.location.href = `/defect?${params.toString()}`
    }
}
