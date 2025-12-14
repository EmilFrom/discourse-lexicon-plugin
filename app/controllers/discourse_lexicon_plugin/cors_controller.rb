# frozen_string_literal: true

module DiscourseLexiconPlugin
  class CorsController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :check_xhr
    skip_before_action :redirect_to_login_if_required
    
    def preflight
      origin = request.headers['Origin']
      
      # Always allow localhost origins in development
      allowed = if origin.present?
        if origin.start_with?('http://localhost:') || origin.start_with?('http://127.0.0.1:')
          true
        else
          allowed_origins = get_allowed_origins
          allowed_origins.any? do |allowed_origin|
            if allowed_origin.include?('*')
              pattern = allowed_origin.gsub('*', '.*')
              origin.match?(/\A#{pattern}\z/)
            else
              origin == allowed_origin
            end
          end
        end
      else
        false
      end
      
      if allowed
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS, PATCH'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, User-Api-Key, User-Api-Client-Id, X-Requested-With, Accept'
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Max-Age'] = '86400'
      end
      
      head :ok
    end
    
    private
    
    def get_allowed_origins
      allowed = SiteSetting.allowed_user_api_auth_redirects&.split("\n") || []
      allowed << "http://localhost:8081"
      allowed << "http://localhost:3000"
      allowed << "http://127.0.0.1:8081"
      allowed << "http://127.0.0.1:3000"
      allowed.compact.uniq
    end
  end
end

