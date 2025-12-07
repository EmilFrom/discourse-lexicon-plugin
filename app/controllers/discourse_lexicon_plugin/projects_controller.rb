module DiscourseLexiconPlugin
  class ProjectsController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    
    def create
      Rails.logger.warn("[Lexicon] ProjectsController#create called")
      
      category = nil
      
      begin
        # Try the "Right Way" first
        require 'category_creator'
        Rails.logger.warn("[Lexicon] 'category_creator' required")
        
        category_args = {
          name: params[:name],
          description: params[:description],
          color: params[:color] || '0088CC',
          text_color: 'FFFFFF',
          user: current_user
        }
        
        Rails.logger.warn("[Lexicon] Using CategoryCreator")
        creator = ::CategoryCreator.new(Discourse.system_user, category_args)
        category = creator.create
        
        if creator.errors.present?
          return render_json_error(creator.errors.full_messages.join(", "))
        end
        
      rescue LoadError, NameError => e
        Rails.logger.warn("[Lexicon] CategoryCreator failed (#{e.message}). Falling back to Category.create!")
        
        # Fallback: Direct ActiveRecord creation
        category = Category.create!(
          name: params[:name],
          user: current_user,
          color: params[:color] || '0088CC',
          text_color: 'FFFFFF'
        )
        
        # Manually create description post if needed (simplified)
        if params[:description].present?
          category.update!(description: params[:description])
        end
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
    rescue => e
      Rails.logger.error("[Lexicon] ERROR: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render_json_error(e.message)
    end
  end
end
