# Test script for team_report_breach functionality
# Run this in rails console: load 'test/team_breach_report_test.rb'

puts '=' * 80
puts 'Testing Team Breach Report Data Structures'
puts '=' * 80

# Check if necessary models exist
begin
  team_count = Team.count
  user_count = User.count
  ticket_count = Ticket.count
  event_count = Event.count

  puts "\n✓ Models accessible:"
  puts "  - Teams: #{team_count}"
  puts "  - Users: #{user_count}"
  puts "  - Tickets: #{ticket_count}"
  puts "  - Events: #{event_count}"

  # Check for events with assigned_user_id
  events_with_assigned = Event.where.not(assigned_user_id: nil).count
  puts "\n✓ Events with assigned_user_id: #{events_with_assigned}"

  if events_with_assigned.zero?
    puts "\n⚠ WARNING: No events have assigned_user_id set."
    puts '  Run the Event update script first to populate assigned_user_id'
  end

  # Check for SLA tickets
  if defined?(SlaTicket)
    sla_count = SlaTicket.count
    breached_count = SlaTicket.where(sla_resolution_deadline: 'Breached').count
    puts "\n✓ SLA Tickets:"
    puts "  - Total: #{sla_count}"
    puts "  - Breached: #{breached_count}"
  else
    puts "\n⚠ SlaTicket model not found"
  end

  # Test with first team if available
  if team_count.positive?
    test_team = Team.first
    puts "\n#{'=' * 80}"
    puts "Sample Test with Team: #{test_team.name}"
    puts '=' * 80

    team_member_ids = test_team.users.pluck(:id)
    puts "Team members: #{team_member_ids.size}"

    # Get assigned tickets
    start_date = 6.months.ago.to_date
    end_date = Date.today

    assigned_ticket_ids = Event.where(assigned_user_id: team_member_ids)
      .where.not(ticket_id: nil)
      .pluck(:ticket_id)
      .uniq

    puts "Tickets assigned to team (ever): #{assigned_ticket_ids.size}"

    tickets = Ticket.where(id: assigned_ticket_ids)
      .where('created_at >= ? AND created_at <= ?',
             start_date.beginning_of_day,
             end_date.end_of_day)

    puts "Tickets in date range (#{start_date} to #{end_date}): #{tickets.count}"

    if tickets.any?
      tickets_by_status = tickets.joins(:statuses).group('statuses.name').count
      puts "\nTickets by status:"
      tickets_by_status.each { |status, count| puts "  - #{status}: #{count}" }

      if defined?(SlaTicket)
        breached = tickets.joins(:sla_tickets)
          .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .distinct
          .count
        puts "\nBreached tickets: #{breached}"

        if tickets.any?
          breach_rate = (breached.to_f / tickets.count) * 100
          performance = (100 - breach_rate).round(2)
          puts "Performance Score: #{performance}%"
        end
      end
    else
      puts "\n⚠ No tickets found in the date range"
    end
  else
    puts "\n⚠ No teams found in database"
  end

  puts "\n#{'=' * 80}"
  puts '✓ Test completed successfully'
  puts '=' * 80
  puts "\nTo access the report:"
  puts '  Navigate to: /team_report_breach'
  puts '  Or use: team_report_breach_path'
rescue StandardError => e
  puts "\n✗ Error during test:"
  puts "  #{e.class}: #{e.message}"
  puts "\n  Backtrace:"
  puts e.backtrace.first(5).map { |line| "    #{line}" }.join("\n")
end
