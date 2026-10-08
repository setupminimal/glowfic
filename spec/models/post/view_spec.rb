RSpec.describe Post::View do
  describe "validations" do
    it "requires post" do
      view = build(:post_view, post: nil)
      expect(view).not_to be_valid
      expect(view.save).to eq(false)
    end

    it "requires user" do
      view = build(:post_view, user: nil)
      expect(view).not_to be_valid
      expect(view.save).to eq(false)
    end

    it "works with both user and post" do
      user = create(:user)
      post = create(:post)
      view = build(:post_view, user: user, post: post)
      expect(view).to be_valid
      expect(view.save).to eq(true)
      view.reload
      expect(view.user).to eq(user)
      expect(view.post).to eq(post)
    end

    it "is unique by post and user" do
      view = create(:post_view)
      new_view = build(:post_view, user: view.user, post: view.post)
      expect(new_view).not_to be_valid
      expect(new_view.save).to eq(false)
      expect {
        new_view.save!(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows one user to have multiple post views" do
      user = create(:user)
      view = create(:post_view, user: user)
      new_view = build(:post_view, user: user, post: create(:post))
      expect(new_view.post).not_to eq(view.post)
      expect(new_view).to be_valid
      expect(new_view.save).to eq(true)
    end

    it "allows one post to have multiple users in post views" do
      post = create(:post)
      view = create(:post_view, post: post)
      new_view = build(:post_view, post: post)
      expect(new_view.user).not_to eq(view.user)
      expect(new_view).to be_valid
      expect(new_view.save).to eq(true)
    end
  end

  describe "mark_favorite_read" do
    include ActiveJob::TestHelper

    let(:user) { create(:user) }
    let(:post) { nil }

    before(:each) do
      clear_enqueued_jobs
    end

    def make_post
      favorited_user = create(:user)
      create(:favorite, user: user, favorite: favorited_user)

      expect(user.notifications.count).to eq(0)
      post = perform_enqueued_jobs(only: NotifyFollowersOfNewPostJob) do
        create(:post, user: favorited_user)
      end
      expect(user.notifications.count).to eq(1)
      expect(user.notifications.first.unread).to be true
      post
    end

    def make_message(post, user)
      message = "#{post.user.username} has just posted a new post entitled #{post.subject} in the #{post.board.name} continuity."
      message += ScrapePostJob.view_post(post.id)
      create(:message, recipient: user, sender_id: 0, subject: "New post by #{post.user.username}", message: message)
    end

    it "updates message if unread" do
      post = create(:post)
      create(:favorite, user: user, favorite: post.user)
      make_message(post, user)
      post.mark_read(user)
      expect(user.messages.first.unread).to eq(false)
    end

    it "does not update message if read" do
      post = create(:post)
      create(:favorite, user: user, favorite: post.user)
      message = make_message(post, user)
      message.update!(unread: false)
      post.mark_read(user)
      expect(user.messages.first.unread).to eq(false)
    end

    it "updates notification if unread" do
      post = make_post
      post.mark_read(user)
      expect(user.notifications.first.unread).to eq(false)
    end

    context "when marking many posts read at once" do
      it "updates notification if unread" do
        post = make_post
        other = create(:post)
        Post.mark_all_read([post, other], user)
        expect(user.notifications.first.unread).to eq(false)
        expect(post.reload.last_read(user)).to be_present
        expect(other.reload.last_read(user)).to be_present
      end

      it "does not update notification if read" do
        post = make_post
        notification = user.notifications.first
        notification.update!(unread: false, read_at: 1.day.ago)
        expect { Post.mark_all_read([post], user) }.not_to change { notification.reload.read_at }
      end

      it "updates message for a followed user if unread" do
        post = create(:post)
        create(:favorite, user: user, favorite: post.user)
        make_message(post, user)
        Post.mark_all_read([post], user)
        expect(user.messages.first.unread).to eq(false)
      end

      it "updates message for a followed continuity if unread" do
        post = create(:post)
        create(:favorite, user: user, favorite: post.board)
        make_message(post, user)
        Post.mark_all_read([post], user)
        expect(user.messages.first.unread).to eq(false)
      end

      it "updates message for a followed coauthor if unread" do
        post = create(:post)
        coauthor = create(:reply, post: post).user
        create(:favorite, user: user, favorite: coauthor)
        make_message(post, user)
        Post.mark_all_read([post], user)
        expect(user.messages.first.unread).to eq(false)
      end

      it "leaves messages about posts the user doesn't follow alone" do
        post = create(:post)
        make_message(post, user)
        Post.mark_all_read([post], user)
        expect(user.messages.first.unread).to eq(true)
      end

      it "matches each post to its own message" do
        followed = create(:post)
        other = create(:post)
        create(:favorite, user: user, favorite: followed.user)
        create(:favorite, user: user, favorite: other.user)
        followed_message = make_message(followed, user)
        other_message = make_message(other, user)
        Post.mark_all_read([followed], user)
        expect(followed_message.reload.unread).to eq(false)
        expect(other_message.reload.unread).to eq(true)
      end

      it "does not mark notifications read for views that already existed" do
        post = make_post
        post.mark_read(user, at_time: 1.day.ago)
        post.update!(tagged_at: Time.zone.now)
        user.notifications.first.update!(unread: true)
        Post.mark_all_read([Post.find(post.id)], user)
        expect(user.notifications.first.unread).to eq(true)
      end
    end

    it "does not update notification if read" do
      post = make_post
      notification = user.notifications.first
      notification.update!(unread: false)
      post.mark_read(user)
      expect(user.notifications.first.unread).to eq(false)
    end
  end
end
