module Users
  class RegistrationsController < Devise::RegistrationsController
    def update
      super do |resource|
        if resource.errors.empty? && !resource.first_login
          # Mark first_login as true if it wasn't already
          resource.update_column(:first_login, true)
        end
      end
    end

    protected

    def after_update_path_for(resource)
      if resource.has_role?(:ceo) && !request.path.start_with?(cease_fire_report_path)
        cease_fire_report_path
      else
        root_path
      end
    end
  end
end
