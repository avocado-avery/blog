# _plugins/fix-og-image.rb
#
# Fixes the social-preview image URL (og:image / twitter:image) on posts.
#
# Why this is needed:
#   Posts set `image.path: banner.png` (relative) and rely on `media_subpath`
#   (see auto-media-subpath.rb) so the banner resolves to
#   /assets/img/posts/<slug>/banner.png on the page and in home cards.
#
#   jekyll-seo-tag, however, builds og:image from `image.path` by resolving the
#   relative path against the PAGE url, producing
#   /blog/posts/<slug>/banner.png  — a 404. It has no knowledge of media_subpath,
#   and Chirpy's attempt to patch it via string-replace does not match, so the
#   broken URL survives. Link unfurls (Discord, Slack, etc.) then show no image.
#
# This hook rewrites og:image and twitter:image in the rendered HTML to the
# correct absolute media URL. Keeping `image.path` relative is intentional —
# making it absolute double-prefixes media_subpath and breaks the on-page banner.

module FixOgImage
  META_RE = /(<meta (?:property|name)="(?:og:image|twitter:image)" content=")[^"]*(")/

  def self.correct_url(doc)
    image = doc.data["image"]
    return nil unless image

    path = image.is_a?(Hash) ? (image["path"] || image["src"]) : image
    return nil if path.nil? || path.empty? || path.include?("://")

    site = doc.site
    base = "#{site.config['url']}#{site.config['baseurl']}"

    # Relative paths hang off media_subpath; absolute ("/...") are used as-is.
    rel = path.start_with?("/") ? path : "#{doc.data['media_subpath']}/#{path}"

    # Collapse accidental double slashes without touching the scheme's "://".
    "#{base}/#{rel}".gsub(%r{(?<!:)/{2,}}, "/")
  end

  def self.patch(doc)
    return unless doc.output
    url = correct_url(doc)
    return unless url

    doc.output = doc.output.gsub(META_RE, "\\1#{url}\\2")
  end
end

Jekyll::Hooks.register :posts, :post_render do |post|
  FixOgImage.patch(post)
end
