module DiscourseLexiconPlugin
  class ProjectsController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    
    def create
      Rails.logger.warn("[Lexicon] ProjectsController#create called")
      
      begin
        require 'category_creator'
        Rails.logger.warn("[Lexicon] 'category_creator' required")
      rescue LoadError => e
        Rails.logger.warn("[Lexicon] LoadError requiring category_creator: #{e.message}")
        # Try without require, maybe it's already there?
      end

      params.require(:name)
      Rails.logger.warn("[Lexicon] Params: #{params.inspect}")
      Rails.logger.warn("[Lexicon] Current User: #{current_user&.username}")
      
      # 1. Create the Category
      category_args = {
        name: params[:name],
        description: params[:description],
        color: params[:color] || '0088CC',
        text_color: 'FFFFFF',
        user: current_user
      }

      Rails.logger.warn("[Lexicon] Initializing CategoryCreator")
      creator = ::CategoryCreator.new(Discourse.system_user, category_args)
      
      Rails.logger.warn("[Lexicon] Creating category...")
      category = creator.create
      Rails.logger.warn("[Lexicon] Category created: #{category&.id}")

      if creator.errors.present?
        Rails.logger.warn("[Lexicon] Creator errors: #{creator.errors.full_messages}")
        return render_json_error(creator.errors.full_messages.join(", "))
      end

      # 2. Set Permissions
      Rails.logger.warn("[Lexicon] Setting permissions...")
      category.set_permissions({ 0 => 1 })
      category.save!

      # 3. Create Chat Channel
      chat_channel = nil
      if params[:create_chat] == 'true' && defined?(::Chat::Channel)
        Rails.logger.warn("[Lexicon] Creating chat channel...")
        chat_channel = ::Chat::Channel.create!(
          chatable: category,
          chatable_type: 'Category',
          name: "General",
          user: current_user
        )
        Rails.logger.warn("[Lexicon] Chat channel created: #{chat_channel&.id}")
      end

      render json: {
        category: {
          id: category.id,
          name: category.name,
          slug: category.slug,
          url: category.url
        },
        chat_channel_id: chat_channel&.id
      }
    rescue Exception => e
      Rails.logger.error("[Lexicon] ERROR: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render_json_error(e.message)
    end
  end
end
