# frozen_string_literal: true

module DiscourseLexiconPlugin
  module TopicListItemSerializerExtension
    def image_url
      url = object.image_url
      return nil unless url

      # Return object with dimensions if available
      dimension = LexiconImageDimension.dimension_for_url(url)
      dimension || { url: url, width: nil, height: nil, aspectRatio: nil }
    end
  end
end

