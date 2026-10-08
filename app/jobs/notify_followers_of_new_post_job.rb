# frozen_string_literal: true
class NotifyFollowersOfNewPostJob < ApplicationJob
  queue_as :notifier

  def perform(post_id, user_id)
    post = Post.find_by(id: post_id)
    user = User.find_by(id: user_id)
    return unless post && user
    return if post.privacy_private?

    if post.user_id == user_id
      notify_of_post_creation(post, user)
    else
      notify_of_post_joining(post, user)
    end
  end

  def notify_of_post_creation(post, post_user)
    favorites = Favorite.where(favorite: post_user).or(Favorite.where(favorite: post.board))
    user_ids = favorites.select(:user_id).distinct.pluck(:user_id)
    users = filter_users(post, user_ids)

    return if users.empty?

    users.each { |user| Notification.notify_user(user, :new_favorite_post, post: post) }
  end

  def notify_of_post_joining(post, new_user)
    users = filter_users(post, Favorite.where(favorite: new_user).pluck(:user_id))
    return if users.empty?

    users.each do |user|
      next if already_notified_about?(post, user)
      Notification.notify_user(user, :joined_favorite_post, post: post)
    end
  end

  def filter_users(post, user_ids)
    user_ids &= PostViewer.where(post: post).pluck(:user_id) if post.privacy_access_list?
    user_ids -= post.author_ids
    user_ids -= blocked_user_ids(post)
    return [] unless user_ids.present?
    users = User.where(id: user_ids, favorite_notifications: true)
    users = users.full if post.privacy_full_accounts?
    users
  end

  def already_notified_about?(post, user)
    self.class.notification_about(post, user).present?
  end

  def self.notification_about(post, user, unread_only: false)
    notifications_about([post], user, unread_only: unread_only)[post.id]
  end

  # Finds, for each of the given posts, the notification (or older-style site message) telling the user about it.
  # Returns a hash of post id to notification, only containing posts that have one; same rules as notification_about
  def self.notifications_about(posts, user, unread_only: false)
    posts = posts.to_a
    return {} if posts.empty?

    found = {}
    notifications = Notification.where(post: posts, user: user, notification_type: [:new_favorite_post, :joined_favorite_post]).index_by(&:post_id)
    legacy = posts.reject do |post|
      notif = notifications[post.id]
      found[post.id] = notif if notif && (!unread_only || notif.unread)
      notif
    end
    return found if legacy.empty?

    messages = Message.where(recipient: user, sender_id: 0).where('created_at >= ?', legacy.map(&:created_at).min)
    messages = messages.unread if unread_only
    links = legacy.index_by { |post| ScrapePostJob.view_post(post.id) }
    messages.find_each do |notification|
      links.each do |link, post|
        next if found.key?(post.id) || notification.created_at < post.created_at
        found[post.id] = notification if notification.message.include?(link)
      end
      break if legacy.all? { |post| found.key?(post.id) }
    end
    found
  end

  def blocked_user_ids(post)
    blocked = Block.where(blocked_user_id: post.author_ids).where("hide_them >= ?", Block.hide_thems[:posts])
    blocked = blocked.select(:blocking_user_id).distinct.pluck(:blocking_user_id)
    blocking = Block.where(blocking_user_id: post.author_ids).where("hide_me >= ?", Block.hide_mes[:posts])
    blocking = blocking.select(:blocked_user_id).distinct.pluck(:blocked_user_id)
    (blocked + blocking).uniq
  end
end
