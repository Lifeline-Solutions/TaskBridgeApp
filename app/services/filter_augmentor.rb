# frozen_string_literal: true

# FilterAugmentor - Merges saved filters with temporary dashboard/page filters
#
# Usage:
#   merged_rules = FilterAugmentor.merge(saved_filter, params)
#   defects = DefectQueryBuilder.new.apply_rules(merged_rules)
#
class FilterAugmentor
  # Merge a saved filter with request parameters
  # @param saved_filter [DefectFilter, nil] The saved filter (can be nil)
  # @param params [ActionController::Parameters, Hash] Request parameters
  # @return [Hash] Merged filter rules
  def self.merge(saved_filter, params)
    return extract_filter_params(params) if saved_filter.blank?

    base_rules = saved_filter.filter_rules.presence || saved_filter.filters || {}
    param_rules = extract_filter_params(params)

    # If both use new format (with 'conditions'), merge as condition groups
    if has_conditions?(base_rules) && has_conditions?(param_rules)
      merge_condition_groups(base_rules, param_rules)
    elsif has_conditions?(base_rules)
      # Base is new format, params are legacy - convert params to new format
      merge_condition_groups(base_rules, legacy_to_new_format(param_rules))
    elsif has_conditions?(param_rules)
      # Params are new format, base is legacy
      merge_condition_groups(legacy_to_new_format(base_rules), param_rules)
    else
      # Both legacy format - simple merge
      base_rules.deep_merge(param_rules)
    end
  end

  # Extract filter parameters from request params
  # @param params [ActionController::Parameters, Hash]
  # @return [Hash]
  def self.extract_filter_params(params)
    params = params.to_unsafe_h if params.respond_to?(:to_unsafe_h)
    params = params.with_indifferent_access

    allowed_keys = DefectFilter::ALLOWED_FILTER_KEYS
    params.slice(*allowed_keys).reject { |_k, v| v.blank? }
  end

  # Check if rules use new condition-based format
  def self.has_conditions?(rules)
    rules.is_a?(Hash) && (rules['conditions'] || rules[:conditions])
  end

  # Merge two condition groups with AND operator
  def self.merge_condition_groups(base, additional)
    {
      'operator' => 'AND',
      'conditions' => [base, additional]
    }
  end

  # Convert legacy filter format to new condition-based format
  # @param legacy_filters [Hash] Legacy filter hash
  # @return [Hash] New format with conditions array
  def self.legacy_to_new_format(legacy_filters)
    conditions = []

    legacy_filters.each do |key, value|
      next if value.blank?

      condition = case key.to_s
                  when 'status', 'priority', 'user_id', 'assignee_id', 'label_ids', 
                       'qa_module_id', 'submodule_id', 'banking_type_id', 'product_id'
                    {
                      'field' => key.to_s,
                      'operator' => 'IN',
                      'value' => Array(value)
                    }
                  when 'reporter_id'
                    {
                      'field' => 'reporter_id',
                      'operator' => Array(value).size == 1 ? '=' : 'IN',
                      'value' => Array(value).size == 1 ? Array(value).first : Array(value)
                    }
                  when 'start_date'
                    {
                      'field' => 'created_at',
                      'operator' => '>=',
                      'value' => value.to_date.beginning_of_day
                    }
                  when 'end_date'
                    {
                      'field' => 'created_at',
                      'operator' => '<=',
                      'value' => value.to_date.end_of_day
                    }
                  when 'query'
                    # Search queries need special handling - we'll use LIKE
                    {
                      'operator' => 'OR',
                      'conditions' => [
                        {
                          'field' => 'summary',
                          'operator' => 'LIKE',
                          'value' => value
                        },
                        {
                          'field' => 'description',
                          'operator' => 'LIKE',
                          'value' => value
                        }
                      ]
                    }
                  end

      conditions << condition if condition
    end

    return {} if conditions.empty?

    {
      'operator' => 'AND',
      'conditions' => conditions
    }
  end

  # Apply filter to a base relation (convenience method)
  # @param base_relation [ActiveRecord::Relation]
  # @param saved_filter [DefectFilter, nil]
  # @param params [Hash]
  # @return [ActiveRecord::Relation]
  def self.apply(base_relation, saved_filter, params = {})
    merged_rules = merge(saved_filter, params)
    DefectQueryBuilder.new(base_relation).apply_rules(merged_rules)
  end
end
