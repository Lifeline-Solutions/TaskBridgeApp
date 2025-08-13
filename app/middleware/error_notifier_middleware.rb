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
    SafeNotifier.email(e, context: context)
    raise
  end
end
