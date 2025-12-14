# frozen_string_literal: true

module DiscourseLexiconPlugin
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME.freeze
    isolate_namespace DiscourseLexiconPlugin

    # Add CORS middleware early in the initialization process
    # This must be done before the middleware stack is frozen
    # The middleware class is loaded in plugin.rb before the engine
    initializer 'discourse_lexicon_plugin.cors_middleware', before: :build_middleware_stack do |app|
      # #region agent log
      begin
        File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
          f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H1', location: 'engine.rb:11', message: 'Initializer entry', data: {rake_defined: defined?(Rake), app_responds_to_middleware: app.config.respond_to?(:middleware)}, timestamp: Time.now.to_i * 1000}.to_json)
        end
      rescue => e
        # Ignore log failures
      end
      # #endregion
      
      begin
        # Skip middleware loading during rake tasks (including migrations)
        if defined?(Rake) && Rake.respond_to?(:application)
          begin
            tasks = Rake.application.top_level_tasks rescue []
            # #region agent log
            begin
              File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
                f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H1', location: 'engine.rb:18', message: 'Rake check', data: {has_tasks: tasks.any?, tasks: tasks}, timestamp: Time.now.to_i * 1000}.to_json)
              end
            rescue => e
            end
            # #endregion
            if tasks.any?
              Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware during rake task") if defined?(Rails) && Rails.logger
              # #region agent log
              begin
                File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
                  f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H1', location: 'engine.rb:22', message: 'Skipping due to rake task', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
                end
              rescue => e
              end
              # #endregion
              next
            end
          rescue => e
            # #region agent log
            begin
              File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
                f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H1', location: 'engine.rb:30', message: 'Rake check exception', data: {error: e.class.name, message: e.message}, timestamp: Time.now.to_i * 1000}.to_json)
              end
            rescue => e2
            end
            # #endregion
            # If we can't check rake tasks, continue anyway
          end
        end
        
        # Only add middleware if we have a proper Rails application
        unless app.config.respond_to?(:middleware)
          Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware - no middleware config") if defined?(Rails) && Rails.logger
          # #region agent log
          begin
            File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H3', location: 'engine.rb:38', message: 'Skipping - no middleware config', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
            end
          rescue => e
          end
          # #endregion
          next
        end
        
        # #region agent log
        begin
          File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H4', location: 'engine.rb:42', message: 'Before middleware insert', data: {action_dispatch_static_defined: defined?(ActionDispatch::Static)}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
        end
        # #endregion
        
        # Insert before ActionDispatch::Static to catch all requests early
        if defined?(ActionDispatch::Static)
          app.config.middleware.insert_before ActionDispatch::Static, DiscourseLexiconPlugin::CorsMiddleware
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded before ActionDispatch::Static") if defined?(Rails) && Rails.logger
          # #region agent log
          begin
            File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H4', location: 'engine.rb:46', message: 'Middleware inserted successfully', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
            end
          rescue => e
          end
          # #endregion
        else
          # Fallback: insert at the beginning
          app.config.middleware.insert 0, DiscourseLexiconPlugin::CorsMiddleware
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded at position 0") if defined?(Rails) && Rails.logger
          # #region agent log
          begin
            File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H4', location: 'engine.rb:51', message: 'Middleware inserted at position 0', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
            end
          rescue => e
          end
          # #endregion
        end
      rescue => e
        # Don't fail initialization if middleware can't be loaded
        # This is especially important during migrations
        Rails.logger.debug("[Lexicon Plugin] Skipped CORS middleware: #{e.class} - #{e.message}") if defined?(Rails) && Rails.logger
        # #region agent log
        begin
          File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug', hypothesisId: 'H1,H4', location: 'engine.rb:56', message: 'Exception in initializer', data: {error: e.class.name, message: e.message, backtrace: e.backtrace.first(5)}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e2
        end
        # #endregion
      end
    end

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseLexiconPlugin::Engine, at: '/lexicon'
      end
    end
  end
end
