# frozen_string_literal: true

module DiscourseLexiconPlugin
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME.freeze
    isolate_namespace DiscourseLexiconPlugin

    # Add CORS middleware early in the initialization process
    # This must be done before the middleware stack is frozen
    # The middleware class is loaded in plugin.rb before the engine
    initializer 'discourse_lexicon_plugin.cors_middleware', before: :build_middleware_stack do |app|
      begin
        # Insert before ActionDispatch::Static to catch all requests early
        if defined?(ActionDispatch::Static)
          app.config.middleware.insert_before ActionDispatch::Static, DiscourseLexiconPlugin::CorsMiddleware
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded before ActionDispatch::Static") if defined?(Rails) && Rails.logger
        else
          # Fallback: insert at the beginning
          app.config.middleware.insert 0, DiscourseLexiconPlugin::CorsMiddleware
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded at position 0") if defined?(Rails) && Rails.logger
        end
      rescue => e
        # Don't fail initialization if middleware can't be loaded
        Rails.logger.warn("[Lexicon Plugin] Failed to add CORS middleware: #{e.message}") if defined?(Rails) && Rails.logger
      end
    end

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseLexiconPlugin::Engine, at: '/lexicon'
      end
    end
  end
end
