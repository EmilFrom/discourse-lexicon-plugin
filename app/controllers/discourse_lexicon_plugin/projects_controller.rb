require_dependency 'category_creator'

module DiscourseLexiconPlugin
  class ProjectsController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :ensure_logged_in

    def create
      Rails.logger.warn("[Lexicon] ProjectsController#create called")

      validation_error = validate_params
      return render_json_error(validation_error, status: 400) if validation_error

      guardian = Guardian.new(current_user)
      unless guardian.can_create_category?
        return render_json_error("You are not allowed to create categories", status: 403)
      end

      category = build_category

      Rails.logger.warn("[Lexicon] Setting permissions...")
      category.set_permissions({ 0 => 1 })
      category.save!

      chat_channel = maybe_create_chat_channel(category)

      render json: {
        category: {
          id: category.id,
          name: category.name,
          slug: category.slug,
          url: category.url
        },
        chat_channel_id: chat_channel&.id
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

      if params[:color].present?
        return "Color must be a 6 character hex value" unless params[:color].match?(/\A[0-9a-fA-F]{6}\z/)
      end

      if params[:description].present? && params[:description].to_s.length > 1000
        return "Description is too long (max 1000 characters)"
      end

      nil
    end

    def build_category
      category = nil

      begin
        if defined?(::CategoryCreator)
          Rails.logger.warn("[Lexicon] Using CategoryCreator")
          category_args = {
            name: params[:name],
            description: params[:description],
            color: params[:color] || "0088CC",
            text_color: "FFFFFF",
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
      Category.transaction do
        category = Category.create!(
          name: params[:name],
          user: current_user,
          color: params[:color] || "0088CC",
          text_color: "FFFFFF"
        )

        if params[:description].present?
          category.update!(description: params[:description])
        end

        category
      end
    end

    def maybe_create_chat_channel(category)
      create_chat = ActiveModel::Type::Boolean.new.cast(params[:create_chat])
      return nil unless create_chat
      return nil unless defined?(::Chat::Channel)

      Rails.logger.warn("[Lexicon] Creating chat channel...")
      ::Chat::Channel.create!(
        chatable: category,
        chatable_type: "Category",
        name: "General"
      )
    end
  end
end
