# Team Breach Report Implementation Summary

## Overview
Implemented a comprehensive team breach reporting feature that analyzes SLA breach performance for team members based on ticket assignments tracked via the `events.assigned_user_id` field.

## What Was Implemented

### 1. Controller Method: `team_report_breach`
**Location:** `app/controllers/profiles_controller.rb`

**Features:**
- ✅ Team selection with date range filtering (defaults to last 6 months)
- ✅ Retrieves all tickets assigned to team members (past or current) via `events.assigned_user_id`
- ✅ Filters tickets by creation date within the selected range
- ✅ Calculates breach statistics by status
- ✅ Calculates breach statistics by team member
- ✅ Performance percentage calculation (100% = zero breaches, lower = more breaches)
- ✅ CSV export functionality

**Key Metrics Calculated:**
- Total tickets assigned to team
- Total breached tickets (SLA resolution deadline)
- Overall breach percentage
- Per-status breakdown (total, breached, non-breached, performance %)
- Per-user breakdown (total, breached, non-breached, performance %)

**Performance Score Logic:**
```ruby
breach_rate = (breached_count / total_tickets) * 100
breach_percentage = (100 - breach_rate).round(2)
```
- 100% = Perfect (zero breaches)
- 80-99% = Excellent
- 50-79% = Moderate
- 0-49% = Critical

### 2. View: `team_report_breach.html.erb`
**Location:** `app/views/profiles/team_report_breach.html.erb`

**UI Components:**
- ✅ Filter form with team selection, start date, and end date
- ✅ Summary cards showing:
  - Team name
  - Total tickets
  - Breached tickets count
  - Overall performance score (color-coded)
- ✅ Status breakdown table with:
  - Status name
  - Total tickets per status
  - Non-breached count
  - Breached count
  - Performance % (color-coded badges)
  - Total row at bottom
- ✅ Team member performance table with:
  - User name
  - Total tickets assigned
  - Non-breached count
  - Breached count
  - Performance % (color-coded badges)
- ✅ Legend explaining performance score
- ✅ CSV export button
- ✅ Responsive design using Tailwind CSS
- ✅ Color-coded indicators:
  - Green (80-100%): Excellent
  - Yellow (50-79%): Moderate
  - Red (0-49%): Critical

### 3. CSV Export Helper: `generate_team_breach_csv`
**Location:** `app/controllers/profiles_controller.rb`

**CSV Structure:**
- Header section with team name, totals, and overall performance
- Status breakdown table
- Team member breakdown table

### 4. Route
**Location:** `config/routes.rb` (already existed)
```ruby
get 'team_report_breach', to: 'profiles#team_report_breach', as: 'team_report_breach'
```

**URL:** `/team_report_breach`
**Path Helper:** `team_report_breach_path`

## How It Works

### Data Flow:
1. User selects team and date range
2. System finds all events where `assigned_user_id` matches team member IDs
3. Gets unique ticket IDs from those events
4. Filters tickets by `created_at` within date range
5. Joins with `sla_tickets` to identify breached tickets (`sla_resolution_deadline = 'Breached'`)
6. Aggregates data by status and by user
7. Calculates performance percentages
8. Displays in sortable tables (sorted by breach % - worst performers first)

### Key Queries:
```ruby
# Get tickets assigned to team members
assigned_ticket_ids = Event.where(assigned_user_id: team_member_ids)
                           .where.not(ticket_id: nil)
                           .pluck(:ticket_id)
                           .uniq

# Filter by date range
@tickets = Ticket.where(id: assigned_ticket_ids)
                .where('created_at >= ? AND created_at <= ?', start_date, end_date)

# Get breached tickets
@breached_tickets = @tickets.joins(:sla_tickets)
                            .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
```

## Usage

### Access the Report:
1. Navigate to `/team_report_breach`
2. Select a team from dropdown
3. Choose date range (or use default: last 6 months)
4. Click "Generate Report"
5. Optionally export to CSV

### Understanding the Report:
- **Performance % = (Total - Breached) / Total × 100**
- Higher percentage = better performance
- Tables are sorted by performance % (lowest/worst first)
- Color coding provides quick visual assessment

## Benefits

1. **Accountability:** Track individual team member SLA performance
2. **Trend Analysis:** Compare performance across different time periods
3. **Status Insights:** Identify which ticket statuses have highest breach rates
4. **Data Export:** CSV export for further analysis or reporting
5. **Visual Clarity:** Color-coded metrics for quick assessment
6. **Historical Tracking:** Uses events table to capture past assignments, not just current state

## Dependencies

- Requires `events.assigned_user_id` to be populated (this is handled by the separate Event update scripts)
- Requires `sla_tickets` table with `sla_resolution_deadline` field
- Requires `Team` model with `users` association
- Uses Tailwind CSS for styling

## Notes

- The report uses `events.assigned_user_id` to track historical assignments
- Breach determination is based on `sla_tickets.sla_resolution_deadline = 'Breached'`
- Performance score is inverted (100% - breach_rate) so higher is better
- Team members with zero assigned tickets in the date range are excluded from user table
- Sorting prioritizes worst performers (lowest %) for visibility

## Files Modified/Created

1. **Modified:** `app/controllers/profiles_controller.rb`
   - Added `team_report_breach` method
   - Added `generate_team_breach_csv` helper method

2. **Created:** `app/views/profiles/team_report_breach.html.erb`
   - Full HTML view with tables and filters

3. **Existing:** `config/routes.rb`
   - Route already existed: `get 'team_report_breach'`

