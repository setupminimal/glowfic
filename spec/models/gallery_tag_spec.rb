RSpec.describe GalleryTag do
  describe "callbacks" do
    context "when gallery group added to gallery" do
      it "does not add to other users' characters" do
        group = create(:gallery_group)
        character = create(:character, gallery_groups: [group])

        gallery = create(:gallery)
        gallery.gallery_groups << group
        gallery.save!
        expect(character.reload.galleries).to be_empty
      end

      it "does not add to a character twice" do
        # tests a manually-attached character1
        # and a double-grouped character2
        group = create(:gallery_group)
        group2 = create(:gallery_group)
        user = create(:user)
        character1 = create(:character, user: user, gallery_groups: [group])
        character2 = create(:character, user: user, gallery_groups: [group, group2])

        gallery = create(:gallery, user: user, characters: [character1])
        gallery.gallery_groups << group
        gallery.save!
        gallery.reload
        expect(gallery.characters).to match_array([character1, character2])
        expect(gallery.characters_galleries.find_by(character_id: character1.id)).not_to be_added_by_group
        expect(gallery.characters_galleries.find_by(character_id: character2.id)).to be_added_by_group

        gallery.gallery_groups << group2
        gallery.save!
        gallery.reload
        expect(gallery.characters).to match_array([character1, character2])
        expect(gallery.characters_galleries.find_by(character_id: character1.id)).not_to be_added_by_group
        expect(gallery.characters_galleries.find_by(character_id: character2.id)).to be_added_by_group
      end

      it "adds galleries to given group" do
        group = create(:gallery_group)
        user = create(:user)
        character1 = create(:character, user: user, gallery_groups: [group])
        character2 = create(:character, user: user, gallery_groups: [group])

        gallery = create(:gallery, user: user)
        gallery.gallery_groups << group
        gallery.save!
        gallery.reload
        expect(gallery.characters).to match_array([character1, character2])
        expect(gallery.characters_galleries.map(&:added_by_group?)).to eq([true, true])
      end
    end

    it "does right things when gallery group removed from gallery" do
      # does not touch unrelated characters
      # does not touch characters that have been otherwise tethered
      # removes from characters that are not otherwise tethered
      group = create(:gallery_group)
      user = create(:user)
      other_character = create(:character, user: user)
      gallery = create(:gallery, user: user, gallery_groups: [group], characters: [other_character])
      character_auto = create(:character, user: user, gallery_groups: [group])
      character_both = create(:character, user: user, gallery_groups: [group])
      gallery.reload
      gallery.characters_galleries.find_by(character_id: character_both.id).update!(added_by_group: false)
      expect(gallery.characters).to match_array([other_character, character_auto, character_both])
      expect(gallery.characters_galleries.find_by(character_id: character_auto.id)).to be_added_by_group

      gallery.update!(gallery_groups: [])
      gallery.reload
      expect(gallery.characters).to match_array([other_character, character_both])
      expect(gallery.characters_galleries.find_by(character_id: character_both.id)).not_to be_added_by_group
    end

    it "adds and removes a group's gallery for many characters in a fixed number of queries" do
      group = create(:gallery_group)
      user = create(:user)
      characters = create_list(:character, 4, user: user, gallery_groups: [group])
      existing = create(:gallery, user: user)
      characters.each { |character| character.galleries << existing }
      gallery = create(:gallery, user: user)

      queries = []
      callback = ->(*, payload) {
        queries << payload[:sql] if payload[:sql].include?('characters_galleries') && !payload[:sql].start_with?('SAVEPOINT', 'RELEASE')
      }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        gallery.update!(gallery_groups: [group])
        gallery.update!(gallery_groups: [])
      end

      expect(queries.size).to be <= 8
      characters.each { |character| expect(character.characters_galleries.ordered.map(&:gallery_id)).to eq([existing.id]) }
    end

    it "puts the group's gallery after the character's existing galleries" do
      group = create(:gallery_group)
      user = create(:user)
      character = create(:character, user: user, gallery_groups: [group])
      earlier = create(:gallery, user: user)
      character.galleries << earlier
      gallery = create(:gallery, user: user, gallery_groups: [group])

      expect(character.characters_galleries.ordered.map(&:gallery_id)).to eq([earlier.id, gallery.id])
      expect(character.characters_galleries.ordered.map(&:section_order)).to eq([0, 1])
    end

    it "closes the gap in a character's galleries when a group's gallery is removed" do
      group = create(:gallery_group)
      user = create(:user)
      character = create(:character, user: user, gallery_groups: [group])
      grouped = create(:gallery, user: user, gallery_groups: [group])
      later = create(:gallery, user: user)
      character.galleries << later

      grouped.update!(gallery_groups: [])

      expect(character.characters_galleries.ordered.map(&:gallery_id)).to eq([later.id])
      expect(character.characters_galleries.ordered.map(&:section_order)).to eq([0])
    end

    it "does not destroy gallery groups when destroyed" do
      group = create(:gallery_group)
      gallery = create(:gallery, gallery_groups: [group])
      other = create(:gallery, gallery_groups: [group])
      gallery.reload
      other.reload
      expect(gallery.gallery_groups).to match_array([group])
      expect(other.gallery_groups).to match_array([group])

      gallery.destroy!
      group.reload
      expect(other.reload.gallery_groups).to match_array([group])
    end
  end
end
