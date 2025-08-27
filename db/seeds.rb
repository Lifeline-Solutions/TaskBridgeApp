# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end


# Create Roles on the system

Role.find_or_create_by!(name: 'agent')
Role.find_or_create_by!(name: 'admin')
Role.find_or_create_by!(name: 'project manager')
Role.find_or_create_by!(name: 'client')
Role.find_or_create_by!(name: 'observer')
Role.find_or_create_by!(name: 'sales')
Role.find_or_create_by!(name: 'ceo')
Role.find_or_create_by!(name: 'hod')
Role.find_or_create_by!(name: 'qa')

a = User.create!(email: 'admin@craftsilicon.com', password: 'password', confirmed_at: DateTime.now , confirmation_sent_at: DateTime.now, first_name: 'Jay', last_name: 'Admin')
a.add_role(:admin)

b = User.create!(email: 'project@craftsilicon.com', password: 'password', confirmed_at: DateTime.now , confirmation_sent_at: DateTime.now, first_name: 'Project', last_name: 'Manager')
b.add_role('project manager')

c = User.create!(email: 'agent@craftsilicon.com', password: 'password', confirmed_at: DateTime.now , confirmation_sent_at: DateTime.now, first_name: 'Agent', last_name: 'Active')
c.add_role(:agent)

d = User.create!(email: 'client@craftsilicon.com', password: 'password', confirmed_at: DateTime.now , confirmation_sent_at: DateTime.now, first_name: 'Client', last_name: 'Active')
d.add_role(:client)

