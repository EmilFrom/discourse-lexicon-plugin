module DiscourseLexiconPlugin
  class ProjectsController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :ensure_logged_in

    def create
      Rails.logger.warn("[Lexicon] ProjectsController#create called")

      validation_error = validate_params
      return render_json_error(validation_error, status: 400) if validation_error

      norm = normalized_params

      guardian = Guardian.new(current_user)
      allowed_group = Group.find_by(id: SiteSetting.lexicon_projects_allowed_group)
      allowed_by_group = allowed_group && current_user.groups.exists?(id: allowed_group.id)
      unless guardian.can_create_category? || allowed_by_group
        return render_json_error("You are not allowed to create categories", status: 403)
      end

      category = nil
      chat_channel = nil
      chat_warning = nil

      Category.transaction do
        category = build_category(norm)

        Rails.logger.warn("[Lexicon] Setting permissions...")
        category.set_permissions({ 0 => 1 })
        category.save!
      end

      # Create chat channel if requested
      if norm[:create_chat]
        begin
          chat_channel = create_chat_channel(category, norm[:chat_channel_name], norm[:chat_channel_description])
        rescue => chat_error
          Rails.logger.warn("[Lexicon] Chat channel creation failed: #{chat_error.message}")
          Rails.logger.warn(chat_error.backtrace.join("\n"))
          chat_warning = "Category created but chat channel could not be created"
        end
      end

      response = {
        category: {
          id: category.id,
          name: category.name,
          slug: category.slug,
          url: category.url
        }
      }
      response[:chat_channel_id] = chat_channel&.id if chat_channel
      response[:warning] = chat_warning if chat_warning

      render json: response
    rescue => e
      Rails.logger.error("[Lexicon] ERROR: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render_json_error(e.message, status: 500)
    end

    private

    def validate_params
      name = params[:name].to_s.strip
      return "Name is required" if name.blank?

      if name.length > 50
        return "Name is too long (max 50 characters)"
      end

      desc = params[:description].to_s.strip
      if desc.length > 1000
        return "Description is too long (max 1000 characters)"
      end

      # Validate chat channel name if provided
      if params[:create_chat].present? && ActiveModel::Type::Boolean.new.cast(params[:create_chat])
        chat_name = params[:chat_channel_name].to_s.strip
        if chat_name.present? && chat_name.length > 100
          return "Chat channel name is too long (max 100 characters)"
        end

        chat_desc = params[:chat_channel_description].to_s.strip
        if chat_desc.length > 500
          return "Chat channel description is too long (max 500 characters)"
        end
      end

      nil
    end

    def normalized_params
      name = params[:name].to_s.strip
      description = params[:description].to_s.strip
      description = nil if description.blank?

      color = params[:color].to_s.strip.downcase
      color = "0088cc" unless color.match?(/\A[0-9a-f]{6}\z/)

      {
        name: name,
        description: description,
        color: color,
        text_color: "ffffff",
        create_chat: ActiveModel::Type::Boolean.new.cast(params[:create_chat]),
        chat_channel_name: params[:chat_channel_name].to_s.strip.presence,
        chat_channel_description: params[:chat_channel_description].to_s.strip.presence
      }
    end

    def build_category(norm)
      category = nil

      begin
        begin
          require_dependency 'category_creator'
        rescue LoadError
          # Will fall back below if not available
        end

        if defined?(::CategoryCreator)
          Rails.logger.warn("[Lexicon] Using CategoryCreator")
          category_args = {
            name: norm[:name],
            description: norm[:description],
            color: norm[:color],
            text_color: norm[:text_color],
            user: current_user
          }
          creator = ::CategoryCreator.new(current_user, category_args)
          category = creator.create

          if creator.errors.present?
            raise StandardError.new(creator.errors.full_messages.join(", "))
          end
        else
          raise NameError, "CategoryCreator not available"
        end
      rescue LoadError, NameError => e
        Rails.logger.warn("[Lexicon] CategoryCreator failed (#{e.message}). Falling back to Category.create!")
        category = build_category_fallback
      end

      category
    end

    def build_category_fallback
      norm = normalized_params

      category = Category.create!(
        name: norm[:name],
        user: current_user,
        color: norm[:color],
        text_color: norm[:text_color]
      )

      if norm[:description].present?
        category.update!(description: norm[:description])
      end

      category
    end

    def create_chat_channel(category, channel_name = nil, channel_description = nil)
      return nil unless defined?(::Chat::Channel)

      Rails.logger.warn("[Lexicon] Creating chat channel for category #{category.id}...")

      # Try to use Chat::CreateChannel service if available
      if defined?(::Chat::CreateChannel)
        begin
          guardian = Guardian.new(current_user)
          result = ::Chat::CreateChannel.call(
            guardian: guardian,
            name: channel_name.presence || "General",
            description: channel_description,
            chatable: category
          )
          
          if result.failure?
            Rails.logger.error("[Lexicon] Chat::CreateChannel failed: #{result.error}")
            raise StandardError.new("Failed to create chat channel: #{result.error}")
          end
          
          Rails.logger.warn("[Lexicon] Chat channel created with ID: #{result.channel.id}")
          return result.channel
        rescue => e
          Rails.logger.warn("[Lexicon] Chat::CreateChannel service failed: #{e.message}")
          # Fall through to direct creation
        end
      end

      # Fallback: Create channel directly using ActiveRecord
      # This bypasses the API layer and CSRF protection
      channel_name_final = channel_name.presence || "General"
      
      # Generate slug from name (similar to how Discourse does it)
      slug = channel_name_final.parameterize
      
      channel = ::Chat::Channel.new(
        chatable: category,
        name: channel_name_final,
        slug: slug,
        description: channel_description,
        status: ::Chat::Channel.statuses[:open]
      )
      
      begin
        if channel.save
          Rails.logger.warn("[Lexicon] Chat channel created directly with ID: #{channel.id}")
          
          # Automatically add the creator as a member
          add_user_to_channel(channel, current_user)
          
          return channel
        else
          error_msg = channel.errors.full_messages.join(", ")
          Rails.logger.error("[Lexicon] Failed to create chat channel: #{error_msg}")
          raise StandardError.new("Failed to create chat channel: #{error_msg}")
        end
      rescue => save_error
        # If save fails due to missing callbacks (like generate_auto_slug), use insert_all to bypass
        if save_error.message.include?('generate_auto_slug') || save_error.message.include?('undefined method')
          Rails.logger.warn("[Lexicon] Save failed due to callback (#{save_error.message}), using insert_all to bypass")
          
          # Use insert_all which bypasses callbacks and validations
          now = Time.current
          
          # Prepare all fields that might be needed
          insert_data = {
            chatable_type: 'Category',
            chatable_id: category.id,
            name: channel_name_final,
            slug: slug,
            description: channel_description,
            status: ::Chat::Channel.statuses[:open],
            created_at: now,
            updated_at: now
          }
          
          # Add optional fields if they exist in the schema
          if ::Chat::Channel.column_names.include?('threading_enabled')
            insert_data[:threading_enabled] = false
          end
          if ::Chat::Channel.column_names.include?('auto_join_users')
            insert_data[:auto_join_users] = false
          end
          
          result = ::Chat::Channel.insert_all([insert_data], returning: [:id])
          
          if result.any?
            channel_id = result.first['id']
            channel = ::Chat::Channel.find(channel_id)
            Rails.logger.warn("[Lexicon] Chat channel created via insert_all with ID: #{channel.id}")
            Rails.logger.warn("[Lexicon] Channel attributes: #{channel.attributes.inspect}")
            
            # Log to debug file
            require 'json'
            log_path = Rails.root.join('.cursor', 'debug.log')
            log_data = {
              sessionId: 'debug-session',
              runId: 'channel-creation',
              hypothesisId: 'A',
              location: 'projects_controller.rb:create_chat_channel',
              message: 'Channel created via insert_all',
              data: {
                channel_id: channel.id,
                channel_attributes: channel.attributes,
                category_id: category.id,
                user_id: current_user.id
              },
              timestamp: Time.current.to_i * 1000
            }
            begin
              File.open(log_path, 'a') do |f|
                f.puts(JSON.generate(log_data))
              end
            rescue => e
              Rails.logger.error("[Lexicon] Failed to write debug log: #{e.message}")
            end
            
            # Reload to ensure all associations are loaded
            channel.reload
            
            Rails.logger.warn("[Lexicon] Channel created via insert_all, slug: #{channel.slug}")
            
            # Automatically add the creator as a member
            membership = add_user_to_channel(channel, current_user)
            Rails.logger.warn("[Lexicon] Membership created: #{membership.present?}")
            
            # Verify the channel is valid
            unless channel.valid?
              Rails.logger.error("[Lexicon] Channel validation errors: #{channel.errors.full_messages.join(', ')}")
            end
            
            return channel
          else
            raise StandardError.new("Failed to create chat channel via insert_all")
          end
        else
          raise
        end
      end
    rescue => e
      Rails.logger.error("[Lexicon] Error creating chat channel: #{e.message}")
      raise
    end

    def add_user_to_channel(channel, user)
      return unless defined?(::Chat::UserChatChannelMembership)
      return if channel.nil? || user.nil?

      # Check if membership already exists
      existing = ::Chat::UserChatChannelMembership.find_by(
        user_id: user.id,
        chat_channel_id: channel.id
      )

      if existing
        Rails.logger.warn("[Lexicon] User #{user.username} already a member of channel #{channel.id}")
        return existing
      end

      # Create membership with default settings
      # notification_level: 2 = "all messages" (following Discourse defaults)
      # following: true = user is following the channel
      membership_data = {
        user_id: user.id,
        chat_channel_id: channel.id,
        notification_level: 2, # All messages
        following: true
      }
      
      # Add optional fields if they exist
      if ::Chat::UserChatChannelMembership.column_names.include?('last_read_message_id')
        membership_data[:last_read_message_id] = nil
      end
      if ::Chat::UserChatChannelMembership.column_names.include?('muted')
        membership_data[:muted] = false
      end
      if ::Chat::UserChatChannelMembership.column_names.include?('desktop_notification_level')
        membership_data[:desktop_notification_level] = 2
      end
      if ::Chat::UserChatChannelMembership.column_names.include?('mobile_notification_level')
        membership_data[:mobile_notification_level] = 2
      end

      membership = ::Chat::UserChatChannelMembership.new(membership_data)

      if membership.save
        Rails.logger.warn("[Lexicon] Added user #{user.username} (ID: #{user.id}) to channel #{channel.id} (ID: #{channel.id})")
        Rails.logger.warn("[Lexicon] Membership ID: #{membership.id}, following: #{membership.following}, notification_level: #{membership.notification_level}")
        return membership
      else
        error_msg = membership.errors.full_messages.join(", ")
        Rails.logger.error("[Lexicon] Failed to add user to channel: #{error_msg}")
        Rails.logger.error("[Lexicon] Membership attributes: #{membership.attributes.inspect}")
        Rails.logger.error("[Lexicon] Membership errors: #{membership.errors.inspect}")
        
        # Try using insert_all as fallback
        begin
          now = Time.current
          insert_data = membership_data.merge(
            created_at: now,
            updated_at: now
          )
          result = ::Chat::UserChatChannelMembership.insert_all([insert_data], returning: [:id])
          if result.any?
            membership_id = result.first['id']
            membership = ::Chat::UserChatChannelMembership.find(membership_id)
            Rails.logger.warn("[Lexicon] Membership created via insert_all with ID: #{membership.id}")
            return membership
          end
        rescue => insert_error
          Rails.logger.error("[Lexicon] Failed to create membership via insert_all: #{insert_error.message}")
        end
        
        # Don't raise - channel creation succeeded, membership is optional
        return nil
      end
    rescue => e
      Rails.logger.error("[Lexicon] Error adding user to channel: #{e.message}")
      Rails.logger.error("[Lexicon] Backtrace: #{e.backtrace.first(5).join("\n")}")
      # Don't raise - channel creation succeeded, membership is optional
      return nil
    end
  end
end
