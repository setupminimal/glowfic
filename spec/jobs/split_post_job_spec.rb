RSpec.describe SplitPostJob do
  include ActiveJob::TestHelper

  before(:each) { clear_enqueued_jobs }

  let(:title) { 'test subject' }

  describe "validations" do
    let!(:reply) { create(:reply) }

    it "requires valid subject" do
      expect {
        SplitPostJob.perform_now(reply.id, '')
      }.to raise_error(RuntimeError, 'Invalid subject')
    end

    it "requires valid reply id" do
      expect {
        SplitPostJob.perform_now(-1, title)
      }.to raise_error(RuntimeError, "Couldn't find reply")
    end

    it "requires existing reply" do
      reply.destroy!
      expect {
        SplitPostJob.perform_now(reply.id, title)
      }.to raise_error(RuntimeError, "Couldn't find reply")
    end

    it "works" do
      expect {
        SplitPostJob.perform_now(reply.id, title)
      }.to change { Post.count }.by(1)

      post = Post.last
      expect(post.subject).to eq(title)
      expect(post.replies.count).to eq(0)
      expect(post.content).to eq(reply.content)
      expect(post.editor_mode).to eq(reply.editor_mode)
      expect(Reply.find_by(id: reply.id)).not_to be_present
    end
  end

  it "works with many replies" do
    user = create(:user)
    coauthor = create(:user)
    cameo = create(:user)
    new_user = create(:user)

    post = create(:post, user: user, unjoined_authors: [coauthor])
    create(:reply, post: post, user: cameo)
    100.times { |i| create(:reply, post: post, user: i.even? ? user : coauthor) }
    create(:reply, post: post, user: new_user)

    previous = post.replies.find_by(reply_order: 49)
    reply = post.replies.find_by(reply_order: 50)
    next_reply = post.replies.find_by(reply_order: 51)
    last = post.replies.last

    expect {
      SplitPostJob.perform_now(reply.id, title)
    }.to change { Post.count }.by(1).and change { Reply.count }.by(-1)

    post.reload
    expect(post.replies.count).to eq(50)
    expect(post.replies.ordered.last).to eq(previous)
    expect(post.last_reply_id).to eq(previous.id)
    expect(post.last_user_id).to eq(previous.user_id)
    expect(post.tagged_at).to eq(previous.created_at)
    expect(post.authors).to match_array([user, coauthor, cameo])

    new_post = Post.last
    expect(new_post.subject).to eq(title)
    expect(new_post.replies.count).to eq(51)
    expect(new_post.content).to eq(reply.content)
    expect(new_post.user_id).to eq(reply.user.id)
    expect(new_post.authors).to match_array([user, coauthor, new_user])
    expect(new_post.last_reply_id).to eq(last.id)
    expect(new_post.last_user_id).to eq(last.user_id)
    expect(new_post.tagged_at).to eq(last.created_at)
    expect(new_post.replies.ordered.first).to eq(next_reply)
    expect(Reply.find_by(id: reply.id)).not_to be_present
  end

  it "gives each author of the split replies the time of their first split reply without looking authors up one by one" do
    owner = create(:user)
    post = create(:post, user: owner)
    authors = create_list(:user, 4)
    first_reply = create(:reply, post: post, user: owner)
    firsts = {}
    # each author replies twice, interleaved; the later reply of each is created earlier in time than their first by order
    2.times do |round|
      authors.each_with_index do |author, index|
        created_at = Time.zone.now + (round == 0 ? index + 10 : -index - 100).hours
        reply = create(:reply, post: post, user: author, created_at: created_at)
        firsts[author.id] ||= reply.created_at
      end
    end
    lookups = []
    callback = lambda do |*, payload|
      sql = payload[:sql]
      lookups << sql if sql.start_with?('SELECT') && sql.match?(/FROM "(users|post_authors)" WHERE/) && sql.exclude?('IN (') && sql.exclude?('!=')
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { SplitPostJob.perform_now(first_reply.id, title) }

    new_post = Post.last
    authors.each do |author|
      expect(new_post.author_for(author).created_at).to be_within(1.second).of(firsts[author.id])
      expect(new_post.author_for(author).joined_at).to be_within(1.second).of(firsts[author.id])
    end
    expect(lookups.size).to be <= 3
  end

  it "copies original post's properties" do
    user = create(:user)
    board = create(:board)
    section = create(:board_section, board: board)
    setting = create(:setting, name: 'setting')
    warning = create(:content_warning, name: 'warning')
    label = create(:label, name: 'label')
    post = create(:post, user: user, board: board, section: section, setting_ids: [setting.id], content_warning_ids: [warning.id],
      label_ids: [label.id],)
    reply = create(:reply, post: post, user: user)

    expect {
      SplitPostJob.perform_now(reply.id, title)
    }.to change { Post.count }.by(1).and change { Reply.count }.by(-1)

    new_post = Post.last
    expect(new_post.board).to eq(board)
    expect(new_post.section).to eq(section)
    expect(new_post.setting_ids).to match_array([setting.id])
    expect(new_post.content_warning_ids).to match_array([warning.id])
    expect(new_post.label_ids).to match_array([label.id])
  end

  it "does not affect other posts" do
    user = create(:user)
    coauthor = create(:user)

    post = create(:post, user: user, unjoined_authors: [coauthor])
    10.times { |i| create(:reply, post: post, user: i.even? ? user : coauthor) }

    other_post = create(:post, num_replies: 10)

    expect {
      SplitPostJob.perform_now(post.replies.find_by(reply_order: 5).id, title)
    }.to change { Post.count }.by(1).and change { Reply.count }.by(-1)

    new_post = Post.last

    expect(post.replies.count).to eq(5)
    expect(new_post.replies.count).to eq(4)
    expect(other_post.replies.count).to eq(10)
  end
end
