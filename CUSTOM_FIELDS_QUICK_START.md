# Custom Field Dashboard Feature - Quick Start Guide

## What's New?

When creating a QA dashboard, you can now select custom fields to display distribution charts alongside your filter-based metrics. This gives you flexibility to visualize data in multiple ways without creating separate dashboards.

## How to Use

### Step 1: Create or Edit a Dashboard
Navigate to **QA → Dashboards** → **New Dashboard** (or click Edit on existing dashboard)

### Step 2: Fill in Basic Info
- **Dashboard Name**: Give your dashboard a descriptive name
- **Description**: Optional description
- **Data Source**: Select a saved filter (this determines which defects to analyze)

### Step 3: Select Custom Fields (NEW!)
Scroll down to the **"Custom Field Distributions (Optional)"** section

Check any fields you'd like to visualize:
- ✓ **Status** - See how many defects in each status
- ✓ **Priority** - Distribution across severity levels
- ✓ **Assignee** - See which team members have the most work
- ✓ **Reporter** - Track who found the most issues
- ✓ **QA Module** - Distribution across modules
- ✓ **Submodule** - Distribution across submodules
- ✓ **Banking Type** - Banking type breakdown
- ✓ **Label** - Distribution across labels
- ✓ **Ageing** - See how old issues are

### Step 4: Save
Click **"Create Dashboard"** or **"Update Dashboard"**

### Step 5: View Your Dashboard
Your dashboard now displays:
1. **Filter-based distributions** (top) - Automatically generated based on active filter parameters
2. **Custom field distributions** (bottom) - Charts for each field you selected

## Examples

### Example 1: Status & Priority Dashboard
- **Filter**: ISP project defects created in last 30 days
- **Custom Fields**: Status, Priority
- **Result**: See how defects are distributed across statuses and priority levels

### Example 2: Team Workload Dashboard
- **Filter**: All open defects
- **Custom Fields**: Assignee, Reporter, Ageing
- **Result**: Understand team distribution, who's reporting issues, and age of defects

### Example 3: Module Health Dashboard
- **Filter**: All defects
- **Custom Fields**: QA Module, Submodule, Banking Type
- **Result**: See which modules/banking types have the most issues

## Feature Details

### Distribution Charts Display
Each selected field shows:
- **Pie Chart**: Visual representation of the distribution
- **Breakdown Table**: List of values with counts and percentages
- **Color Coded**: Different colors for easy distinction

### Data Calculation
- Charts are calculated on the fly when viewing the dashboard
- Uses all defects matching your selected filter
- Counts are accurate in real-time

### Performance
- Efficiently uses database indexing
- Scales well with large datasets
- Auto-refresh optional (configurable in settings)

## Tips & Best Practices

### ✓ Do
- Select 3-5 custom fields for best visual clarity
- Use the same dashboard for related metrics (e.g., Status + Priority)
- Update custom fields as your tracking needs change
- Combine with date filters for trend analysis

### ✗ Don't
- Select too many fields at once (becomes cluttered)
- Expect real-time updates without auto-refresh
- Use on very large datasets without date filtering

## Troubleshooting

**Q: Dashboard shows "No Data"**
- A: Your selected filter has no active parameters. Edit the filter to add criteria.

**Q: Custom field charts not showing**
- A: The selected field may have no data in your filtered dataset. Check your filter parameters.

**Q: Charts look cluttered**
- A: Try selecting fewer fields or use different filters for different dashboards.

## Available Fields Explained

| Field | Description | Use Case |
|-------|-------------|----------|
| Status | Current status of defect | Track workflow progress |
| Priority | Severity level (1-4) | Understand criticality |
| Assignee | Who it's assigned to | Team workload analysis |
| Reporter | Who found the issue | Identify top reporters |
| QA Module | Which module it's in | Module health check |
| Submodule | Specific submodule | Deep-dive analysis |
| Banking Type | Banking type (if applicable) | Banking domain tracking |
| Label | Custom labels | Custom categorization |
| Ageing | Age of defect | Identify old issues |

## Need Help?

For detailed technical documentation, see: `CUSTOM_FIELDS_DASHBOARD_FEATURE.md`
