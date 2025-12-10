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
          chat_channel = create_chat_channel(category)
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
        create_chat: ActiveModel::Type::Boolean.new.cast(params[:create_chat])
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

    def create_chat_channel(category)
      return nil unless defined?(::Chat::Channel)

      Rails.logger.warn("[Lexicon] Creating chat channel for category #{category.id}...")

      # Use internal API call to create the channel
      # This avoids permission issues by using the same user context
      chat_params = {
        chatable_id: category.id,
        chatable_type: "Category",
        name: "General"
      }

      # Make internal HTTP request to Chat API endpoint
      # Use the same base URL but make an internal request
      base_url = Discourse.base_url
      uri = URI("#{base_url}/chat/api/channels.json")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      
      # Use the API credentials from the original request headers
      # This way we use the same authentication that was used to call this endpoint
      api_key = self.request.headers['Api-Key'] || self.request.headers['User-Api-Key']
      api_username = self.request.headers['Api-Username'] || current_user.username
      
      if api_key
        request['Api-Key'] = api_key
        request['Api-Username'] = api_username
      else
        # Fallback: try to find a UserApiKey for the current user
        user_api_key = UserApiKey.where(user_id: current_user.id, revoked_at: nil).order(created_at: :desc).first
        if user_api_key
          request['Api-Key'] = user_api_key.key
          request['Api-Username'] = current_user.username
        else
          # Last resort: use session-based auth by forwarding cookies from original request
          if self.request.headers['Cookie'].present?
            request['Cookie'] = self.request.headers['Cookie']
          end
        end
      end
      
      request.body = chat_params.to_json

      response = http.request(request)

      if response.code.to_i == 200 || response.code.to_i == 201
        result = JSON.parse(response.body)
        channel_id = result.dig('channel', 'id') || result['id']
        if channel_id
          Rails.logger.warn("[Lexicon] Chat channel created with ID: #{channel_id}")
          return ::Chat::Channel.find(channel_id)
        end
      end

      error_msg = begin
        parsed = JSON.parse(response.body)
        parsed['errors'] || parsed['error'] || parsed.to_s
      rescue
        response.body
      end
      Rails.logger.error("[Lexicon] Chat API returned #{response.code}: #{error_msg}")
      raise StandardError.new("Failed to create chat channel: #{error_msg}")
    rescue => e
      Rails.logger.error("[Lexicon] Error creating chat channel: #{e.message}")
      raise
    end
  end
end
