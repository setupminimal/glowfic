# frozen_string_literal: true
class Post::View < ApplicationRecord
  belongs_to :post, optional: false
  belongs_to :user, optional: false

  validates :post, uniqueness: { scope: :user }

  # set when the views are being created in bulk, in which case the caller uses Post::View.mark_favorites_read afterwards
  attr_accessor :defer_favorite_read

  after_create :mark_favorite_read, unless: :defer_favorite_read

  # Marks as read any notifications about the given (newly created) views' posts that the view's user has because
  # they follow the post's continuity or one of its authors. Does it for all the views at once, in a fixed number of queries.
  # Expects the views' posts to have their board and joined_post_authors loaded, and the user's favorites to be loaded.
  def self.mark_favorites_read(views)
    return if views.empty?
    user = views.first.user
    favorited = views.filter_map(&:post).select do |post|
      author_ids = post.joined_post_authors.map(&:user_id)
      user.favorites.any? do |favorite|
        (favorite.favorite_type == Board.polymorphic_name && favorite.favorite_id == post.board_id) ||
          (favorite.favorite_type == User.polymorphic_name && author_ids.include?(favorite.favorite_id))
      end
    end
    NotifyFollowersOfNewPostJob.notifications_about(favorited, user, unread_only: true).each_value do |message|
      message.update!(unread: false, read_at: Time.zone.now)
    end
  end

  private

  def mark_favorite_read
    favorited_continuity = user.favorites.where(favorite: post.board).exists?
    favorited_users = user.favorites.where(favorite: post.joined_authors).exists?
    return unless favorited_continuity || favorited_users

    message = NotifyFollowersOfNewPostJob.notification_about(post, user, unread_only: true)
    return unless message

    message.update!(unread: false, read_at: Time.zone.now)
  end
end
