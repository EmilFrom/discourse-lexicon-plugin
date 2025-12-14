# frozen_string_literal: true

module DiscourseLexiconPlugin
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME.freeze
    isolate_namespace DiscourseLexiconPlugin

    # Add CORS middleware early in the initialization process
    # This must be done before the middleware stack is frozen
    # The middleware class is loaded in plugin.rb before the engine
    # Use a class variable to track if middleware was already added to prevent duplicate insertion
    @@cors_middleware_added = false
    
    initializer 'discourse_lexicon_plugin.cors_middleware', before: :build_middleware_stack do |app|
      # #region agent log
      begin
        File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
          f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H6,H7,H8', location: 'engine.rb:12', message: 'Initializer entry', data: {already_added: @@cors_middleware_added, rake_defined: defined?(Rake), app_responds_to_middleware: app.config.respond_to?(:middleware), thread_id: Thread.current.object_id}, timestamp: Time.now.to_i * 1000}.to_json)
        end
      rescue => e
        # Ignore log failures
      end
      # #endregion
      
      # Prevent duplicate middleware insertion
      if @@cors_middleware_added
        # #region agent log
        begin
          File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H8', location: 'engine.rb:20', message: 'Skipping - already added', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
        end
        # #endregion
        return
      end
      
      begin
        # Skip middleware loading during rake tasks (including migrations)
        if defined?(Rake) && Rake.respond_to?(:application)
          begin
            tasks = Rake.application.top_level_tasks rescue []
            # #region agent log
            begin
              File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
                f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H1', location: 'engine.rb:30', message: 'Rake check', data: {has_tasks: tasks.any?, tasks: tasks}, timestamp: Time.now.to_i * 1000}.to_json)
              end
            rescue => e
            end
            # #endregion
            if tasks.any?
              Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware during rake task") if defined?(Rails) && Rails.logger
              # #region agent log
              begin
                File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
                  f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H1', location: 'engine.rb:34', message: 'Skipping due to rake task', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
                end
              rescue => e
              end
              # #endregion
              return
            end
          rescue => e
            # #region agent log
            begin
              File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
                f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H1', location: 'engine.rb:42', message: 'Rake check exception', data: {error: e.class.name, message: e.message}, timestamp: Time.now.to_i * 1000}.to_json)
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
              f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H3', location: 'engine.rb:50', message: 'Skipping - no middleware config', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
            end
          rescue => e
          end
          # #endregion
          return
        end
        
        # Check if middleware is already in the stack
        middleware_already_present = begin
          app.config.middleware.include?(DiscourseLexiconPlugin::CorsMiddleware)
        rescue
          false
        end
        
        # #region agent log
        begin
          File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H7,H8', location: 'engine.rb:58', message: 'Before middleware insert', data: {action_dispatch_static_defined: defined?(ActionDispatch::Static), middleware_already_present: middleware_already_present, middleware_stack_size: app.config.middleware.size rescue 'unknown'}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
        end
        # #endregion
        
        if middleware_already_present
          @@cors_middleware_added = true
          # #region agent log
          begin
            File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H7', location: 'engine.rb:65', message: 'Middleware already in stack, skipping', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
            end
          rescue => e
          end
          # #endregion
          return
        end
        
        # Insert before ActionDispatch::Static to catch all requests early
        if defined?(ActionDispatch::Static)
          app.config.middleware.insert_before ActionDispatch::Static, DiscourseLexiconPlugin::CorsMiddleware
          @@cors_middleware_added = true
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded before ActionDispatch::Static") if defined?(Rails) && Rails.logger
          # #region agent log
          begin
            File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H4', location: 'engine.rb:73', message: 'Middleware inserted successfully', data: {new_stack_size: app.config.middleware.size rescue 'unknown'}, timestamp: Time.now.to_i * 1000}.to_json)
            end
          rescue => e
          end
          # #endregion
        else
          # Fallback: insert at the beginning
          app.config.middleware.insert 0, DiscourseLexiconPlugin::CorsMiddleware
          @@cors_middleware_added = true
          Rails.logger.info("[Lexicon Plugin] CORS middleware loaded at position 0") if defined?(Rails) && Rails.logger
          # #region agent log
          begin
            File.open('/Users/emil/Documents/Taenketanken/discourse/.cursor/debug.log', 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H4', location: 'engine.rb:81', message: 'Middleware inserted at position 0', data: {new_stack_size: app.config.middleware.size rescue 'unknown'}, timestamp: Time.now.to_i * 1000}.to_json)
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
            f.puts({sessionId: 'debug-session', runId: 'loop-debug', hypothesisId: 'H1,H4', location: 'engine.rb:88', message: 'Exception in initializer', data: {error: e.class.name, message: e.message, backtrace: e.backtrace.first(5)}, timestamp: Time.now.to_i * 1000}.to_json)
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
