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
      # Rails.logger.info("[Lexicon Plugin] Saved image dimension for upload #{upload.id}")
      dimension
    else
      # Rails.logger.warn("[Lexicon Plugin] Failed to persist dimensions: #{dimension.errors.full_messages.to_sentence}")
      nil
    end
  rescue => e
    Rails.logger.error("[Lexicon Plugin] Error in ensure_for_upload: #{e.message}")
    nil
  end

  # Lazy lookup with fallback to Upload table and OptimizedImage table
  def self.dimension_for_url(url)
    return nil if url.blank?

    # 1. Normalize URL: Create a relative version (strip protocol/host)
    #    Input: https://site.com/uploads/default/img.jpg -> Output: /uploads/default/img.jpg
    relative_url = url.sub(/^https?:\/\/[^\/]+/, '')

    # 2. Try Lexicon Cache (Check both absolute and relative keys)
    dimension = find_by(url: url) || find_by(url: relative_url)
    return format_dimension(dimension, url) if dimension

    # 3. Fallback: Try Upload Table (The original image)
    upload = Upload.find_by(url: relative_url) || Upload.find_by(url: url)
    if upload && upload.width && upload.height
      dimension = ensure_for_upload(upload)
      return format_dimension(dimension, url) if dimension
    end

    # 4. Fallback: Try OptimizedImage Table (Thumbnails/Resized versions)
    #    The frontend often requests optimized URLs which aren't in the 'uploads' table.
    optimized = OptimizedImage.find_by(url: relative_url) || OptimizedImage.find_by(url: url)
    if optimized && optimized.width && optimized.height
      # We calculate aspect ratio on the fly for optimized images
      return {
        url: url, # Return the requested URL so the frontend map key matches
        width: optimized.width,
        height: optimized.height,
        aspectRatio: optimized.width.to_f / optimized.height.to_f
      }
    end

    nil
  end

  # Bulk lookup
  def self.dimensions_for_urls(urls)
    return {} if urls.blank?

    # We don't strictly need Rails cache here if we want fresh data during debug,
    # but keeping it for performance is good.
    cache_key = "lexicon_image_dims:#{Digest::MD5.hexdigest(urls.sort.join(','))}"
    
    Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      result = {}

      urls.each do |url|
        # Perform the smart lookup defined above
        dims = dimension_for_url(url)
        result[url] = dims if dims
      end

      result
    end
  end

  private

  def calculate_aspect_ratio
    self.aspect_ratio = width.to_f / height.to_f if width && height && height > 0
  end

  def self.format_dimension(dim, requested_url = nil)
    return nil unless dim
    {
      url: requested_url || dim.url, # Use the requested URL to ensure map keys match
      width: dim.width,
      height: dim.height,
      aspectRatio: dim.aspect_ratio
    }
  end
end