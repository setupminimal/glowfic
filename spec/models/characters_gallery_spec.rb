RSpec.describe CharactersGallery do
  it "should reset section_order fields in other galleries after deletion" do
    character = create(:character)
    gallery = create(:gallery, user: character.user)
    cg0 = CharactersGallery.create!(character: character, gallery: gallery)
    expect(cg0.section_order).to eq(0)
    gallery = create(:gallery, user: character.user)
    cg1 = CharactersGallery.create!(character: character, gallery: gallery)
    expect(cg1.section_order).to eq(1)
    gallery = create(:gallery, user: character.user)
    cg2 = CharactersGallery.create!(character: character, gallery: gallery)
    expect(cg2.section_order).to eq(2)

    cg1.destroy!

    expect(cg0.reload.section_order).to eq(0)
    expect(cg2.reload.section_order).to eq(1)
  end

  it "should autofill gallery order" do
    character = create(:character)
    gallery = create(:gallery, user: character.user)
    cg = CharactersGallery.create!(character: character, gallery: gallery)
    expect(cg.section_order).to eq(0)
    gallery = create(:gallery, user: character.user)
    cg = CharactersGallery.create!(character: character, gallery: gallery)
    expect(cg.section_order).to eq(1)
    gallery = create(:gallery, user: character.user)
    cg = CharactersGallery.create!(character: character, gallery: gallery)
    expect(cg.section_order).to eq(2)
  end

  it "should prevent duplicate joins for the same character and gallery" do
    character = create(:character)
    gallery = create(:gallery, user: character.user)
    character.galleries << gallery
    cg = character.characters_galleries.create(gallery: gallery)
    expect(cg.persisted?).to be(false)
    expect(cg).not_to be_valid
    expect(cg.errors.messages).to eq({ character: ['has already been taken'] })
  end

  it "should allow multiple galleries on the same character" do
    character = create(:character)
    character.galleries << create(:gallery, user: character.user)
    gallery2 = create(:gallery, user: character.user)
    cg = character.characters_galleries.create(gallery: gallery2)
    expect(cg.persisted?).to be(true)
    expect(cg).to be_valid
  end

  it "should allow multiple characters to have the same gallery" do
    character = create(:character)
    gallery = create(:gallery, user: character.user)
    character.galleries << gallery
    character2 = create(:character, user: character.user)
    cg = character2.characters_galleries.create(gallery: gallery)
    expect(cg.persisted?).to be(true)
    expect(cg).to be_valid
  end

  describe ".add_by_group" do
    it "adds the galleries after each character's existing ones, marked as added by group" do
      user = create(:user)
      first, second = create_list(:character, 2, user: user)
      first_gallery, second_gallery, group_gallery = create_list(:gallery, 3, user: user)
      first.galleries << first_gallery
      second.galleries << second_gallery

      CharactersGallery.add_by_group([[first.id, group_gallery.id], [second.id, group_gallery.id]])

      expect(first.characters_galleries.ordered.map(&:gallery_id)).to eq([first_gallery.id, group_gallery.id])
      expect(second.characters_galleries.ordered.map(&:gallery_id)).to eq([second_gallery.id, group_gallery.id])
      expect(first.characters_galleries.ordered.map(&:section_order)).to eq([0, 1])
      expect(first.characters_galleries.ordered.map(&:added_by_group)).to eq([false, true])
    end

    it "numbers several galleries added to one character in order" do
      character = create(:character)
      galleries = create_list(:gallery, 3, user: character.user)
      CharactersGallery.add_by_group(galleries.map { |gallery| [character.id, gallery.id] })
      expect(character.characters_galleries.ordered.map(&:gallery_id)).to eq(galleries.map(&:id))
      expect(character.characters_galleries.ordered.map(&:section_order)).to eq([0, 1, 2])
    end

    it "does nothing with nothing to add" do
      expect { CharactersGallery.add_by_group([]) }.not_to change { CharactersGallery.count }
    end
  end

  describe ".reorder_for" do
    it "closes gaps in the order of each given character's galleries only" do
      user = create(:user)
      first, second, untouched = create_list(:character, 3, user: user)
      galleries = create_list(:gallery, 3, user: user)
      [first, second, untouched].each { |character| galleries.each { |gallery| character.galleries << gallery } }
      first.characters_galleries.find_by(gallery: galleries[0]).update_columns(section_order: 5) # rubocop:disable Rails/SkipsModelValidations
      first.characters_galleries.find_by(gallery: galleries[1]).update_columns(section_order: 9) # rubocop:disable Rails/SkipsModelValidations
      second.characters_galleries.find_by(gallery: galleries[2]).update_columns(section_order: 7) # rubocop:disable Rails/SkipsModelValidations
      untouched.characters_galleries.find_by(gallery: galleries[0]).update_columns(section_order: 4) # rubocop:disable Rails/SkipsModelValidations

      CharactersGallery.reorder_for([first.id, second.id])

      expect(first.characters_galleries.ordered.map(&:section_order)).to eq([0, 1, 2])
      expect(first.characters_galleries.ordered.map(&:gallery_id)).to eq([galleries[2].id, galleries[0].id, galleries[1].id])
      expect(second.characters_galleries.ordered.map(&:section_order)).to eq([0, 1, 2])
      expect(untouched.characters_galleries.ordered.map(&:section_order)).to include(4)
    end

    it "does nothing with no characters" do
      expect { CharactersGallery.reorder_for([]) }.not_to raise_error
    end
  end
end
