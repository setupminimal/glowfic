# frozen_string_literal: true
class Post::Author < ApplicationRecord
  belongs_to :post, optional: false
  belongs_to :user, optional: false

  validates :user, uniqueness: { scope: :post }

  # users whose block caches need clearing, keyed by the transaction that changed their authorship
  PENDING_CACHE_USERS = ObjectSpace::WeakMap.new

  after_create :invalidate_caches
  after_destroy :invalidate_caches

  # Queues the user so that all the authors changed in one transaction have their caches cleared together
  # (in two queries) once the transaction commits, rather than in a pair of queries per author
  def invalidate_caches
    transaction = self.class.with_connection(&:current_transaction)
    pending = PENDING_CACHE_USERS[transaction]
    if pending
      pending << user_id
      return
    end

    pending = PENDING_CACHE_USERS[transaction] = Set[user_id]
    ActiveRecord.after_all_transactions_commit do
      PENDING_CACHE_USERS[transaction] = nil
      self.class.clear_cache_for(pending.to_a)
    end
  end

  def self.clear_cache_for(authors)
    blocked_ids = Block.where(blocking_user: authors, hide_me: [:posts, :all]).pluck(:blocked_user_id)
    blocked_ids.each { |blocked| Rails.cache.delete(Block.cache_string_for(blocked, 'blocked')) }
    hiding_ids = Block.where(blocked_user: authors, hide_them: [:posts, :all]).pluck(:blocking_user_id)
    hiding_ids.each { |blocker| Rails.cache.delete(Block.cache_string_for(blocker, 'hidden')) }
  end
end
