RSpec.describe GalleriesIcon do
  describe ".remove_from_gallery" do
    let(:user) { create(:user) }
    let(:gallery) { create(:gallery, user: user) }
    let(:other_gallery) { create(:gallery, user: user) }

    it "removes the icons from only that gallery" do
      icons = create_list(:icon, 2, user: user)
      icons.each { |icon| gallery.icons << icon }
      other_gallery.icons << icons.first

      GalleriesIcon.remove_from_gallery(gallery, icons)

      expect(gallery.icons.reload).to be_empty
      expect(other_gallery.icons.reload).to eq([icons.first])
    end

    it "marks icons left in no gallery as galleryless, and leaves others alone" do
      only_here, also_elsewhere = create_list(:icon, 2, user: user)
      gallery.icons << only_here
      gallery.icons << also_elsewhere
      other_gallery.icons << also_elsewhere

      GalleriesIcon.remove_from_gallery(gallery, [only_here, also_elsewhere])

      expect(only_here.reload.has_gallery).to be(false)
      expect(also_elsewhere.reload.has_gallery).to be(true)
    end

    it "does not touch icons that were not given" do
      kept, removed = create_list(:icon, 2, user: user)
      gallery.icons << kept
      gallery.icons << removed

      GalleriesIcon.remove_from_gallery(gallery, [removed])

      expect(gallery.icons.reload).to eq([kept])
      expect(kept.reload.has_gallery).to be(true)
    end
  end

  describe "when the icon is deleted" do
    it "removes the icon's gallery rows without checking its other galleries" do
      icon = create(:icon)
      create(:gallery, user: icon.user).icons << icon
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "galleries" INNER JOIN "galleries_icons"') }
      expect {
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          Audited.audit_class.as_user(icon.user) do
            icon.destroy!
          end
        end
      }.to change {
             GalleriesIcon.count
           }.by(-1)
      expect(queries).to be_empty
    end

    it "still marks the icon galleryless when removed from its gallery" do
      icon = create(:icon)
      gallery = create(:gallery, user: icon.user)
      gallery.icons << icon
      gallery.icons.destroy(icon)
      expect(icon.reload.has_gallery).to be(false)
    end
  end
end
