# Dashboard SQL GROUP BY Fix

## Issue
When viewing dashboards with chart visualizations (pie_chart, bar_chart, line_chart), the following PostgreSQL error occurred:

```
PG::GroupingError: ERROR: column "defects.created_at" must appear in the GROUP BY clause or be used in an aggregate function
```

## Root Cause
The `DashboardDataGenerator` service was calling `.group()` and `.count()` on ActiveRecord relations that had existing `ORDER BY` clauses. In PostgreSQL, when you use `GROUP BY`, any column referenced in the `SELECT` list or `ORDER BY` clause must either:
1. Be included in the `GROUP BY` clause, or
2. Be used in an aggregate function (like COUNT, SUM, AVG, etc.)

Since the defects relation likely had an `ORDER BY created_at DESC` from the base query, this caused the SQL error.

## Solution
Added `.reorder(nil)` before all grouping operations to remove any existing `ORDER BY` clauses before applying `GROUP BY`. This is a Rails method that clears all existing ordering from the query.

## Files Modified

### app/services/dashboard_data_generator.rb
Updated all grouping methods to include `.reorder(nil)`:

1. **group_by_priority**: 
   - Before: `relation.group(:priority).count`
   - After: `relation.reorder(nil).group(:priority).count`

2. **group_by_status**:
   - Before: `relation.joins(:statuses).group('statuses.name').count`
   - After: `relation.reorder(nil).joins(:statuses).group('statuses.name').count`

3. **group_by_module**:
   - Before: `relation.joins(:qa_module).group(...).count`
   - After: `relation.reorder(nil).joins(:qa_module).group(...).count`

4. **group_by_banking_type**:
   - Before: `relation.joins(:banking_type).group(...).count`
   - After: `relation.reorder(nil).joins(:banking_type).group(...).count`

5. **group_by_assignee**:
   - Before: `relation.joins(...).group(...).count`
   - After: `relation.reorder(nil).joins(...).group(...).count`

6. **group_by_date_range**:
   - Before: `relation.group(<<~SQL.squish).count`
   - After: `relation.reorder(nil).group(<<~SQL.squish).count`

## Technical Details

### What is `.reorder(nil)`?
- Rails ActiveRecord method that removes all existing `ORDER BY` clauses from a query
- Essential when using `GROUP BY` with aggregation functions
- Prevents PostgreSQL grouping errors
- Safe to use because:
  - For aggregated data (charts), the ordering is handled after grouping
  - For table/count views, we apply ordering separately in the `generate` method

### Why This Works
When you call `.reorder(nil)`, Rails generates SQL like:
```sql
-- Before (causes error):
SELECT COUNT(*) FROM defects 
WHERE ... 
GROUP BY priority 
ORDER BY created_at DESC

-- After (works correctly):
SELECT COUNT(*) FROM defects 
WHERE ... 
GROUP BY priority
```

The ordering for chart data is then handled in Ruby after the counts are retrieved, using methods like `.sort_by`.

## Testing
After this fix, dashboards with chart visualizations should:
1. Load without SQL errors
2. Display correct aggregated counts
3. Show data in meaningful order (e.g., priorities sorted by severity)

## Related Files
- `app/models/dashboard_widget.rb` - Calls `DashboardDataGenerator`
- `app/models/defect_filter.rb` - Provides the base filtered relation
- `app/controllers/dashboard_widgets_controller.rb` - Handles show action

## Date
November 21, 2025
