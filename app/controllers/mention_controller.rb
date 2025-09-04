class MentionController < ApplicationController
  before_action :authenticate_user!

  def users
    query = params[:query]&.downcase || ''

    # Get all active users from the database
    base_users = User.where(active: true)

    # Filter users based on query
    users = if query.present?
              base_users.where(
                "LOWER(first_name) LIKE ? OR LOWER(last_name) LIKE ? OR LOWER(email) LIKE ? OR LOWER(CONCAT(first_name, ' ', last_name)) LIKE ?",
                "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%"
              )
            else
              base_users
            end

    # Order by name and limit results
    users = users.order(:first_name, :last_name).limit(10)

    formatted_users = users.map do |user|
      {
        id: user.id,
        name: "#{user.first_name} #{user.last_name}",
        email: user.email,
        avatar_url: user.profile_picture.attached? ? url_for(user.profile_picture) : nil
      }
    end

    render json: formatted_users
  end

  def defects
    query = params[:query]&.downcase || ''
    current_defect_id = params[:current_defect_id]

    # Get published defects excluding current defect
    base_defects = Defect.published.includes(:product)
    base_defects = base_defects.where.not(id: current_defect_id) if current_defect_id.present?

    # Filter defects based on query
    defects = if query.present?
                base_defects.where(
                  'LOWER(summary) LIKE ? OR LOWER(defect_unique) LIKE ?',
                  "%#{query}%", "%#{query}%"
                )
              else
                base_defects
              end

    # Limit results and format response
    defects = defects.order(created_at: :desc).limit(10)

    formatted_defects = defects.map do |defect|
      {
        id: defect.id,
        defect_unique: defect.defect_unique,
        summary: defect.summary,
        priority: defect.priority,
        product_name: defect.product&.content&.to_plain_text&.truncate(30) || 'No product'
      }
    end

    render json: formatted_defects
  end
end
