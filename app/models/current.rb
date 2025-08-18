# frozen_string_literal: true

# Thread-safe holder for request-scoped attributes like current user
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
