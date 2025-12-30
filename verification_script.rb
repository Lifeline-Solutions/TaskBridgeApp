
# Verification Script

# 1. Create Email
puts "Creating email..."
builder = Messaging::EmailSender.send_email("Test Subject", to: "test@example.com", body: "Test Body")
email = builder.send(queue: false)

puts "Email created with ID: #{email.id}"
puts "Retried Count: #{email.retried_count} (Expected: 0)"
puts "Failed Count: #{email.failed_count} (Expected: 0)"
puts "Retried At: #{email.retried_at.inspect} (Expected: nil)"
puts "Sent At: #{email.sent_at.inspect} (Expected: nil)"
puts "Failed At: #{email.failed_at.inspect} (Expected: nil)"

# 2. Mark Sent
puts "\nMarking as sent..."
email.mark_sent!(message_id: "msg-123")
email.reload
puts "Sent At: #{email.sent_at.inspect} (Expected: Time)"
puts "Status: #{email.status}"

# 3. Create another for failure
puts "\nCreating failing email..."
builder2 = Messaging::EmailSender.send_email("Fail Subject", to: "fail@example.com", body: "Fail Body")
email2 = builder2.send(queue: false)

puts "\nMarking as failed..."
email2.mark_failed!(reason: "Test Failure")
email2.reload
puts "Failed At: #{email2.failed_at.inspect} (Expected: Time)"
puts "Failed Count: #{email2.failed_count} (Expected: 1)"
puts "Status: #{email2.status}"

puts "\nVerification Complete"
