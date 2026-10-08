RSpec.describe Post::Author do
  describe "validations" do
    it 'succeeds' do
      expect(create(:post_author)).to be_valid
    end

    it 'suceeds with multiple posts and one user' do
      user = create(:user)
      post1 = create(:post)
      post2 = create(:post)
      create(:post_author, user: user, post: post1)
      second = build(:post_author, user: user, post: post2)
      expect(second).to be_valid
      expect {
        second.save!
      }.not_to raise_error
    end

    it 'succeeds with one post and multiple users' do
      user1 = create(:user)
      user2 = create(:user)
      post = create(:post)
      create(:post_author, user: user1, post: post)
      second = build(:post_author, user: user2, post: post)
      expect(second).to be_valid
      expect {
        second.save!
      }.not_to raise_error
    end

    it "should require a user" do
      post_author = build(:post_author, user: nil)
      expect(post_author).not_to be_valid
      post_author.user = create(:user)
      expect(post_author).to be_valid
    end

    it "should require a post" do
      post_author = build(:post_author, post: nil)
      expect(post_author).not_to be_valid
      post_author.post = create(:post)
      expect(post_author).to be_valid
    end

    it "should enforce uniqueness for a specific user and post" do
      user = create(:user)
      post = create(:post)
      create(:post_author, user: user, post: post) # post_author

      new_author = build(:post_author, user: user, post: post)
      expect(new_author).not_to be_valid
      expect {
        new_author.save!
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "cache invalidation" do
    def block_selects
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/\ASELECT .* FROM "blocks"/) }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
      queries
    end

    it "clears the caches of users blocked by or blocking an author" do
      author = create(:user)
      blocked = create(:user)
      blocker = create(:user)
      create(:block, blocking_user: author, blocked_user: blocked, hide_me: :posts)
      create(:block, blocking_user: blocker, blocked_user: author, hide_them: :posts)
      blocked_key = Block.cache_string_for(blocked.id, 'blocked')
      hidden_key = Block.cache_string_for(blocker.id, 'hidden')
      Rails.cache.write(blocked_key, 'cached')
      Rails.cache.write(hidden_key, 'cached')

      create(:post_author, user: author)

      expect(Rails.cache.read(blocked_key)).to be_nil
      expect(Rails.cache.read(hidden_key)).to be_nil
    end

    it "clears the caches of every author changed in one transaction using a fixed number of queries" do
      post = create(:post)
      users = create_list(:user, 3)
      blocked = users.map do |user|
        create(:user).tap { |other| create(:block, blocking_user: user, blocked_user: other, hide_me: :posts) }
      end
      keys = blocked.map { |user| Block.cache_string_for(user.id, 'blocked') }
      keys.each { |key| Rails.cache.write(key, 'cached') }

      queries = block_selects do
        Post.transaction { users.each { |user| create(:post_author, post: post, user: user) } }
      end

      expect(queries.size).to eq(2)
      expect(keys.map { |key| Rails.cache.read(key) }).to all(be_nil)
    end

    it "still clears caches after an earlier transaction was rolled back" do
      author = create(:user)
      blocked = create(:user)
      create(:block, blocking_user: author, blocked_user: blocked, hide_me: :posts)
      key = Block.cache_string_for(blocked.id, 'blocked')

      Post.transaction do
        create(:post_author, user: author)
        raise ActiveRecord::Rollback
      end
      Rails.cache.write(key, 'cached')
      create(:post_author, user: author)

      expect(Rails.cache.read(key)).to be_nil
    end
  end
end
