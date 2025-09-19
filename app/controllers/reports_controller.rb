require 'csv'
require 'axlsx'
class ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize! :generate, :report
    @products = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
      product.statuses.any? { |status| ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name) } &&
        Defect.published.where(product_id: product.id).exists?
    end

    @product_options = @products.map do |product|
      client_name = product.client&.name || 'No Client Assigned'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end

    product_id = params[:product_id]
    defects_scope = Defect.published
    defects_scope = defects_scope.where(product_id: product_id) if product_id.present?

    @defects_per_creator = defects_scope
      .joins(:creator)
      .group('users.id', 'users.first_name', 'users.last_name')
      .count

    @defects_per_status = defects_scope
      .joins(:statuses)
      .group('statuses.id', 'statuses.name')
      .count

    @defects_per_retest = defects_scope.where('retest_count > 0').sum(:retest_count)
  end

  def export_csv
    product_id = params[:product_id]
    defects = Defect.published
    defects = defects.where(product_id: product_id) if product_id.present?

    product = Product.find_by(id: product_id) if product_id.present?
    client_name = product&.client&.name || 'all_clients'
    filename = "defect_reports_#{client_name}_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.csv"
    csv_data = generate_defect_csv(defects)

    respond_to do |format|
      format.csv { send_data csv_data, filename: filename, type: 'text/csv' }
    end
  end

  def generate_defect_csv(defects)
    CSV.generate(headers: true) do |csv|
      csv << ['Client Name', 'Product Name', 'Bug ID', 'Label', 'Module', 'Sub Module', 'Banking Type', 'Summary',
              'Assignee', 'Reporter', 'Severity', 'Status', 'Created At', 'Updated At', 'Content']
      defects.each do |defect|
        csv << [
          defect.product&.client&.name,
          defect.product&.groupwares&.map(&:name)&.join(', ') || 'N/A',
          defect.defect_unique&.gsub('–', '-'),
          defect.summary,
          defect.labels&.name,
          defect.qa_module&.name || 'Not specified',
          defect.submodule&.name || 'Not specified',
          defect.banking_type&.name,
          defect.users.map(&:name).select(&:present?).join(', '), # Assignee
          defect.creator&.name, # Reporter (assuming creator is the reporter)
          defect.priority,
          defect.statuses.first&.name || 'N/A',
          defect.created_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          defect.updated_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          defect.content.to_plain_text.truncate(3000)
        ]
      end
    end
  end
end
