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

      begin
        chat_channel = maybe_create_chat_channel(category, norm[:create_chat])
      rescue => chat_error
        Rails.logger.warn("[Lexicon] Chat channel creation failed: #{chat_error.message}")
        Rails.logger.warn(chat_error.backtrace.join("\n"))
        chat_warning = "Category created but chat channel could not be created"
      end

      render json: {
        category: {
          id: category.id,
          name: category.name,
          slug: category.slug,
          url: category.url
        },
        chat_channel_id: chat_channel&.id,
        warning: chat_warning
      }
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

    def maybe_create_chat_channel(category, create_chat_flag)
      return nil unless create_chat_flag
      return nil unless defined?(::Chat::Channel)
      # If CategoryCreator is unavailable, skip chat creation because Chat::Channel
      # may rely on slug generation callbacks not present in the fallback flow.
      return nil unless defined?(::CategoryCreator)

      Rails.logger.warn("[Lexicon] Creating chat channel...")
      ::Chat::Channel.create!(
        chatable: category,
        chatable_type: "Category",
        name: "General"
      )
    end
  end
end
