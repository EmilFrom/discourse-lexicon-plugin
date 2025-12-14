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
        # Skip middleware loading during rake tasks (including migrations)
        if defined?(Rake) && Rake.respond_to?(:application)
          begin
            if Rake.application.top_level_tasks.any?
              Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware during rake task") if defined?(Rails) && Rails.logger
              next
            end
          rescue
            # If we can't check rake tasks, continue anyway
          end
        end
        
        # Only add middleware if we have a proper Rails application
        unless app.config.respond_to?(:middleware)
          Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware - no middleware config") if defined?(Rails) && Rails.logger
          next
        end
        
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
        # This is especially important during migrations
        Rails.logger.debug("[Lexicon Plugin] Skipped CORS middleware: #{e.class} - #{e.message}") if defined?(Rails) && Rails.logger
      end
    end

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseLexiconPlugin::Engine, at: '/lexicon'
      end
    end
  end
end
