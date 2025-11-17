# frozen_string_literal: true

class LexiconImageDimension < ActiveRecord::Base
  belongs_to :upload

  validates :upload_id, presence: true, uniqueness: true
  validates :url, presence: true
  validates :width, presence: true, numericality: { greater_than: 0 }
  validates :height, presence: true, numericality: { greater_than: 0 }
  validates :aspect_ratio, presence: true, numericality: { greater_than: 0 }

  before_validation :calculate_aspect_ratio

  # Find or create with lazy fallback from Upload record
  def self.ensure_for_upload(upload)
    return nil unless upload&.id && upload.width.present? && upload.height.present?

    dimension = find_or_initialize_by(upload_id: upload.id)
    dimension.url = upload.url
    dimension.width = upload.width
    dimension.height = upload.height

    if dimension.save
      Rails.logger.info("[Lexicon Plugin] Saved image dimension for upload #{upload.id} (#{dimension.width}x#{dimension.height})")
      dimension
    else
      Rails.logger.warn("[Lexicon Plugin] Failed to persist dimensions for upload #{upload.id}: #{dimension.errors.full_messages.to_sentence}")
      nil
    end
  rescue => e
    Rails.logger.error("[Lexicon Plugin] Unexpected error creating image dimension for upload #{upload&.id}: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  # Lazy lookup with fallback to Upload table
  def self.dimension_for_url(url)
    return nil if url.blank?

    # Try cache first
    dimension = find_by(url: url)
    return format_dimension(dimension) if dimension

    # Fallback: find upload and cache it
    upload = Upload.find_by(url: url)
    if upload && upload.width && upload.height
      dimension = ensure_for_upload(upload)
      return format_dimension(dimension) if dimension
    end

    nil
  end

  # Bulk lookup with Rails cache
  def self.dimensions_for_urls(urls)
    return {} if urls.blank?

    cache_key = "lexicon_image_dims:#{Digest::MD5.hexdigest(urls.sort.join(','))}"
    
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      # Get cached dimensions
      cached = where(url: urls).index_by(&:url)
      result = {}

      urls.each do |url|
        if cached[url]
          result[url] = format_dimension(cached[url])
        else
          # Lazy fallback for missing dimensions
          result[url] = dimension_for_url(url)
        end
      end

      result.compact
    end
  end

  private

  def calculate_aspect_ratio
    self.aspect_ratio = width.to_f / height.to_f if width && height && height > 0
  end

  def self.format_dimension(dim)
    return nil unless dim
    {
      url: dim.url,
      width: dim.width,
      height: dim.height,
      aspectRatio: dim.aspect_ratio
    }
  end
end

