class MentionNotificationService
  def initialize(content, defect, current_user, context_type = 'message')
    @content = content
    @defect = defect
    @current_user = current_user
    @context_type = context_type # 'message' or 'defect_content'
  end

  def process_mentions
    mentioned_users = extract_mentioned_users
    return mentioned_users if mentioned_users.empty?

    mentioned_users.each do |user|
      next if user == @current_user # Don't notify self

      send_mention_notification(user)
      create_activity_log(user)
    end

    mentioned_users
  end

  private

  def extract_mentioned_users
    return [] unless @content.present?

    # Extract user mentions from rich text content
    # Handle both ActionText::Content and HTML string formats
    content_html = extract_html_content(@content)

    user_ids = []

    # Find mention spans with data-mention-id attributes (primary format)
    content_html.scan(/data-mention-id="([^"]*)"[^>]*data-mention-type="user"/) do |match|
      user_ids << match[0]
    end

    # Handle the {{user:id:name}} format from form submission (legacy)
    content_html.scan(/\{\{user:([^:}]+):[^}]*\}\}/) do |match|
      user_ids << match[0]
    end

    # Handle link format from frontend: <a href="/users/USER_ID">@Username</a>
    content_html.scan(%r{<a[^>]*href="/users/([^"]+)"[^>]*>@[^<]*</a>}) do |match|
      user_ids << match[0]
    end

    # Also handle plain text mentions for backward compatibility
    content_html.scan(/@mention-user-(\w+)/) do |match|
      user_ids << match[0]
    end

    # Remove duplicates and fetch users
    User.where(id: user_ids.uniq, active: true)
  end

  def extract_html_content(content)
    case content
    when ActionText::Content
      content.to_html
    when String
      content
    else
      content.to_s
    end
  end

  def send_mention_notification(user)
    subject = build_email_subject
    body = build_email_body(user)

    Messaging::EmailSender
      .send_email(
        subject,
        to: [user.email],
        body: body,
        actor: @current_user,
        priority: :normal,
        type: 'defect_mention'
      )
      .set_source('Defect', @defect.id)
      .set_party('User', user.id)
      .send(queue: true)
  rescue StandardError => e
    Rails.logger.error "Failed to send mention notification to #{user.email}: #{e.message}"
    ErrorLogger.log(e, context: {
                      user_id: user.id,
                      defect_id: @defect.id,
                      current_user_id: @current_user.id,
                      context_type: @context_type
                    })
  end

  def build_email_subject
    context_text = @context_type == 'message' ? 'comment' : 'defect'
    "You were mentioned in a #{context_text} on defect #{@defect.defect_unique}"
  end

  def build_email_body(user)
    defect_url = Rails.application.routes.url_helpers.defect_url(@defect, host: ENV.fetch('APP_HOST', 'localhost:3000'))

    context_text = @context_type == 'message' ? 'comment' : 'defect description'

    <<~HTML
      <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
        <h2 style="color: #2563eb;">You've been mentioned!</h2>

        <p>Hi #{user.first_name},</p>

        <p><strong>#{@current_user.first_name} #{@current_user.last_name}</strong> mentioned you in a #{context_text} on defect:</p>

        <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 16px; margin: 16px 0;">
          <h3 style="margin-top: 0; color: #1f2937;">#{@defect.defect_unique}: #{@defect.summary}</h3>
          <p><strong>Priority:</strong> #{@defect.priority}</p>
          <p><strong>Product:</strong> #{get_product_display_name}</p>
          #{build_content_preview}
        </div>

        <div style="margin: 24px 0;">
          <a href="#{defect_url}"
             style="background-color: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block;">
            View Defect
          </a>
        </div>

        <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">

        <p style="font-size: 12px; color: #6b7280;">
          This notification was sent because you were mentioned in TaskBridge.
          <br>Reply directly to this email or click the link above to respond.
        </p>
      </div>
    HTML
  end

  def build_content_preview
    return '' unless @content.present?

    # Extract plain text for preview (remove HTML tags and mentions)
    content_text = ActionController::Base.helpers.strip_tags(extract_html_content(@content))
    content_text = content_text.gsub(/@[^\s]+/, '').gsub(/#[^\s]+/, '').strip

    # Limit to first 200 characters
    preview = content_text.length > 200 ? "#{content_text[0..197]}..." : content_text

    return '' if preview.blank?

    <<~HTML
      <div style="margin-top: 12px; padding-top: 12px; border-top: 1px solid #e2e8f0;">
        <p style="font-style: italic; margin: 0;">#{preview}</p>
      </div>
    HTML
  end

  def create_activity_log(user)
    Activities.activity
      .caused_by(@current_user)
      .performed_on(@defect)
      .event('defect.user_mentioned')
      .with_properties(
        mentioned_user_id: user.id,
        mentioned_user_name: "#{user.first_name} #{user.last_name}",
        context_type: @context_type,
        defect_unique: @defect.defect_unique
      )
      .log("Mentioned #{user.first_name} #{user.last_name} in #{@context_type} on Defect ##{@defect.id}")
  end

  def get_product_display_name
    return 'Unknown Product' unless @defect.product

    # Try different attributes to get a meaningful product name
    product = @defect.product

    if product.document_name.present?
      product.document_name
    elsif product.respond_to?(:name) && product.name.present?
      product.name
    elsif product.respond_to?(:title) && product.title.present?
      product.title
    else
      "Product ##{product.id.to_s[0..7]}"
    end
  end

  class << self
    # Class method for easier usage
    def process_mentions(content, defect, current_user, context_type = 'message')
      new(content, defect, current_user, context_type).process_mentions
    end
  end
end
