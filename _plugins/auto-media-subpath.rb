# _plugins/auto-media-subpath.rb
#
# Gives every post a default image folder based on its filename slug, so you
# don't have to set `media_subpath` by hand.
#
#   _posts/2026-10-23-htb-cozyhosting.md
#     -> images resolve from /assets/img/posts/htb-cozyhosting/
#
# A `media_subpath` set in a post's front matter still wins.

module Jekyll
  class AutoMediaSubpath < Generator
    safe true
    priority :highest

    def generate(site)
      site.posts.docs.each do |post|
        next if post.data["media_subpath"]

        post.data["media_subpath"] = "/assets/img/posts/#{post.data['slug']}/"
      end
    end
  end
end
