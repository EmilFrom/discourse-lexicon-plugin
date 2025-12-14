# frozen_string_literal: true

module DiscourseLexiconPlugin
  class ExpoPnController < ::ApplicationController
    requires_plugin DiscourseLexiconPlugin::PLUGIN_NAME
    before_action :set_cors_headers
    before_action :handle_options_request

    def subscribe
      expo_pn_token = params.require(:push_notifications_token)
      application_name = params.require(:application_name)
      platform = params.require(:platform)
      experience_id = params.require(:experience_id)

      if %w[ios android].exclude?(platform)
        raise Discourse::InvalidParameters,
              "\"platform\" must be \"ios\" or \"android\"."
      end

      ExpoPnSubscription
        .where(expo_pn_token: expo_pn_token)
        .destroy_all

      record =
        ExpoPnSubscription.find_or_create_by(
          user_id: current_user.id,
          expo_pn_token: expo_pn_token,
          application_name: application_name,
          platform: platform,
          experience_id: experience_id,
          user_auth_token_id: current_user.user_auth_tokens&.last&.id
        )
      # return the expo_pn_token and user_id
      # so that the client can utilize it if needed
      render json: {
               expo_pn_token: record.expo_pn_token,
               user_id: record.user_id
             }
    end

    def unsubscribe
      expo_pn_token = params.require(:push_notifications_token)

      ExpoPnSubscription
        .where(expo_pn_token: expo_pn_token, user_id: current_user.id)
        .delete_all

      # return success if there are no error
      render json: {
               message: "success"
             }
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
