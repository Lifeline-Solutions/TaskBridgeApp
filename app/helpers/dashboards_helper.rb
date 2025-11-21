module DashboardsHelper
  def format_filter_value(key, value)
    return value if value.blank?

    case key.to_s
    when 'qa_module_id'
      format_qa_module_ids(value)
    when 'submodule_id'
      format_submodule_ids(value)
    when 'label_ids'
      format_label_ids(value)
    when 'user_id'
      format_user_ids(value)
    when 'reporter_id'
      format_reporter_ids(value)
    when 'product_id'
      format_product_ids(value)
    when 'banking_type_id'
      format_banking_type_ids(value)
    when 'priority', 'status'
      format_array_value(value)
    else
      value.is_a?(Array) ? value.join(', ') : value
    end
  end

  private

  def format_qa_module_ids(value)
    ids = Array(value)
    modules = QaModule.where(id: ids).pluck(:name)
    modules.any? ? modules.join(', ') : value
  end

  def format_submodule_ids(value)
    ids = Array(value)
    submodules = QaModule.where(id: ids).pluck(:name)
    submodules.any? ? submodules.join(', ') : value
  end

  def format_label_ids(value)
    ids = Array(value)
    labels = Label.where(id: ids).pluck(:name)
    labels.any? ? labels.join(', ') : value
  end

  def format_user_ids(value)
    ids = Array(value)
    users = User.where(id: ids).pluck(:first_name, :last_name)
    return value if users.empty?
    
    users.map { |first, last| "#{first} #{last}".strip }.join(', ')
  end

  def format_reporter_ids(value)
    ids = Array(value)
    reporters = User.where(id: ids).pluck(:first_name, :last_name)
    return value if reporters.empty?
    
    reporters.map { |first, last| "#{first} #{last}".strip }.join(', ')
  end

  def format_product_ids(value)
    ids = Array(value)
    products = Product.where(id: ids).pluck(:name)
    products.any? ? products.join(', ') : value
  end

  def format_banking_type_ids(value)
    ids = Array(value)
    banking_types = BankingType.where(id: ids).pluck(:name)
    banking_types.any? ? banking_types.join(', ') : value
  end

  def format_array_value(value)
    value.is_a?(Array) ? value.join(', ') : value
  end
end
