# frozen_string_literal: true
class GalleriesIcon < ApplicationRecord
  belongs_to :icon, optional: true # TODO: This is required, fix bug around validation if it is set as such
  belongs_to :gallery, optional: false
  accepts_nested_attributes_for :icon, allow_destroy: true

  after_create :set_has_gallery
  after_destroy :unset_has_gallery
  validates :gallery, uniqueness: { scope: :icon }
  validate :icon_belongs_to_gallery_user

  # Takes the icons out of the gallery, and marks any that are then in no gallery as such, in two queries
  # rather than a lookup and update for each icon (the same result as destroying each icon's GalleriesIcon)
  def self.remove_from_gallery(gallery, icons)
    icon_ids = icons.map(&:id)
    where(gallery_id: gallery.id, icon_id: icon_ids).delete_all
    Icon.where(id: icon_ids, has_gallery: true).where.not(id: select(:icon_id)).update_all(has_gallery: false) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def icon_belongs_to_gallery_user
    return unless icon && gallery
    return if icon.user_id == gallery.user_id
    errors.add(:icon, "must belong to the gallery owner")
  end

  def unset_has_gallery
    return if destroyed_by_association&.active_record == Icon # the icon is being deleted too
    return if icon.galleries.present?
    icon.update(has_gallery: false)
  end

  def set_has_gallery
    return if icon.has_gallery?
    icon.update(has_gallery: true)
  end
end
