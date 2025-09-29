class ErrorNotifierMiddleware
  def initialize(app) = @app = app

  def call(env)
    @app.call(env)
  rescue StandardError => e
    context = {
      rack_path: env['PATH_INFO'],
      method: env['REQUEST_METHOD'],
      request_id: env['action_dispatch.request_id'],
      params: (env['action_dispatch.request.parameters'] || {}).except('controller', 'action'),
      user_agent: env['HTTP_USER_AGENT'],
      ip: env['REMOTE_ADDR']
    }
    ErrorLogger.log(e, context: context)
    # No email here; SafeNotifier is reserved for explicit system-break paths
    raise
  end
end
