# frozen_string_literal: true

module DiscourseLexiconPlugin
  class CorsMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      origin = request.env['HTTP_ORIGIN']
      request_method = env['REQUEST_METHOD']
      path = env['PATH_INFO']

      # Handle OPTIONS preflight requests - must be done BEFORE calling the app
      # This ensures we catch OPTIONS requests before Discourse's router rejects them
      if request_method == 'OPTIONS'
        Rails.logger.info("[Lexicon CORS] Handling OPTIONS preflight for #{path} from origin #{origin}") if defined?(Rails) && Rails.logger
        return handle_preflight(origin)
      end

      # Process the request
      status, headers, body = @app.call(env)

      # Add CORS headers to response if origin is allowed
      # Add headers even for error responses to help with debugging
      if origin.present? && origin_allowed?(origin)
        headers['Access-Control-Allow-Origin'] = origin
        headers['Access-Control-Allow-Credentials'] = 'true'
        Rails.logger.debug("[Lexicon CORS] Added CORS headers for #{path} (status: #{status})") if defined?(Rails) && Rails.logger
      elsif origin.present?
        Rails.logger.debug("[Lexicon CORS] Origin #{origin} not allowed for #{path}") if defined?(Rails) && Rails.logger
      end

      [status, headers, body]
    end

    private

    def handle_preflight(origin)
      # Always allow preflight requests if origin is present and allowed
      # This prevents 404 errors on OPTIONS requests
      if origin.present? && origin_allowed?(origin)
        headers = {
          'Access-Control-Allow-Origin' => origin,
          'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS, PATCH',
          'Access-Control-Allow-Headers' => 'Content-Type, Authorization, User-Api-Key, User-Api-Client-Id, X-Requested-With, Accept',
          'Access-Control-Allow-Credentials' => 'true',
          'Access-Control-Max-Age' => '86400',
          'Content-Length' => '0',
          'Content-Type' => 'text/plain'
        }
        [200, headers, []]
      else
        # Even if origin is not allowed, return 200 to prevent 404 errors
        # The browser will still block the actual request due to missing CORS headers
        headers = {
          'Content-Length' => '0',
          'Content-Type' => 'text/plain'
        }
        [200, headers, []]
      end
    end

    def origin_allowed?(origin)
      return false unless origin.present?
      
      # Always allow localhost origins in development
      if origin.start_with?('http://localhost:') || origin.start_with?('http://127.0.0.1:')
        return true
      end
      
      allowed_origins = get_allowed_origins
      allowed_origins.any? do |allowed|
        if allowed.include?('*')
          pattern = allowed.gsub('*', '.*')
          origin.match?(/\A#{pattern}\z/)
        else
          origin == allowed
        end
      end
    end

    def get_allowed_origins
      # Get from site settings if available
      # Use safe navigation to avoid errors during migrations
      allowed = begin
        if defined?(SiteSetting) && SiteSetting.respond_to?(:allowed_user_api_auth_redirects)
          value = SiteSetting.allowed_user_api_auth_redirects
          value.present? ? value.split("\n") : []
        else
          []
        end
      rescue => e
        # During migrations or when SiteSetting is not available, return empty array
        Rails.logger.debug("[Lexicon CORS] Could not access SiteSetting: #{e.message}") if defined?(Rails)
        []
      end
      
      # Add common development origins (always allow localhost for development)
      allowed << "http://localhost:8081"
      allowed << "http://localhost:3000"
      allowed << "http://127.0.0.1:8081"
      allowed << "http://127.0.0.1:3000"
      # Also allow any localhost origin for development
      allowed << "http://localhost:*"
      allowed.compact.uniq
    end
  end
end

