RSpec.describe PostsController, 'GET history' do
  let(:post) { create(:post) }

  it "requires post" do
    login
    get :history, params: { id: -1 }
    expect(response).to redirect_to(continuities_url)
    expect(flash[:error]).to eq("Post could not be found.")
  end

  it "works logged out" do
    get :history, params: { id: post.id }
    expect(response.status).to eq(200)
  end

  it "works logged in" do
    login
    get :history, params: { id: post.id }
    expect(response.status).to eq(200)
  end

  it "works for reader account" do
    login_as(create(:reader_user))
    get :history, params: { id: post.id }
    expect(response).to have_http_status(200)
  end

  context "with render_view" do
    render_views

    it "loads the audits once however many versions there are, showing each version's content" do
      Post.auditing_enabled = true
      post.update!(content: 'second version')
      post.update!(content: 'third version')
      post.update!(content: 'fourth version')
      login_as(post.user)
      audit_queries = []
      callback = ->(*, payload) { audit_queries << payload[:sql] if payload[:sql].start_with?('SELECT') && payload[:sql].include?('FROM "audits"') }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get :history, params: { id: post.id } }

      expect(response.status).to eq(200)
      ['second version', 'third version', 'fourth version'].each { |content| expect(response.body).to include(content) }
      expect(audit_queries.size).to be <= 5
      Post.auditing_enabled = false
    end

    it "works" do
      Post.auditing_enabled = true
      post.update!(privacy: :access_list)
      post.update!(board: create(:board))
      post.update!(content: 'new content')

      login_as(post.user)

      get :history, params: { id: post.id }

      expect(response.status).to eq(200)
      Post.auditing_enabled = false
    end
  end
end
