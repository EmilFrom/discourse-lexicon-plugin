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
        next
      end

      # Skip if middleware class is not defined
      unless defined?(DiscourseLexiconPlugin::CorsMiddleware)
        next
      end

      # Skip if already added
      if @@cors_middleware_added
        next
      end

      # Only add middleware if we have a proper Rails application
      unless app.config.respond_to?(:middleware)
        next
      end

      begin
        # Check if middleware is already in the stack
        middleware_present = app.config.middleware.include?(DiscourseLexiconPlugin::CorsMiddleware) rescue false
        if middleware_present
          @@cors_middleware_added = true
          next
        end

        # Try to insert early in the middleware stack for CORS preflight handling
        # We need to be early to catch OPTIONS requests before the router rejects them
        inserted = false

        # Try inserting before Rack::Head (almost always present)
        begin
          if app.config.middleware.include?(Rack::Head)
            app.config.middleware.insert_before Rack::Head, DiscourseLexiconPlugin::CorsMiddleware
            inserted = true
            Rails.logger.info("[Lexicon Plugin] CORS middleware loaded before Rack::Head") if defined?(Rails) && Rails.logger
          end
        rescue => e
          # Continue to fallback
        end

        # Try inserting before ActionDispatch::Static if it exists in the stack
        if !inserted
          begin
            if app.config.middleware.include?(ActionDispatch::Static)
              app.config.middleware.insert_before ActionDispatch::Static, DiscourseLexiconPlugin::CorsMiddleware
              inserted = true
              Rails.logger.info("[Lexicon Plugin] CORS middleware loaded before ActionDispatch::Static") if defined?(Rails) && Rails.logger
            end
          rescue => e
            # Continue to fallback
          end
        end

        # Final fallback: use 'unshift' or 'insert 0' to prepend
        if !inserted
          begin
            app.config.middleware.unshift DiscourseLexiconPlugin::CorsMiddleware
            inserted = true
            Rails.logger.info("[Lexicon Plugin] CORS middleware loaded via unshift") if defined?(Rails) && Rails.logger
          rescue => e
            # Try insert 0 as last resort
            begin
              app.config.middleware.insert(0, DiscourseLexiconPlugin::CorsMiddleware)
              inserted = true
              Rails.logger.info("[Lexicon Plugin] CORS middleware loaded at position 0") if defined?(Rails) && Rails.logger
            rescue => e2
              Rails.logger.warn("[Lexicon Plugin] All middleware insertion methods failed") if defined?(Rails) && Rails.logger
            end
          end
        end

        @@cors_middleware_added = inserted
      rescue => e
        # Don't fail initialization if middleware can't be loaded
        Rails.logger.warn("[Lexicon Plugin] Failed to add CORS middleware: #{e.class} - #{e.message}") if defined?(Rails) && Rails.logger
      end
    end

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseLexiconPlugin::Engine, at: '/lexicon'
      end
    end
  end
end
