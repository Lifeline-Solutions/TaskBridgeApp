module MentionsHelper
  def render_mentions(content)
    return content unless content.present?

    # Convert content to HTML string
    html_content = case content
                   when ActionText::Content
                     content.to_html
                   when String
                     content
                   else
                     content.to_s
                   end

    # Process user mentions
    html_content = html_content.gsub(/\{\{user:([^:}]+):([^}]*)\}\}/) do
      user_id = Regexp.last_match(1)
      user_name = Regexp.last_match(2)

      user = User.find_by(id: user_id)
      if user
        link_to "@#{user.first_name} #{user.last_name}",
                user_path(user),
                class: 'mention mention-user',
                title: "View #{user.first_name} #{user.last_name}'s profile"
      else
        "<span class='mention mention-user mention-deleted'>@#{user_name}</span>".html_safe
      end
    end

    # Process defect mentions
    html_content = html_content.gsub(/\{\{defect:([^:}]+):([^}]*)\}\}/) do
      defect_id = Regexp.last_match(1)
      defect_unique = Regexp.last_match(2)

      defect = Defect.find_by(id: defect_id)
      if defect
        link_to "##{defect.defect_unique}",
                defect_path(defect),
                class: 'mention mention-defect',
                title: "View defect: #{defect.summary}"
      else
        "<span class='mention mention-defect mention-deleted'>##{defect_unique}</span>".html_safe
      end
    end

    # Also handle legacy span format for existing data (this is the primary format now)
    html_content = html_content.gsub(%r{<span[^>]*data-mention-id="([^"]*)"[^>]*data-mention-type="user"[^>]*>([^<]*)</span>}) do
      user_id = Regexp.last_match(1)
      mention_text = Regexp.last_match(2)

      user = User.find_by(id: user_id)
      if user
        link_to mention_text,
                user_path(user),
                class: 'mention mention-user',
                title: "View #{user.first_name} #{user.last_name}'s profile"
      else
        "<span class='mention mention-user mention-deleted'>#{mention_text}</span>".html_safe
      end
    end

    html_content = html_content.gsub(%r{<span[^>]*data-mention-id="([^"]*)"[^>]*data-mention-type="defect"[^>]*>([^<]*)</span>}) do
      defect_id = Regexp.last_match(1)
      mention_text = Regexp.last_match(2)

      defect = Defect.find_by(id: defect_id)
      if defect
        link_to mention_text,
                defect_path(defect),
                class: 'mention mention-defect',
                title: "View defect: #{defect.summary}"
      else
        "<span class='mention mention-defect mention-deleted'>#{mention_text}</span>".html_safe
      end
    end

    html_content.html_safe
  end
end
