# frozen_string_literal: true

module DiscourseLexiconPlugin
  class UploadDimensionTracker
    ALLOWED_EXTENSIONS = %w[jpg jpeg png gif webp].freeze

    def self.image_extension?(extension)
      extension&.in?(ALLOWED_EXTENSIONS)
    end

    def self.handle_upload_created(upload)
      return unless upload&.id
      return unless image_extension?(upload.extension)

      start_time = Time.now
      result = LexiconImageDimension.ensure_for_upload(upload)
      duration = ((Time.now - start_time) * 1000).round(2)

      if result
        Rails.logger.info("[Lexicon Plugin] ✓ Tracked dimensions for upload #{upload.id} in #{duration}ms")
      else
        Rails.logger.warn("[Lexicon Plugin] ✗ Failed to track dimensions for upload #{upload.id}")
      end

      result
    end
  end
end

