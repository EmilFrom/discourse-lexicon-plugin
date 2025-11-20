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

    # 1. Try strict lookup (Cache)
    # Normalize URL: Create a relative version (strip protocol/host)
    relative_url = url.sub(/^https?:\/\/[^\/]+/, '')
    
    dimension = find_by(url: url) || find_by(url: relative_url)
    return format_dimension(dimension, url) if dimension

    # 2. Try strict lookup (Optimized Image Table)
    optimized = OptimizedImage.find_by(url: relative_url)
    if optimized && optimized.width && optimized.height
      return {
        url: url,
        width: optimized.width,
        height: optimized.height,
        aspectRatio: optimized.width.to_f / optimized.height.to_f
      }
    end

    # 3. THE FIX: SHA1 Lookup (The "Fingerprint" method)
    # Extract the 40-character SHA1 hash from the URL
    sha1 = url[/[a-f0-9]{40}/]

    if sha1
      # Find the original upload by its hash
      upload = Upload.find_by(sha1: sha1)
      
      if upload && upload.width && upload.height
        # Calculate dimensions based on the requested URL if possible
        # (If the URL says 750x1000, trust that over the original 3000x4000)
        match = url.match(/_(\d+)x(\d+)\.[a-zA-Z]+$/)
        
        if match
          req_w = match[1].to_i
          req_h = match[2].to_i
          return {
            url: url,
            width: req_w,
            height: req_h,
            aspectRatio: req_w.to_f / req_h.to_f
          }
        else
          # Fallback: Return the Original's dimensions (Aspect Ratio is usually preserved)
          return format_dimension(ensure_for_upload(upload), url)
        end
      end
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