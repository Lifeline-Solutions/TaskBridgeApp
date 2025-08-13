module ErrorPayload
  module_function

  def build(exception, context: nil)
    {
      exception_class: exception.class.name,
      message: exception.message.to_s,
      backtrace: Array(exception.backtrace).first(50), # keep it light
      context: safe_context(context),
      occurred_at: Time.current.iso8601
    }
  end

  def safe_context(obj)
    # ensure JSON-serializable & remove huge/unsafe pieces like file uploads
    case obj
    when Hash
      obj.transform_values { |v| scalarize(v) }
    else
      scalarize(obj)
    end
  end

  def scalarize(v)
    case v
    when String, Numeric, TrueClass, FalseClass, NilClass
      v
    when Array
      v.map { |el| scalarize(el) }
    when Hash
      v.transform_values { |el| scalarize(el) }
    else
      v.to_s
    end
  end
end
