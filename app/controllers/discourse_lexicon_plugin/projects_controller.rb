# require_dependency 'category_creator'

module DiscourseLexiconPlugin
  class ProjectsController < ::ApplicationController
    def create
      render json: { status: 'ok' }
    end
  end
end
