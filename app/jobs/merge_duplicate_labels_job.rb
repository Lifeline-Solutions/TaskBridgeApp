class MergeDuplicateLabelsJob < ApplicationJob
  queue_as :default

  # Merges duplicate labels differing only by case / spacing created before normalization fixes.
  # Strategy:
  #  1. Group by canonical form (downcased with single hyphens)
  #  2. Pick earliest created label as survivor
  #  3. Repoint DefectLabel rows from duplicates to survivor (avoiding duplicates via DISTINCT)
  #  4. Soft delete duplicates
  def perform
    duplicates = Label.with_deleted.group_by { |l| canonical(l.name) }.values.select { |arr| arr.size > 1 }
    duplicates.each do |group|
      survivor = group.min_by(&:created_at)
      (group - [survivor]).each do |dupe|
        ActiveRecord::Base.transaction do
          DefectLabel.where(label_id: dupe.id).distinct.pluck(:defect_id).each do |defect_id|
            unless DefectLabel.exists?(defect_id: defect_id, label_id: survivor.id)
              DefectLabel.create!(defect_id: defect_id, label_id: survivor.id, created_by: dupe.created_by, modified_by: dupe.modified_by)
            end
          end
          # Soft delete duplicate if not already
          dupe.soft_delete!(User.find_by(id: dupe.modified_by)) unless dupe.deleted_on.present?
        end
      end
    end
  end

  private

  def canonical(name)
    name.to_s.strip.gsub(/\s+/, '-').gsub(/-+/, '-').downcase
  end
end