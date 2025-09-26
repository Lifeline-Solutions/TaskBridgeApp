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
    UserMailer.defect_mention_notification(
      user,
      @defect,
      @current_user,
      @content,
      @context_type
    ).deliver_now
  rescue StandardError => e
    Rails.logger.error "Failed to send mention notification to #{user.email}: #{e.message}"
    ErrorLogger.log(e, context: {
                      user_id: user.id,
                      defect_id: @defect.id,
                      current_user_id: @current_user.id,
                      context_type: @context_type
                    })
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

  class << self
    # Class method for easier usage
    def process_mentions(content, defect, current_user, context_type = 'message')
      new(content, defect, current_user, context_type).process_mentions
    end
  end
end
