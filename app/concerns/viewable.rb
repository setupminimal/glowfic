# frozen_string_literal: true
module Viewable
  extend ActiveSupport::Concern

  included do
    # Marks all the given posts read for the user, in a fixed number of queries rather than several per post
    def self.mark_all_read(posts, user)
      update_all_views(posts, user) { |post| post.mark_read(user) }
    end

    # Hides all the given posts for the user, in a fixed number of queries rather than several per post
    def self.ignore_all(posts, user)
      update_all_views(posts, user) { |post| post.ignore(user) }
    end

    def self.update_all_views(posts, user)
      posts = posts.to_a
      ActiveRecord::Associations::Preloader.new(records: posts, associations: [:board, :joined_post_authors]).call
      user.favorites.load
      existing = Post::View.where(user_id: user.id, post_id: posts.map(&:id)).index_by(&:post_id)
      posts.each do |post|
        existing[post.id]&.association(:post)&.target = post # saving a view validates its post
        post.preload_view(existing[post.id] || Post::View.new(post: post, user: user, defer_favorite_read: true))
        yield post
      end
      Post::View.mark_favorites_read(posts.filter_map(&:loaded_view).select(&:previously_new_record?))
      posts
    end
    private_class_method :update_all_views

    # Used by Post.mark_all_read and Post.ignore_all to give posts views they already found or built
    def preload_view(view)
      @view = view
    end

    def loaded_view
      @view
    end

    def mark_read(user, at_time: nil, force: false)
      view = view_for(user)

      if view.new_record?
        view.read_at = at_time || Time.now.in_time_zone
        return view.save
      end

      return view.update(read_at: Time.now.in_time_zone) unless at_time.present?
      return true if view.read_at && at_time <= view.read_at && !force
      view.update(read_at: at_time)
    end

    def ignore(user)
      view_for(user).update(ignored: true)
    end

    def unignore(user)
      view_for(user).update(ignored: false)
    end

    def ignored_by?(user)
      view_for(user).ignored
    end

    def last_read(user)
      view_for(user).read_at
    end

    def reload
      @view = nil
      @first_unread = nil
      super
    end

    private

    def view_for(user)
      @view ||= views.where(user_id: user.id).first_or_initialize
    end
  end
end
