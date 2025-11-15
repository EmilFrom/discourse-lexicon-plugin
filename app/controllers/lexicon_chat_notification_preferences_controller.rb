# frozen_string_literal: true

class LexiconChatNotificationPreferencesController < ApplicationController
  requires_plugin 'discourse-lexicon-plugin'
  before_action :ensure_logged_in
  
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
          channel_id: p.chat_channel_id,
          push_enabled: p.push_enabled
        }
      end
    }
  end
end

