# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DiscourseLexiconPlugin::ChatMessageNotification do
  subject { described_class.handle(message, chat_channel, memberships) }

  let(:sender) { Fabricate(:user) }
  let(:recipient1) { Fabricate(:user) }
  let(:recipient2) { Fabricate(:user) }
  let(:chat_channel) { Fabricate(:chat_channel) }
  let(:message) { Fabricate(:chat_message, chat_channel: chat_channel, user: sender) }
  let(:expo_pn_data) { ExpoPushNotificationData.new }

  # Create membership objects for testing
  let(:sender_membership) do
    Chat::UserChatChannelMembership.new(
      user_id: sender.id,
      chat_channel: chat_channel,
      notification_level: 2
    )
  end

  let(:recipient1_membership) do
    Chat::UserChatChannelMembership.new(
      user_id: recipient1.id,
      chat_channel: chat_channel,
      notification_level: 2 # All messages
    )
  end

  let(:recipient2_membership) do
    Chat::UserChatChannelMembership.new(
      user_id: recipient2.id,
      chat_channel: chat_channel,
      notification_level: 1 # Mentions only
    )
  end

  let(:memberships) { [sender_membership, recipient1_membership, recipient2_membership] }

  context 'when notification_level is set to all messages (2)' do
    before do
      # Create subscriptions for all users
      ExpoPnSubscription.create!(expo_pn_data.subscription.merge(user_id: recipient1.id))
    end

    it 'enqueues a job for users with notification_level = 2' do
      expect { subject }.to change { Jobs::ExpoPushNotification.jobs.size }.by(1)

      job = Jobs::ExpoPushNotification.jobs.first
      expect(job['args'].first['user_id']).to eq(recipient1.id)
      expect(job['args'].first['payload']).to include(
        'notification_type' => 30, # ChatMessage type
        'excerpt' => message.message,
        'username' => sender.username,
        'post_url' => "/c/#{chat_channel.id}/#{message.id}",
        'is_chat' => true,
        'is_thread' => message.thread_id.present?,
        'channel_name' => chat_channel.name
      )
    end
  end

  context 'when notification_level is set to mentions only (1)' do
    before do
      ExpoPnSubscription.create!(expo_pn_data.subscription.merge(user_id: recipient2.id))
    end

    let(:memberships) { [recipient2_membership] }

    it 'does not enqueue a job for users with notification_level = 1' do
      expect { subject }.not_to(change { Jobs::ExpoPushNotification.jobs.size })
    end
  end

  context 'when sender is in the memberships list' do
    before do
      ExpoPnSubscription.create!(expo_pn_data.subscription.merge(user_id: sender.id))
      ExpoPnSubscription.create!(expo_pn_data.subscription.merge(user_id: recipient1.id))
    end

    it 'does not send notification to the sender' do
      expect { subject }.to change { Jobs::ExpoPushNotification.jobs.size }.by(1)

      job = Jobs::ExpoPushNotification.jobs.first
      # Verify only recipient1 gets the notification, not sender
      expect(job['args'].first['user_id']).to eq(recipient1.id)
      expect(job['args'].first['user_id']).not_to eq(sender.id)
    end
  end

  context 'when message is a thread message' do
    let(:thread) { Fabricate(:chat_thread, channel: chat_channel) }
    let(:message) { Fabricate(:chat_message, chat_channel: chat_channel, user: sender, thread: thread) }

    before do
      ExpoPnSubscription.create!(expo_pn_data.subscription.merge(user_id: recipient1.id))
    end

    it 'includes thread information in the payload' do
      expect { subject }.to change { Jobs::ExpoPushNotification.jobs.size }.by(1)

      job = Jobs::ExpoPushNotification.jobs.first
      expect(job['args'].first['payload']).to include(
        'is_thread' => true,
        'post_url' => "/c/#{chat_channel.id}/#{thread.id}/#{message.id}"
      )
    end
  end

  context 'when user has no expo push subscription' do
    let(:memberships) { [recipient1_membership] }

    it 'does not enqueue a job' do
      expect { subject }.not_to(change { Jobs::ExpoPushNotification.jobs.size })
    end
  end

  context 'with multiple users having all messages enabled' do
    let(:recipient3) { Fabricate(:user) }
    let(:recipient3_membership) do
      Chat::UserChatChannelMembership.new(
        user_id: recipient3.id,
        chat_channel: chat_channel,
        notification_level: 2
      )
    end

    let(:memberships) { [sender_membership, recipient1_membership, recipient3_membership] }

    before do
      ExpoPnSubscription.create!(expo_pn_data.subscription.merge(user_id: recipient1.id))
      ExpoPnSubscription.create!(expo_pn_data.subscription.merge(user_id: recipient3.id))
    end

    it 'enqueues jobs for all eligible users' do
      expect { subject }.to change { Jobs::ExpoPushNotification.jobs.size }.by(2)

      user_ids = Jobs::ExpoPushNotification.jobs.map { |job| job['args'].first['user_id'] }
      expect(user_ids).to contain_exactly(recipient1.id, recipient3.id)
      expect(user_ids).not_to include(sender.id)
    end
  end
end

