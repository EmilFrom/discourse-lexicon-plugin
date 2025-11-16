# frozen_string_literal: true

module DiscourseLexiconPlugin
  class ImageDimensionsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    def bulk_lookup
      urls = params.permit(urls: [])[:urls] || []
      
      if urls.empty?
        return render json: { dimensions: {} }
      end

      if urls.length > 100
        return render json: { error: "Too many URLs (max 100)" }, status: 400
      end

      dimensions = LexiconImageDimension.dimensions_for_urls(urls)
      
      render json: { dimensions: dimensions }
    end
  end
end

