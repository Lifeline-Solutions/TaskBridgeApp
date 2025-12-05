class ErrorNotifierMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue StandardError => e
    context = {
      rack_path: env['PATH_INFO'],
      request_method: env['REQUEST_METHOD'],
      query_string: env['QUERY_STRING'],
      content_type: env['CONTENT_TYPE']
    }

    Rails.logger.error("Middleware Error: #{e.class} - #{e.message}")
    Rails.logger.error("Context: #{context}")
    Rails.logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")

    # Re-raise to let Rails handle it
    raise e
  end
end
