require_dependency 'category_creator'

module DiscourseLexiconPlugin
  class ProjectsController < ::ApplicationController

    def create
      params.require(:name)
      
      # 1. Create the Category
      # We use the system user to bypass permission checks, but we set the creator as the current user
      category_args = {
        name: params[:name],
        description: params[:description],
        color: params[:color] || '0088CC',
        text_color: 'FFFFFF',
        user: current_user
      }

      # Use CategoryCreator to handle all the heavy lifting (slugs, validation, etc.)
      creator = ::CategoryCreator.new(Discourse.system_user, category_args)
      category = creator.create

      if creator.errors.present?
        return render_json_error(creator.errors.full_messages.join(", "))
      end

      # 2. Set Permissions (Everyone can See/Reply/Create)
      # 0 = Everyone
      # 1 = Full (See, Create, Reply)
      category.set_permissions({ 0 => 1 })
      category.save!

      # 3. (Optional) Create Chat Channel
      chat_channel = nil
      if params[:create_chat] == 'true' && defined?(::Chat::Channel)
        # Create a category channel
        chat_channel = ::Chat::Channel.create!(
          chatable: category,
          chatable_type: 'Category',
          name: "General",
          user: current_user
        )
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
      render_json_error(e.message)
    end
  end
end
