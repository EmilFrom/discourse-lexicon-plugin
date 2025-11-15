# frozen_string_literal: true

module DiscourseLexiconPlugin
  class ChatMessageNotification
    def self.handle(message, channel, members)
      sender = message.user
      
      # Don't notify the sender
      members = members.reject { |member| member.user_id == sender.id }
      
      members.each do |membership|
        user_id = membership.user_id
        
        # Check if user has expo push subscription
        user_subscription = ExpoPnSubscription.find_by(user_id: user_id)
        next unless user_subscription
        
        # Check channel notification preference
        # notification_level: 
        # 0 = never, 1 = mention only (default), 2 = all messages
        next unless membership.notification_level == 2
        
        post_url = "/c/#{channel.id}#{message.thread_id ? "/#{message.thread_id}" : ""}/#{message.id}"
        
        payload = {
          notification_type: 30, # NEW: ChatMessage type
          excerpt: message.message,
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

