# Make GlobalID deserialization tolerant in ActiveJob executions.
# When a GlobalID references a record that no longer exists, GlobalID.locate
# normally raises ActiveRecord::RecordNotFound during job argument
# deserialization which causes the job to fail before it can run. To avoid
# noisy failures we return nil and log the missing reference, allowing jobs
# to decide how to proceed (or fail later with clearer context).

begin
  require 'global_id'

  # Only attempt to reopen/patch GlobalID if it exists and is a Module.
  # If some application code erroneously assigns GlobalID to a class or
  # other constant, trying to `module GlobalID` will raise a TypeError
  # (you've seen "GlobalID is not a module"). To avoid that, check the
  # constant's type first and skip patching when it's not safe.
  if defined?(::GlobalID)
    if ::GlobalID.is_a?(Module)
      # Patch GlobalID::Locator.locate to rescue RecordNotFound and return nil
      ::GlobalID::Locator.singleton_class.class_eval do
        if method_defined?(:locate) || private_method_defined?(:locate)
          alias_method :__orig_locate, :locate
        end

        define_method(:locate) do |gid|
          begin
            __orig_locate(gid)
          rescue ::ActiveRecord::RecordNotFound => _e
            Rails.logger.warn("GlobalID locate: referenced record not found for gid=#{gid}") if defined?(Rails)
            nil
          end
        end
      end
    else
      # GlobalID exists but is not a Module — log and skip to avoid boot error.
      Rails.logger.warn("globalid_rescue: skipping patch because GlobalID is defined but is a ") if defined?(Rails)
    end
  else
    # If GlobalID isn't defined, nothing to do (gem may be absent in some envs)
    Rails.logger.info("globalid_rescue: GlobalID constant not defined; skipping patch") if defined?(Rails)
  end
rescue LoadError
  # global_id gem not installed; nothing to do
rescue => e
  # Catch-all to avoid initializer crashes; log so we can investigate safely.
  Rails.logger.error("globalid_rescue: unexpected error during initialization: #{e.class}: #{e.message}") if defined?(Rails)
end
