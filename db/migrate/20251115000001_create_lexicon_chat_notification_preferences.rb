# frozen_string_literal: true

class CreateLexiconChatNotificationPreferences < ActiveRecord::Migration[7.0]
  def change
    create_table :lexicon_chat_notification_preferences do |t|
      t.integer :user_id, null: false
      t.integer :chat_channel_id, null: false
      t.boolean :push_enabled, null: false, default: true
      t.timestamps
    end
    
    add_index :lexicon_chat_notification_preferences, [:user_id, :chat_channel_id], 
              unique: true, 
              name: 'index_lexicon_chat_prefs_on_user_and_channel'
    add_index :lexicon_chat_notification_preferences, :user_id
    add_index :lexicon_chat_notification_preferences, :chat_channel_id
  end
end

