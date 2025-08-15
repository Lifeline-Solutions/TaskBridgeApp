class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Soft delete support for all models that have deleted_on column
  include SoftDeletable if defined?(SoftDeletable)

  # Auto audit created_by/modified_by on save for all models that have those columns
  include Auditable if defined?(Auditable)
end
