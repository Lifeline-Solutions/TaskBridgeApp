module DefectFilterHelper
  # Check if any filter parameters are present
  def filter_params_present?
    filter_keys = %i[product_id status priority user_id reporter_id qa_module_id
                     submodule_id banking_type_id label_ids start_date end_date order]
    filter_keys.any? { |key| params[key].present? && params[key] != [] }
  end

  # Build URL with a specific filter parameter removed
  def remove_filter_path(filter_key, value_to_remove = nil)
    new_params = params.to_unsafe_h.deep_dup

    if value_to_remove.nil?
      # Remove the entire filter key
      new_params.delete(filter_key.to_s)
    else
      # Remove specific value from array
      current_values = Array(new_params[filter_key.to_s])
      current_values.delete(value_to_remove.to_s)

      if current_values.empty?
        new_params.delete(filter_key.to_s)
      else
        new_params[filter_key.to_s] = current_values
      end
    end

    # Remove pagination to show first page with new filters
    new_params.delete('page')
    new_params.delete('filter_open')
    new_params.delete('filters_loaded')

    "#{request.path}?#{new_params.to_query}"
  end

  # Format product display name
  def product_display_name(product)
    return product.document_name if product.document_name.present?

    name_parts = []
    name_parts << product.client&.name if product.client&.name.present?
    name_parts << product.groupwares&.first&.name if product.groupwares&.first&.name.present?

    name_parts.any? ? name_parts.join(' - ') : "Product ##{product.id}"
  end

  # Format user display name
  def user_display_name(user)
    return 'Unknown User' if user.nil?

    "#{user.first_name} #{user.last_name}".strip.presence || user.email
  end

  # Determine chip color based on filter type
  def filter_chip_color(filter_type)
    colors = {
      product: { bg: 'bg-indigo-100 dark:bg-indigo-900', text: 'text-indigo-800 dark:text-indigo-200', border: 'border-indigo-200 dark:border-indigo-700' },
      status: { bg: 'bg-blue-100 dark:bg-blue-900', text: 'text-blue-800 dark:text-blue-200', border: 'border-blue-200 dark:border-blue-700' },
      priority: { bg: 'bg-orange-100 dark:bg-orange-900', text: 'text-orange-800 dark:text-orange-200', border: 'border-orange-200 dark:border-orange-700' },
      assignee: { bg: 'bg-green-100 dark:bg-green-900', text: 'text-green-800 dark:text-green-200', border: 'border-green-200 dark:border-green-700' },
      reporter: { bg: 'bg-emerald-100 dark:bg-emerald-900', text: 'text-emerald-800 dark:text-emerald-200', border: 'border-emerald-200 dark:border-emerald-700' },
      module: { bg: 'bg-teal-100 dark:bg-teal-900', text: 'text-teal-800 dark:text-teal-200', border: 'border-teal-200 dark:border-teal-700' },
      submodule: { bg: 'bg-cyan-100 dark:bg-cyan-900', text: 'text-cyan-800 dark:text-cyan-200', border: 'border-cyan-200 dark:border-cyan-700' },
      banking_type: { bg: 'bg-purple-100 dark:bg-purple-900', text: 'text-purple-800 dark:text-purple-200', border: 'border-purple-200 dark:border-purple-700' },
      label: { bg: 'bg-pink-100 dark:bg-pink-900', text: 'text-pink-800 dark:text-pink-200', border: 'border-pink-200 dark:border-pink-700' },
      date: { bg: 'bg-gray-100 dark:bg-gray-700', text: 'text-gray-800 dark:text-gray-200', border: 'border-gray-200 dark:border-gray-600' },
      order: { bg: 'bg-yellow-100 dark:bg-yellow-900', text: 'text-yellow-800 dark:text-yellow-200', border: 'border-yellow-200 dark:border-yellow-700' }
    }

    colors[filter_type.to_sym] || colors[:status]
  end

  # Render a single filter chip
  def render_filter_chip(filter_type_label, filter_value, remove_url, filter_type: :status)
    colors = filter_chip_color(filter_type)

    content_tag(:span, class: "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm #{colors[:bg]} #{colors[:text]} rounded-full border #{colors[:border]} transition-all duration-200") do
      content_tag(:span, class: 'font-medium') do
        "#{filter_type_label}:"
      end +
        content_tag(:span, class: 'ml-1') do
          truncate(filter_value, length: 30)
        end +
        link_to(remove_url,
                class: 'ml-2 hover:bg-white/20 dark:hover:bg-black/20 rounded-full p-0.5 transition-colors duration-150 flex-shrink-0',
                title: "Remove #{filter_type_label.downcase} filter",
                data: { turbo_method: :get }) do
          tag.svg(class: 'w-3.5 h-3.5', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24', xmlns: 'http://www.w3.org/2000/svg') do
            tag.path(stroke_linecap: 'round', stroke_linejoin: 'round', stroke_width: '2', d: 'M6 18L18 6M6 6l12 12')
          end
        end
    end
  end
end
