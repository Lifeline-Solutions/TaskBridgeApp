# Maps classes to short type keys for activities. Override map to customize.
module ActivityMorphMap
  module_function

  # Customize this map if you want shorter keys than full class names
  MAP = {
    # Example:
    # 'User' => 'user',
    # 'Project' => 'project'
  }.freeze

  def class_to_key(klass)
    return nil unless klass
    MAP[klass.name] || klass.name
  end
end
