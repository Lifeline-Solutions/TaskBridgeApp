# Dashboard System - Quick Reference Guide

## Overview
The Dashboard system allows you to create visual representations of defect data based on saved filters.

## How It Works

### Step 1: Create or Select a Filter
1. Navigate to **Defect Filters** (or create from the Dashboard creation page)
2. Create a filter with your desired criteria:
   - Priority (Severity 1, 2, 3, 4)
   - Status (Open, In Progress, Resolved, etc.)
   - Module/Submodule
   - Banking Type
   - Assignee
   - Date range
   - And more...
3. Save the filter with a descriptive name

### Step 2: Create a Dashboard
1. Go to **Dashboard Widgets** → Click "Create Dashboard"
2. Enter a **Dashboard Name** (e.g., "Critical Issues Dashboard")
3. Select the **Filter** you created in Step 1
4. Choose a **Visualization Type**:

   - **Table** (Default)
     - Shows detailed list of all defects matching the filter
     - Displays: ID, Summary, Priority, Status, Assignees, Module, Created Date
     - Best for: Detailed analysis and review

   - **Pie Chart**
     - Circular chart showing distribution
     - Automatically groups by the main filter parameter
     - Best for: Understanding proportions and distributions

   - **Bar Chart**
     - Vertical bars showing counts
     - Automatically groups by the main filter parameter
     - Best for: Comparing quantities across categories

   - **Line Chart**
     - Trend line visualization
     - Shows data progression
     - Best for: Viewing trends over time

   - **Count**
     - Large number display
     - Shows total count of matching defects
     - Best for: KPI tracking and dashboards

5. (Optional) Set **Auto-Refresh Interval**
   - Minimum: 30 seconds
   - Leave blank for manual refresh only
   - Useful for live monitoring dashboards

6. Click **"Create Dashboard"**

### Step 3: View Your Dashboard
- The dashboard will open automatically after creation
- You'll see:
  - Dashboard header with name and filter
  - Active filter parameters displayed as badges
  - Statistics (visualization type, total records, last updated)
  - The actual visualization based on your selected type
  - Actions: Refresh, Edit, Delete, Back

## How Visualizations Work

### Automatic Grouping (for Charts)
The system automatically determines what to group by based on your filter's active parameters:

- **Priority filter active** → Groups by priority (Severity 1, 2, 3, 4)
- **Status filter active** → Groups by status (Open, Resolved, etc.)
- **Module filter active** → Groups by module
- **Banking Type filter active** → Groups by banking type
- **Assignee filter active** → Groups by assignee
- **No specific filter** → Groups by creation date range

### Example Scenarios

#### Scenario 1: Priority-Based Dashboard
```
Filter: "High Priority Issues"
Parameters:
  - Priority: Severity 1, Severity 2
  - Status: Open

Visualization: Pie Chart
Result: Shows distribution between Severity 1 and Severity 2
```

#### Scenario 2: Module Analysis
```
Filter: "Module Breakdown"
Parameters:
  - Module: All modules
  - Date Range: Last 30 days

Visualization: Bar Chart
Result: Shows count of defects per module
```

#### Scenario 3: Detailed Review
```
Filter: "Unresolved Critical Issues"
Parameters:
  - Priority: Severity 1
  - Status: Open, In Progress

Visualization: Table
Result: Shows detailed list with all defect information
```

#### Scenario 4: KPI Dashboard
```
Filter: "Today's Open Issues"
Parameters:
  - Status: Open
  - Date: Today

Visualization: Count
Result: Shows large number of open issues
Auto-Refresh: Every 60 seconds
```

## Managing Dashboards

### Viewing All Dashboards
- Navigate to **Dashboard Widgets**
- See all your dashboards as cards
- Each card shows:
  - Dashboard name
  - Associated filter
  - Visualization type
  - Active parameters (preview)
  - Last updated time

### Editing a Dashboard
1. Open the dashboard
2. Click **"Edit"** button
3. Change name, filter, visualization type, or auto-refresh
4. Click **"Update Dashboard"**

### Refreshing Data
- **Manual**: Click the "Refresh" button in the dashboard view
- **Automatic**: Set auto-refresh interval when creating/editing

### Deleting a Dashboard
1. Open the dashboard
2. Click **"Delete"** button
3. Confirm deletion

## Tips and Best Practices

### Creating Effective Dashboards

1. **Use Descriptive Names**
   - Good: "Critical Issues by Module - Last 7 Days"
   - Bad: "Dashboard 1"

2. **Match Visualization to Data**
   - Use **Table** for detailed review and export
   - Use **Pie Chart** for proportions (2-8 categories work best)
   - Use **Bar Chart** for comparisons across categories
   - Use **Count** for single metrics and KPIs

3. **Leverage Auto-Refresh**
   - Set 30-60 seconds for live monitoring
   - Set 300+ seconds (5 min) for overview dashboards
   - Leave blank for analysis dashboards (manual refresh)

4. **Create Multiple Perspectives**
   - Same filter, different visualizations
   - Example:
     - "Priority Overview" → Pie Chart
     - "Priority Details" → Table
     - "Priority Count" → Count

5. **Organize Filters Strategically**
   - Create specific filters for different needs
   - Use clear, descriptive filter names
   - Keep filters focused (fewer parameters = clearer visualization)

### Performance Tips

1. **Filter Before Visualizing**
   - Apply filters to reduce dataset size
   - More specific filters = faster dashboards

2. **Use Table for Large Datasets**
   - Tables handle pagination better
   - Charts work best with <50 data points

3. **Set Reasonable Auto-Refresh**
   - Don't set < 30 seconds
   - Consider server load for multiple dashboards

## Common Use Cases

### 1. Executive Dashboard
- **Filter**: "All High Priority Open Issues"
- **Visualization**: Count + Auto-refresh (60s)
- **Purpose**: Monitor critical issues in real-time

### 2. Team Performance Dashboard
- **Filter**: "Issues by Assignee - This Month"
- **Visualization**: Bar Chart
- **Purpose**: See workload distribution

### 3. Module Health Dashboard
- **Filter**: "Open Issues by Module"
- **Visualization**: Pie Chart
- **Purpose**: Identify problem areas

### 4. Daily Review Dashboard
- **Filter**: "Today's Activity"
- **Visualization**: Table
- **Purpose**: Detailed review of daily defects

### 5. Trend Analysis Dashboard
- **Filter**: "Last 30 Days - All Issues"
- **Visualization**: Line Chart
- **Purpose**: See defect trends over time

## Troubleshooting

### No Data Showing
- Check if filter has matching defects
- Verify filter parameters are not too restrictive
- Try clicking "Refresh" button

### Chart Looks Cluttered
- Use a more specific filter to reduce categories
- Consider switching to Table visualization
- Try different grouping by changing filter parameters

### Auto-Refresh Not Working
- Verify refresh interval is ≥ 30 seconds
- Check browser console for errors
- Try manual refresh first

## Keyboard Shortcuts
- **Index Page**: Click card to view dashboard
- **Dashboard View**:
  - Click "Back" to return to index
  - Click "Refresh" to reload data
  - Click "Edit" to modify settings

## Related Features
- **Defect Filters**: Create and manage filters
- **Reports**: Generate detailed reports
- **Defect List**: Browse all defects
