# frozen_string_literal: true

class LexiconChatNotificationPreferencesController < ApplicationController
  requires_plugin 'discourse-lexicon-plugin'
  before_action :ensure_logged_in
  before_action :set_cors_headers
  before_action :handle_options_request
  
  # GET /lexicon/chat-notifications/:channel_id
  def show
    channel_id = params[:channel_id].to_i
    pref = LexiconChatNotificationPreference.push_enabled_for?(current_user.id, channel_id)
    
    render json: { 
      user_id: current_user.id,
      channel_id: channel_id,
      push_enabled: pref
    }
  end
  
  # PUT /lexicon/chat-notifications/:channel_id
  def update
    channel_id = params[:channel_id].to_i
    enabled = params[:push_enabled]
    
    if enabled.nil?
      return render json: { error: 'push_enabled parameter required' }, status: 400
    end
    
    pref = LexiconChatNotificationPreference.set_preference(
      current_user.id,
      channel_id,
      ActiveModel::Type::Boolean.new.cast(enabled)
    )
    
    render json: {
      user_id: pref.user_id,
      channel_id: pref.chat_channel_id,
      push_enabled: pref.push_enabled
    }
  end
  
  # GET /lexicon/chat-notifications (list all preferences for current user)
  def index
    prefs = LexiconChatNotificationPreference.where(user_id: current_user.id)
    
    render json: {
      preferences: prefs.map do |p|
        {
          user_id: p.user_id,
          channel_id: p.chat_channel_id,
          push_enabled: p.push_enabled
        }
      end
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

