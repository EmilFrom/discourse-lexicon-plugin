# frozen_string_literal: true

# Hook into Chat::Api::ChannelMessagesController to capture errors
# when messages are sent to channels created by our plugin

if defined?(::Chat::Api::ChannelMessagesController)
  ::Chat::Api::ChannelMessagesController.class_eval do
    require 'json'
    
    rescue_from StandardError, with: :log_lexicon_chat_error

    private

    def log_lexicon_chat_error(exception)
      # Log to our debug log file
      log_path = Rails.root.join('.cursor', 'debug.log')
      log_data = {
        sessionId: 'debug-session',
        runId: 'message-error',
        hypothesisId: 'A',
        location: 'Chat::Api::ChannelMessagesController#create',
        message: 'Error creating chat message',
        data: {
          channel_id: params[:chat_channel_id] || params[:id],
          error_class: exception.class.name,
          error_message: exception.message,
          backtrace: exception.backtrace&.first(10),
          params: params.to_unsafe_h.except('controller', 'action')
        },
        timestamp: Time.current.to_i * 1000
      }
      
      begin
        File.open(log_path, 'a') do |f|
          f.puts(JSON.generate(log_data))
        end
      rescue => e
        Rails.logger.error("[Lexicon] Failed to write debug log: #{e.message}")
      end

      # Also log to Rails logger
      Rails.logger.error("[Lexicon] Chat message creation error:")
      Rails.logger.error("[Lexicon] Channel ID: #{params[:chat_channel_id] || params[:id]}")
      Rails.logger.error("[Lexicon] Error: #{exception.class.name}: #{exception.message}")
      Rails.logger.error("[Lexicon] Backtrace: #{exception.backtrace&.first(10)&.join("\n")}")

      # Re-raise to let Discourse handle it normally
      raise exception
    end
  end
end

