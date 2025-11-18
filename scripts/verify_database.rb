#!/usr/bin/env ruby
# frozen_string_literal: true

# Verification script to check banking types, labels, comments, and history in database

require_relative '../config/environment'

puts '=' * 80
puts 'DATABASE VERIFICATION REPORT'
puts '=' * 80

# Banking Types
puts "\n" + ('=' * 80)
puts 'BANKING TYPES'
puts '=' * 80

banking_types = BankingType.all
puts "\nTotal Banking Types: #{banking_types.count}"

if banking_types.any?
  puts "\nBanking Types in Database:"
  banking_types.each do |bt|
    defect_count = Defect.where(banking_type_id: bt.id).count
    puts "  - ID: #{bt.id}, Name: '#{bt.name}', Defects: #{defect_count}"
  end
else
  puts '  ⚠ No banking types found'
end

defects_with_banking = Defect.where.not(banking_type_id: nil)
puts "\nDefects with banking_type_id: #{defects_with_banking.count}"

# Labels
puts "\n" + ('=' * 80)
puts 'LABELS'
puts '=' * 80

labels = Label.all
puts "\nTotal Labels: #{labels.count}"

if labels.any?
  puts "\nLabels in Database:"
  labels.limit(10).each do |label|
    defect_count = begin
      label.defects.count
    rescue StandardError
      0
    end
    puts "  - ID: #{label.id}, Name: '#{label.name}', Defects: #{defect_count}"
  end
  puts "  ... and #{labels.count - 10} more" if labels.count > 10
else
  puts '  ⚠ No labels found'
end

defects_with_labels = Defect.joins(:defect_labels).distinct.count
total_defects = Defect.count
puts "\nDefects with labels: #{defects_with_labels} out of #{total_defects}"

# Comments (DefectMessage)
puts "\n" + ('=' * 80)
puts 'COMMENTS (DefectMessage)'
puts '=' * 80

comments_count = DefectMessage.count
puts "\nTotal DefectMessage Records: #{comments_count}"

if comments_count > 0
  defects_with_comments = Defect.joins(:defect_messages).distinct.count
  puts "Defects with comments: #{defects_with_comments} out of #{total_defects}"

  comments_with_attachments = begin
    DefectMessage.joins(:attachments_attachments).distinct.count
  rescue StandardError
    0
  end
  puts "Comments with attachments: #{comments_with_attachments}"

  puts "\nRecent Comments (last 5):"
  DefectMessage.order(created_at: :desc).limit(5).each do |comment|
    defect = Defect.find_by(id: comment.defect_id)
    defect_key = defect ? defect.defect_unique : 'UNKNOWN'
    user = User.find_by(id: comment.user_id)
    user_name = user ? "#{user.first_name} #{user.last_name}".strip : 'UNKNOWN'
    content_preview = begin
      comment.content.to_plain_text.truncate(60)
    rescue StandardError
      'N/A'
    end
    puts "  - #{defect_key}: by #{user_name} at #{comment.created_at}"
    puts "    Content: #{content_preview}"
  end
else
  puts '  ⚠ No comments found'
end

# History (DefectHistory)
puts "\n" + ('=' * 80)
puts 'DEFECT HISTORY'
puts '=' * 80

history_count = DefectHistory.count
puts "\nTotal DefectHistory Records: #{history_count}"

if history_count > 0
  puts "\nHistory Types Distribution:"
  history_types = DefectHistory.group(:history_type).count.sort_by { |_k, v| -v }
  history_types.take(10).each do |type, count|
    puts "  - #{type}: #{count} record(s)"
  end

  defects_with_history = Defect.joins(:defect_histories).distinct.count
  puts "\nDefects with history: #{defects_with_history} out of #{total_defects}"

  puts "\nRecent History Entries (last 5):"
  DefectHistory.order(created_at: :desc).limit(5).each do |history|
    defect = Defect.find_by(id: history.defect_id)
    defect_key = defect ? defect.defect_unique : 'UNKNOWN'
    user = User.find_by(id: history.user_id)
    user_name = user ? "#{user.first_name} #{user.last_name}".strip : 'UNKNOWN'
    puts "  - #{defect_key}: #{history.history_type} by #{user_name} at #{history.created_at}"
  end
else
  puts '  ⚠ No history records found'
end

# Summary
puts "\n" + ('=' * 80)
puts 'SUMMARY'
puts '=' * 80
puts "Total Defects: #{total_defects}"
puts "Banking Types: #{banking_types.count}"
puts "  - Defects with banking type: #{defects_with_banking.count}"
puts "Labels: #{labels.count}"
puts "  - Defects with labels: #{defects_with_labels}"
puts "Comments: #{comments_count}"
puts "  - Defects with comments: #{Defect.joins(:defect_messages).distinct.count}"
puts "History Records: #{history_count}"
puts "  - Defects with history: #{Defect.joins(:defect_histories).distinct.count}"
puts '=' * 80
