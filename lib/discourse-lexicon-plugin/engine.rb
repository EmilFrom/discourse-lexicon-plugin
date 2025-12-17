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
    
    # Helper method to detect if we're in a migration/rake context
    def self.in_migration_context?
      return true if defined?(Rake) && Rake.respond_to?(:application) && Rake.application.top_level_tasks.any? rescue false
      return true if $0 && ($0.include?('rake') || ($0.include?('rails') && !$0.include?('server')))
      return true if ARGV.any? { |arg| arg.include?('db:migrate') || arg.include?('rake') }
      false
    rescue
      false
    end
    
    initializer 'discourse_lexicon_plugin.cors_middleware', before: :build_middleware_stack do |app|
      # Wrap entire initializer in rescue to prevent ANY errors from breaking migrations
      begin
        # Skip entirely if in migration context - don't even try to load middleware
        if DiscourseLexiconPlugin::Engine.in_migration_context?
          Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware initializer - migration context detected") if defined?(Rails) && Rails.logger
          return
        end
        
        log_path = '/var/discourse/shared/standalone/.cursor/debug.log'
        
        # #region agent log
        begin
          env_value = begin; ENV['RAILS_ENV']; rescue; 'unknown'; end
          argv0_value = begin; $0; rescue; 'unknown'; end
          File.open(log_path, 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug-v4', hypothesisId: 'H1,H6', location: 'engine.rb:24', message: 'Initializer entry', data: {already_added: @@cors_middleware_added, cors_middleware_defined: defined?(DiscourseLexiconPlugin::CorsMiddleware), rake_defined: defined?(Rake), env: env_value, argv0: argv0_value}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
          # Ignore log failures
        end
        # #endregion
        
        # If middleware class is not defined, skip entirely (likely during migrations)
        unless defined?(DiscourseLexiconPlugin::CorsMiddleware)
        # #region agent log
        begin
          File.open(log_path, 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H5', location: 'engine.rb:22', message: 'Skipping - CORS middleware class not defined', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
        end
        # #endregion
          return
        end
        
        # Prevent duplicate middleware insertion
        if @@cors_middleware_added
        # #region agent log
        begin
          File.open(log_path, 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H8', location: 'engine.rb:30', message: 'Skipping - already added', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
        end
        # #endregion
          return
        end
        
        # Comprehensive check to skip during migrations/rake tasks
        skip_middleware = false
      skip_reason = nil
      
      begin
        # Check 1: Rake tasks
        if defined?(Rake) && Rake.respond_to?(:application)
          begin
            tasks = Rake.application.top_level_tasks rescue []
            # #region agent log
            begin
              File.open(log_path, 'a') do |f|
                f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H1', location: 'engine.rb:42', message: 'Rake check', data: {has_tasks: tasks.any?, tasks: tasks}, timestamp: Time.now.to_i * 1000}.to_json)
              end
            rescue => e
            end
            # #endregion
            if tasks.any?
              skip_middleware = true
              skip_reason = "rake task: #{tasks.join(', ')}"
            end
          rescue => e
            # #region agent log
            begin
              File.open(log_path, 'a') do |f|
                f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H1', location: 'engine.rb:51', message: 'Rake check exception', data: {error: e.class.name, message: e.message}, timestamp: Time.now.to_i * 1000}.to_json)
              end
            rescue => e2
            end
            # #endregion
          end
        end
        
        # Check 2: Program name
        if $0 && ($0.include?('rake') || ($0.include?('rails') && !$0.include?('server')))
          skip_middleware = true
          skip_reason = "program name: #{$0}"
        end
        
        # Check 3: ARGV
        if ARGV.any? { |arg| arg.include?('db:migrate') || arg.include?('rake') }
          skip_middleware = true
          skip_reason = "ARGV: #{ARGV.join(' ')}"
        end
        
        # #region agent log
        begin
          File.open(log_path, 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H1', location: 'engine.rb:64', message: 'Skip decision', data: {skip_middleware: skip_middleware, skip_reason: skip_reason}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
        end
        # #endregion
        
        if skip_middleware
          Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware: #{skip_reason}") if defined?(Rails) && Rails.logger
          return
        end
        
        # Only add middleware if we have a proper Rails application
        unless app.config.respond_to?(:middleware)
          Rails.logger.debug("[Lexicon Plugin] Skipping CORS middleware - no middleware config") if defined?(Rails) && Rails.logger
          # #region agent log
          begin
            File.open(log_path, 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H3', location: 'engine.rb:74', message: 'Skipping - no middleware config', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
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
          File.open(log_path, 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H7,H8', location: 'engine.rb:82', message: 'Before middleware insert', data: {action_dispatch_static_defined: defined?(ActionDispatch::Static), middleware_already_present: middleware_already_present}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e
        end
        # #endregion
        
        if middleware_already_present
          @@cors_middleware_added = true
          # #region agent log
          begin
            File.open(log_path, 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H7', location: 'engine.rb:89', message: 'Middleware already in stack, skipping', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
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
            File.open(log_path, 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H4', location: 'engine.rb:99', message: 'Middleware inserted successfully', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
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
            File.open(log_path, 'a') do |f|
              f.puts({sessionId: 'debug-session', runId: 'migration-debug-v3', hypothesisId: 'H4', location: 'engine.rb:107', message: 'Middleware inserted at position 0', data: {}, timestamp: Time.now.to_i * 1000}.to_json)
            end
          rescue => e
          end
          # #endregion
        end
      rescue => e
        # Don't fail initialization if middleware can't be loaded
        # This is especially important during migrations - swallow ALL errors
        Rails.logger.debug("[Lexicon Plugin] Skipped CORS middleware: #{e.class} - #{e.message}") if defined?(Rails) && Rails.logger
        # #region agent log
        begin
          File.open(log_path, 'a') do |f|
            f.puts({sessionId: 'debug-session', runId: 'migration-debug-v4', hypothesisId: 'H1,H4', location: 'engine.rb:114', message: 'Exception in initializer - swallowed', data: {error: e.class.name, message: e.message, backtrace: e.backtrace.first(5)}, timestamp: Time.now.to_i * 1000}.to_json)
          end
        rescue => e2
        end
        # #endregion
        # Return silently - don't let this break migrations
        return
      end
    end

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseLexiconPlugin::Engine, at: '/lexicon'
      end
    end
  end
end
