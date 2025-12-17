# frozen_string_literal: true

module DiscourseLexiconPlugin
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME.freeze
    isolate_namespace DiscourseLexiconPlugin

    # Track if middleware was already added to prevent duplicate insertion
    @@cors_middleware_added = false

    # Helper method to detect if we're in a migration/rake context
    def self.in_migration_context?
      # Check program name
      return true if $0 && ($0.include?('rake') || ($0.include?('rails') && !$0.include?('server')))
      # Check ARGV
      return true if ARGV.any? { |arg| arg.include?('db:migrate') || arg.include?('rake') }
      # Check Rake tasks
      if defined?(Rake) && Rake.respond_to?(:application)
        tasks = Rake.application.top_level_tasks rescue []
        return true if tasks.any?
      end
      false
    rescue
      false
    end

    initializer 'discourse_lexicon_plugin.cors_middleware', before: :build_middleware_stack do |app|
      # Skip entirely if in migration context
      if DiscourseLexiconPlugin::Engine.in_migration_context?
        Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware - migration context") if defined?(Rails) && Rails.logger
        next
      end

      # Skip if middleware class is not defined
      unless defined?(DiscourseLexiconPlugin::CorsMiddleware)
        Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware - class not defined") if defined?(Rails) && Rails.logger
        next
      end

      # Skip if already added
      if @@cors_middleware_added
        Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware - already added") if defined?(Rails) && Rails.logger
        next
      end

      # Only add middleware if we have a proper Rails application
      unless app.config.respond_to?(:middleware)
        Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware - no middleware config") if defined?(Rails) && Rails.logger
        next
      end

      begin
        # Check if middleware is already in the stack
        middleware_present = app.config.middleware.include?(DiscourseLexiconPlugin::CorsMiddleware) rescue false
        if middleware_present
          @@cors_middleware_added = true
          next
        end

        # Insert before ActionDispatch::Static to catch all requests early
        if defined?(ActionDispatch::Static)
          app.config.middleware.insert_before ActionDispatch::Static, DiscourseLexiconPlugin::CorsMiddleware
          @@cors_middleware_added = true
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded before ActionDispatch::Static") if defined?(Rails) && Rails.logger
        else
          # Fallback: insert at the beginning
          app.config.middleware.insert 0, DiscourseLexiconPlugin::CorsMiddleware
          @@cors_middleware_added = true
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded at position 0") if defined?(Rails) && Rails.logger
        end
      rescue => e
        # Don't fail initialization if middleware can't be loaded
        Rails.logger.debug("[Lexicon Plugin] Failed to add CORS middleware: #{e.class} - #{e.message}") if defined?(Rails) && Rails.logger
      end
    end

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseLexiconPlugin::Engine, at: '/lexicon'
      end
    end
  end
end
