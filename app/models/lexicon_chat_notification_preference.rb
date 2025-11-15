# frozen_string_literal: true

class LexiconChatNotificationPreference < ActiveRecord::Base
  belongs_to :user
  belongs_to :chat_channel, class_name: 'Chat::Channel'
  
  validates :user_id, presence: true
  validates :chat_channel_id, presence: true
  validates :user_id, uniqueness: { scope: :chat_channel_id }
  
  # Helper to check if user wants push for a channel (default true if no preference set)
  def self.push_enabled_for?(user_id, channel_id)
    pref = find_by(user_id: user_id, chat_channel_id: channel_id)
    pref.nil? ? true : pref.push_enabled
  end
  
  # Helper to set preference
  def self.set_preference(user_id, channel_id, enabled)
    pref = find_or_initialize_by(user_id: user_id, chat_channel_id: channel_id)
    pref.push_enabled = enabled
    pref.save!
    pref
  end
end

