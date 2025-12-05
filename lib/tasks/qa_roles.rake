# Task to set up QA roles for the global search functionality
# Run with: rails qa_roles:setup

namespace :qa_roles do
  desc 'Create QA Agent and QA Admin roles for defect search'
  task setup: :environment do
    puts 'Setting up QA roles...'

    # Create QA Agent role
    qa_agent = Role.find_or_create_by(name: 'qa agent') do |role|
      role.resource_type = nil
      role.resource_id = nil
    end

    if qa_agent.persisted?
      puts '✓ QA Agent role created/verified'
    else
      puts "✗ Failed to create QA Agent role: #{qa_agent.errors.full_messages.join(', ')}"
    end

    # Create QA Admin role
    qa_admin = Role.find_or_create_by(name: 'qa admin') do |role|
      role.resource_type = nil
      role.resource_id = nil
    end

    if qa_admin.persisted?
      puts '✓ QA Admin role created/verified'
    else
      puts "✗ Failed to create QA Admin role: #{qa_admin.errors.full_messages.join(', ')}"
    end

    puts "\nRoles setup complete!"
    puts "\nTo assign roles to users, use:"
    puts "  user = User.find_by(email: 'user@example.com')"
    puts "  user.add_role('qa agent')  # or 'qa admin'"
  end

  desc 'List all users with QA roles'
  task list: :environment do
    puts "Users with QA roles:\n\n"

    puts 'QA Agents:'
    User.with_role('qa agent').each do |user|
      puts "  - #{user.email} (#{user.name})"
    end

    puts "\nQA Admins:"
    User.with_role('qa admin').each do |user|
      puts "  - #{user.email} (#{user.name})"
    end
  end
end
