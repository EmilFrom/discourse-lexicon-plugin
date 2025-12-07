module DiscourseLexiconPlugin
  class ProjectsController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    
    def create
      render json: { status: 'ok' }
    end
  end
end
