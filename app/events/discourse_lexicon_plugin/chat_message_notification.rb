# frozen_string_literal: true

module DiscourseLexiconPlugin
  class ChatMessageNotification
    def self.handle(message, channel, members)
      sender = message.user
      
      # Don't notify the sender
      members = members.reject { |member| member.user_id == sender.id }
      
      members.each do |membership|
        user_id = membership.user_id
        Rails.logger.warn("[Lexicon Plugin] Processing member - User ID: #{user_id}")
        
        # Check if user has expo push subscription
        user_subscription = ExpoPnSubscription.find_by(user_id: user_id)
        unless user_subscription
          Rails.logger.warn("[Lexicon Plugin] User #{user_id} has NO expo subscription - skipping")
          next
        end
        Rails.logger.warn("[Lexicon Plugin] User #{user_id} HAS expo subscription")
        
        # Check app-specific notification preference (defaults to true if not set)
        unless LexiconChatNotificationPreference.push_enabled_for?(user_id, channel.id)
          Rails.logger.warn("[Lexicon Plugin] User #{user_id} has disabled push for channel #{channel.id} - skipping")
          next
        end
        Rails.logger.warn("[Lexicon Plugin] User #{user_id} has push enabled for channel #{channel.id} - proceeding")
        
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
        
        Rails.logger.warn("[Lexicon Plugin] Enqueuing push notification for user #{user_id}")
        Jobs.enqueue(:expo_push_notification, payload:, user_id: user_id)
        Rails.logger.warn("[Lexicon Plugin] Push notification enqueued successfully for user #{user_id}")
      end
    end
  end
end

