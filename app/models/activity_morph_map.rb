# app/models/activity_morph_map.rb
class ActivityMorphMap
  # Convert a class to the stored polymorphic key
  def self.class_to_key(klass)
    klass.base_class.name
  end

  # Convert a stored key back to a class
  def self.key_to_class(key)
    key.to_s.constantize
  end
end
