# Make GlobalID deserialization tolerant in ActiveJob executions.
# When a GlobalID references a record that no longer exists, GlobalID.locate
# normally raises ActiveRecord::RecordNotFound during job argument
# deserialization which causes the job to fail before it can run. To avoid
# noisy failures we return nil and log the missing reference, allowing jobs
# to decide how to proceed (or fail later with clearer context).

begin
  require 'global_id'

  module GlobalID
    class Locator
      class << self
        if method_defined?(:locate) || private_method_defined?(:locate)
          alias_method :__orig_locate, :locate
        end

        def locate(gid)
          begin
            __orig_locate(gid)
          rescue ::ActiveRecord::RecordNotFound => _e
            Rails.logger.warn("GlobalID locate: referenced record not found for gid=#{gid}") if defined?(Rails)
            nil
          end
        end
      end
    end
  end
rescue LoadError
  # global_id not available; nothing to do
end
