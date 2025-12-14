# frozen_string_literal: true

module DiscourseLexiconPlugin
  class CorsMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      origin = request.env['HTTP_ORIGIN']

      # Handle OPTIONS preflight requests
      if request.options?
        return handle_preflight(origin)
      end

      # Process the request
      status, headers, body = @app.call(env)

      # Add CORS headers to response if origin is allowed
      if origin.present? && origin_allowed?(origin)
        headers['Access-Control-Allow-Origin'] = origin
        headers['Access-Control-Allow-Credentials'] = 'true'
      end

      [status, headers, body]
    end

    private

    def handle_preflight(origin)
      if origin.present? && origin_allowed?(origin)
        headers = {
          'Access-Control-Allow-Origin' => origin,
          'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type, Authorization, User-Api-Key, User-Api-Client-Id, X-Requested-With',
          'Access-Control-Allow-Credentials' => 'true',
          'Access-Control-Max-Age' => '86400',
          'Content-Length' => '0'
        }
        [200, headers, []]
      else
        [403, {}, []]
      end
    end

    def origin_allowed?(origin)
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
      
      # Add common development origins
      allowed << "http://localhost:8081"
      allowed << "http://localhost:3000"
      allowed << "http://127.0.0.1:8081"
      allowed << "http://127.0.0.1:3000"
      allowed.compact.uniq
    end
  end
end

