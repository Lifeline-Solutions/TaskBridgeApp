class ErrorLogger
  LOG_FILE = Rails.root.join("log", "production_errors.log")

  def self.log(exception, context: nil)
    File.open(LOG_FILE, "a") do |f|
      f.puts "=== ERROR @ #{Time.current} ==="
      f.puts "Message: #{exception.message}"
      f.puts "Type: #{exception.class}"
      f.puts "Context: #{context.inspect}" if context
      f.puts "Backtrace:\n#{Array(exception.backtrace).join("\n")}"
      f.puts "=============================="
      f.puts
    end
  end
end