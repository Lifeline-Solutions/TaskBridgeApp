module Activities
  module_function

  def activity(log_name: 'user_activity')
    Builder.new(log_name: log_name)
  end

  class Builder
    def initialize(log_name:)
      @attrs = { log_name: log_name, properties: {} }
    end

    def caused_by(user)
      return self unless user

      @attrs[:causer] = user
      @attrs[:causer_type] = ::ActivityMorphMap.class_to_key(user.class)
      @attrs[:causer_id] = user.id
      self
    end

    def performed_on(record)
      return self unless record

      @attrs[:subject] = record
      @attrs[:subject_type] = ::ActivityMorphMap.class_to_key(record.class)
      @attrs[:subject_id] = record.id
      self
    end

    def event(name)
      @attrs[:event] = name.to_s
      self
    end

    def with_properties(hash)
      @attrs[:properties] = (@attrs[:properties] || {}).merge(hash || {})
      self
    end

    def in_batch(uuid)
      @attrs[:batch_uuid] = uuid
      self
    end

    def log(description)
      @attrs[:description] = description
      save!
    end

    private

    def save!
      causer = @attrs[:causer] || Current.user
      SystemActivity.create!(
        log_name: @attrs[:log_name],
        description: @attrs[:description],
        subject_type: @attrs[:subject_type],
        subject_id: @attrs[:subject_id],
        causer_type: causer && ::ActivityMorphMap.class_to_key(causer.class),
        causer_id: causer&.id,
        properties: @attrs[:properties],
        event: @attrs[:event],
        batch_uuid: @attrs[:batch_uuid]
        # created_by / modified_by set by SystemActivity model hook
      )
    rescue StandardError => e
      Rails.logger.error("Activities save failed (#{e.class}): #{e.message}")
    end
  end
end
