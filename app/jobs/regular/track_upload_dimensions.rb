# frozen_string_literal: true

module Jobs
  class TrackUploadDimensions < ::Jobs::Base
    MAX_ATTEMPTS = 5
    RETRY_DELAY = 5.seconds

    def execute(args)
      return unless SiteSetting.lexicon_image_dimensions_enabled

      upload = Upload.find_by(id: args[:upload_id])
      return unless upload
      return unless DiscourseLexiconPlugin::UploadDimensionTracker.image_extension?(upload.extension)

      if upload.width.present? && upload.height.present?
        DiscourseLexiconPlugin::UploadDimensionTracker.handle_upload_created(upload)
      elsif args[:attempt].to_i < MAX_ATTEMPTS
        attempt = args[:attempt].to_i + 1
        Rails.logger.info("[Lexicon Plugin] Scheduling retry #{attempt} for upload #{upload.id} (missing dimensions)")
        Jobs.enqueue_in(RETRY_DELAY, :track_upload_dimensions, upload_id: upload.id, attempt:)
      else
        Rails.logger.warn("[Lexicon Plugin] Giving up tracking dimensions for upload #{upload.id} after #{MAX_ATTEMPTS} attempts")
      end
    rescue => e
      Rails.logger.error("[Lexicon Plugin] Error in TrackUploadDimensions job for upload #{args[:upload_id]}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise
    end
  end
end

