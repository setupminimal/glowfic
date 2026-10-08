RSpec.describe BookmarksController, 'GET search' do
  context "no search" do
    it "works logged out" do
      get :search
      expect(response).to have_http_status(200)
      expect(assigns(:page_title)).to eq('Search Bookmarks')
      expect(assigns(:search_results)).to be_nil
      expect(assigns(:user)).to be_nil # this will be dynamically loaded
      expect(assigns(:posts)).to be_nil
    end

    it "works logged in" do
      login
      get :search
      expect(response).to have_http_status(200)
      expect(assigns(:page_title)).to eq('Search Bookmarks')
      expect(assigns(:search_results)).to be_nil
      expect(assigns(:user)).to be_nil # this will be dynamically loaded
      expect(assigns(:posts)).to be_nil
    end

    it "works for reader account" do
      login_as(create(:reader_user))
      get :search
      expect(response).to have_http_status(200)
    end

    it "handles invalid user" do
      get :search, params: { user_id: -1 }
      expect(response).to have_http_status(200)
      expect(assigns(:page_title)).to eq('Search Bookmarks')
      expect(assigns(:user)).to be_nil
      expect(assigns(:search_results)).to be_nil
    end
  end

  context "searching" do
    context "with many bookmarks" do
      render_views

      it "shows each bookmarked reply's icon and character name without querying per bookmark" do
        user = create(:user)
        replies = Array.new(3) do |index|
          author = create(:user)
          character = create(:character, user: author, name: "Character #{index}")
          calias = create(:alias, character: character, name: "Alias #{index}") if index.odd?
          reply = create(:reply, user: author, character: character, character_alias: calias,
            icon: create(:icon, user: author, keyword: "icon#{index}"),)
          create(:bookmark, user: user, reply: reply, post: reply.post, public: true)
          reply
        end
        expect_no_n_plus_one { get :search, params: { commit: true, user_id: user.id } }
        expect(response).to have_http_status(200)
        expect(assigns(:search_results).size).to eq(3)
        replies.each_with_index do |reply, index|
          expect(response.body).to include(reply.icon.keyword)
          expect(response.body).to include(index.odd? ? "Alias #{index}" : "Character #{index}")
        end
      end

      it "leaves icons out of the condensed view" do
        user = create(:user)
        author = create(:user)
        reply = create(:reply, user: author, icon: create(:icon, user: author, keyword: 'hiddenicon'))
        create(:bookmark, user: user, reply: reply, post: reply.post, public: true)
        get :search, params: { commit: true, user_id: user.id, condensed: true }
        expect(response.body).not_to include('hiddenicon')
      end
    end

    it "finds nothing when no arguments given" do
      create_list(:bookmark, 2)
      get :search, params: { commit: true }
      expect(assigns(:search_results)).to be_nil
    end

    it "finds nothing when user is not selected" do
      bookmarks = create_list(:bookmark, 2)
      get :search, params: { commit: true, post_id: [bookmarks[0].post_id, bookmarks[1].post_id] }
      expect(assigns(:search_results)).to be_nil
    end

    it "doesn't find private bookmarks" do
      bookmarks = create_list(:bookmark, 2)
      get :search, params: { commit: true, user_id: bookmarks[0].user_id }
      search_results = assigns(:search_results)
      expect(search_results).not_to be_nil
      expect(search_results.length).to eq(0)
    end

    it "finds public bookmarks" do
      bookmarks = create_list(:bookmark, 2)
      bookmarks[0].user.update!(public_bookmarks: true)
      get :search, params: { commit: true, user_id: bookmarks[0].user_id }
      search_results = assigns(:search_results)
      expect(search_results).not_to be_nil
      expect(search_results.length).to eq(1)
    end

    it "finds own bookmarks" do
      bookmarks = create_list(:bookmark, 2)
      login_as(bookmarks[0].user)
      get :search, params: { commit: true, user_id: bookmarks[0].user_id }
      search_results = assigns(:search_results)
      expect(search_results).not_to be_nil
      expect(search_results.length).to eq(1)
    end

    it "filters user" do
      user = create(:user, public_bookmarks: true)
      replies = create_list(:reply, 5)
      bookmark0 = create(:bookmark, reply: replies[0], user: user)
      bookmark1 = create(:bookmark, reply: replies[1], user: user)
      create(:bookmark, reply: replies[2])
      create(:bookmark, reply: replies[3])
      create(:bookmark, reply: replies[4])

      get :search, params: { commit: true, user_id: user.id }
      search_results = assigns(:search_results)
      expect(search_results.length).to eq(2)
      expect(search_results).to match_array([replies[0], replies[1]])
      expect(search_results[0].bookmark_id).to eq(bookmark0.id)
      expect(search_results[1].bookmark_id).to eq(bookmark1.id)
    end

    it "filters posts" do
      user = create(:user, public_bookmarks: true)
      replies = create_list(:reply, 3)
      bookmark0 = create(:bookmark, reply: replies[0], user: user)
      create(:bookmark, reply: replies[1], user: user)
      bookmark2 = create(:bookmark, reply: replies[2], user: user)

      get :search, params: { commit: true, user_id: user.id, post_id: [replies[0].post_id, replies[2].post_id] }
      search_results = assigns(:search_results)
      expect(search_results.length).to eq(2)
      expect(search_results).to match_array([replies[0], replies[2]])
      expect(search_results[0].bookmark_id).to eq(bookmark0.id)
      expect(search_results[1].bookmark_id).to eq(bookmark2.id)
    end

    it "only shows from visible posts" do
      user = create(:user, public_bookmarks: true)
      replies = create_list(:reply, 3)
      bookmark0 = create(:bookmark, reply: replies[0], user: user)
      create(:bookmark, reply: replies[1], user: user)
      create(:bookmark, reply: replies[2], user: user)
      replies[2].post.update!(privacy: :private)

      get :search, params: { commit: true, user_id: user.id, post_id: [replies[0].post_id, replies[2].post_id] }
      search_results = assigns(:search_results)
      expect(search_results.length).to eq(1)
      expect(search_results).to match_array([replies[0]])
      expect(search_results[0].bookmark_id).to eq(bookmark0.id)
    end
  end
end
