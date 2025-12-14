# frozen_string_literal: true

module DiscourseLexiconPlugin
  class UserController < ::ApplicationController
    before_action :set_cors_headers
    before_action :handle_options_request

    def get_current_user
      render json: current_user
    end

    private

    def set_cors_headers
      origin = request.headers['Origin']
      return unless origin.present?

      allowed_origins = get_allowed_origins

      if origin_allowed?(origin, allowed_origins)
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, User-Api-Key, User-Api-Client-Id, X-Requested-With'
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Max-Age'] = '86400'
      end
    end

    def handle_options_request
      if request.method == 'OPTIONS'
        head :ok
        return
      end
    end

    def get_allowed_origins
      allowed = SiteSetting.allowed_user_api_auth_redirects&.split("\n") || []
      allowed << "http://localhost:8081"
      allowed << "http://localhost:3000"
      allowed << "http://127.0.0.1:8081"
      allowed << "http://127.0.0.1:3000"
      allowed.compact.uniq
    end

    def origin_allowed?(origin, allowed_origins)
      allowed_origins.any? do |allowed|
        if allowed.include?('*')
          pattern = allowed.gsub('*', '.*')
          origin.match?(/\A#{pattern}\z/)
        else
          origin == allowed
        end
      end
    end
  end
end
