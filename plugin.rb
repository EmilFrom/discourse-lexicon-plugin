# frozen_string_literal: true

# name: discourse-lexicon-plugin
# about: Official Discourse plugin for Lexicon (https://lexicon.is)
# version: 3.0
# authors: kodefox
# url: https://github.com/kodefox/discourse-lexicon-plugin

# We need to load all external packages first
# Reference: https://meta.discourse.org/t/plugin-using-own-gem/50007/4
# After testing, we determined that we do not need to load all the dependent packages already installed in the Discourse core. However, `ffi` is required because we encountered the error: `Error installing llhttp-ffi Gem::MissingSpecError: Could not find 'ffi' (>= 1.15.5)`.

gem 'domain_name', '0.5.20190701'
gem 'http-cookie', '1.0.5'
gem 'ffi', '1.17.2'
gem 'ffi-compiler', '1.3.2', require_name: 'ffi-compiler/loader'
gem 'llhttp-ffi', '0.4.0', require_name: 'llhttp'
gem 'http-form_data', '2.3.0', require_name: 'http/form_data'
gem 'http', '5.1.1'
require_relative 'lib/expo_server_sdk_ruby/expo/server/sdk'

enabled_site_setting :lexicon_push_notifications_enabled
enabled_site_setting :lexicon_email_deep_linking_enabled
enabled_site_setting :lexicon_app_scheme

module ::DiscourseLexiconPlugin
  PLUGIN_NAME = 'discourse-lexicon-plugin'
end

load File.expand_path('lib/discourse-lexicon-plugin/engine.rb', __dir__)

# Site setting validators must be loaded before initialize
require_relative 'lib/validators/lexicon_enable_deep_linking_validator'
require_relative 'lib/validators/lexicon_app_scheme_validators'

after_initialize do
  load File.expand_path('app/controllers/deeplink_controller.rb', __dir__)
  load File.expand_path('app/deeplink_notification_module.rb', __dir__)
  load File.expand_path('app/serializers/site_serializer.rb', __dir__)

  if SiteSetting.lexicon_image_dimensions_enabled
    load File.expand_path('app/models/lexicon_image_dimension.rb', __dir__)
    load File.expand_path('app/events/discourse_lexicon_plugin/upload_dimension_tracker.rb', __dir__)
    load File.expand_path('app/controllers/discourse_lexicon_plugin/image_dimensions_controller.rb', __dir__)
    load File.expand_path('app/serializers/topic_list_item_serializer_extension.rb', __dir__)

    DiscourseEvent.on(:upload_created) do |upload|
      DiscourseLexiconPlugin::UploadDimensionTracker.handle_upload_created(upload)
    end

    TopicListItemSerializer.prepend(TopicListItemSerializerExtension)

    Rails.logger.info("[Lexicon Plugin] Image dimension tracking initialized")
  end

  if SiteSetting.lexicon_push_notifications_enabled
    Rails.logger.warn("="*80)
    Rails.logger.warn("[Lexicon Plugin] INITIALIZATION - Push notifications enabled")
    Rails.logger.warn("="*80)
    
    load File.expand_path('app/jobs/regular/expo_push_notification.rb', __dir__)
    load File.expand_path('app/jobs/regular/check_pn_receipt.rb', __dir__)
    load File.expand_path('app/jobs/scheduled/clean_up_push_notification_retries.rb', __dir__)
    load File.expand_path('app/jobs/scheduled/clean_up_push_notification_receipts.rb', __dir__)
    load File.expand_path('app/events/discourse_lexicon_plugin/chat_mention_notification.rb', __dir__)
    load File.expand_path('app/events/discourse_lexicon_plugin/chat_message_notification.rb', __dir__)
    load File.expand_path('app/models/lexicon_chat_notification_preference.rb', __dir__)
    load File.expand_path('app/controllers/lexicon_chat_notification_preferences_controller.rb', __dir__)

    User.class_eval { has_many :expo_pn_subscriptions, dependent: :delete_all }

    DiscourseEvent.on(:before_create_notification) do |user, type, post, opts|
      Rails.logger.warn("[Lexicon Plugin] before_create_notification fired - User: #{user.username}, Type: #{type}")
      
      if user.expo_pn_subscriptions.exists?
        Rails.logger.warn("[Lexicon Plugin] User has expo subscription, enqueuing push notification")
        
        payload = {
          notification_type: type,
          post_number: post.post_number,
          topic_title: post.topic.title,
          topic_id: post.topic.id,
          excerpt:
            nil ||
            post.excerpt(
              400,
              text_entities: true,
              strip_links: true,
              remap_emoji: true
            ),
          username: type == Notification.types[:liked] ? nil || opts[:display_username] : nil || post.username,
          post_url: post.url,
          is_pm: post.topic.private_message?
        }
        Jobs.enqueue(
          :expo_push_notification,
          payload:,
          user_id: user.id
        )
      end
    end

    # Handle notification chat mention event after create notification summary
    DiscourseEvent.on(:notification_created) do |notification|
      Rails.logger.warn("[Lexicon Plugin] notification_created fired - Type: #{notification.notification_type}, User ID: #{notification.user_id}")
      DiscourseLexiconPlugin::ChatMentionNotification.handle(notification)
    end

    # Handle regular chat messages (non-mentions) using after_commit callback
    Rails.logger.warn("[Lexicon Plugin] Registering Chat::Message after_commit callback...")
    
    Chat::Message.class_eval do
      after_commit :send_lexicon_push_notifications, on: :create
      
      private
      
      def send_lexicon_push_notifications
        Rails.logger.warn("[Lexicon Plugin] ========================================")
        Rails.logger.warn("[Lexicon Plugin] after_commit callback TRIGGERED!")
        Rails.logger.warn("[Lexicon Plugin] Message ID: #{self.id}, User: #{self.user&.username}")
        Rails.logger.warn("[Lexicon Plugin] ========================================")
        
        return unless SiteSetting.lexicon_push_notifications_enabled
        Rails.logger.warn("[Lexicon Plugin] Push notifications enabled: true")
        
        begin
          channel = self.chat_channel
          Rails.logger.warn("[Lexicon Plugin] Channel: #{channel&.name} (ID: #{channel&.id})")
          
          memberships = channel.user_chat_channel_memberships.where.not(user_id: self.user_id)
          Rails.logger.warn("[Lexicon Plugin] Found #{memberships.count} memberships (excluding sender)")
          
          memberships.each do |m|
            Rails.logger.warn("[Lexicon Plugin] Membership - User ID: #{m.user_id}, Notification Level: #{m.notification_level} (#{m.notification_level_before_type_cast})")
          end
          
          DiscourseLexiconPlugin::ChatMessageNotification.handle(self, channel, memberships)
          Rails.logger.warn("[Lexicon Plugin] Handler called successfully")
        rescue => e
          Rails.logger.error("[Lexicon Plugin] Error in after_commit callback: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
        end
      end
    end

  end

  Discourse::Application.routes.append do
    get '/lexicon/deeplink/*link' => 'deeplink#index'
    get '/deeplink/*link' => 'deeplink#index'
    get '/lexicon/chat-notifications' => 'lexicon_chat_notification_preferences#index'
    get '/lexicon/chat-notifications/:channel_id' => 'lexicon_chat_notification_preferences#show'
    put '/lexicon/chat-notifications/:channel_id' => 'lexicon_chat_notification_preferences#update'
  end

  UserNotifications.class_eval { prepend DeeplinkNotification }
end
