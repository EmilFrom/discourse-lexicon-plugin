# frozen_string_literal: true
module DiscourseLexiconPlugin
  class ChatMessageNotification
    def self.handle(message, channel, members)
      sender = message.user
      
      # --- NEW: Helper logic to clean excerpt ---
      raw_excerpt = message.message || ""
      
      # Regex to find markdown images ex: ![image.jpg|...](upload://...)
      # We replace it with a camera emoji and text
      cleaned_excerpt = raw_excerpt.gsub(/!\[.*?\]\(.*?\)/, '📷 [Image]').strip
      
      # If the message was ONLY an image, it might look like "📷 [Image]", which is perfect.
      # If it was "Check this out ![...]", it becomes "Check this out 📷 [Image]"
      # ------------------------------------------

      # Don't notify the sender
      members = members.reject { |member| member.user_id == sender.id }
      
      members.each do |membership|
        user_id = membership.user_id
        
        # ... (Existing subscription checks) ...
        user_subscription = ExpoPnSubscription.find_by(user_id: user_id)
        next unless user_subscription
        
        unless LexiconChatNotificationPreference.push_enabled_for?(user_id, channel.id)
          next
        end
        
        post_url = "/c/#{channel.id}#{message.thread_id ? "/#{message.thread_id}" : ""}/#{message.id}"
        
        payload = {
          notification_type: 30, 
          excerpt: cleaned_excerpt, # <--- CHANGED: Use cleaned_excerpt instead of message.message
          username: sender.username,
          post_url: post_url,
          is_chat: true,
          is_thread: message.thread_id.present?,
          channel_name: channel.name
        }
        
        Jobs.enqueue(:expo_push_notification, payload:, user_id: user_id)
      end
    end
  end
end

