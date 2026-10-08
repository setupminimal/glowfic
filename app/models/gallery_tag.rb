# frozen_string_literal: true
class GalleryTag < ApplicationRecord
  belongs_to :gallery, inverse_of: :gallery_tags, optional: false
  belongs_to :tag, inverse_of: :gallery_tags, optional: true # TODO: This is required, fix bug around validation if it is set as such
  belongs_to :gallery_group, foreign_key: :tag_id, inverse_of: :gallery_tags, optional: false # This is currently required but may not continue to be

  validates :gallery, uniqueness: { scope: :tag }

  after_create :add_gallery_to_characters
  after_destroy :remove_gallery_from_characters

  def add_gallery_to_characters
    return if gallery_group.nil? # skip non-gallery_groups
    joined_character_ids = gallery.characters_galleries.map(&:character_id)
    character_ids = gallery_group.characters.where(user_id: gallery.user_id).where.not(id: joined_character_ids).pluck(:id)
    CharactersGallery.add_by_group(character_ids.map { |character_id| [character_id, gallery.id] })
    gallery.characters_galleries.reset
  end

  def remove_gallery_from_characters
    return if gallery_group.nil? # skip non-gallery_groups
    removed = CharactersGallery.where(character: gallery.characters, gallery: gallery, added_by_group: true)
    character_ids = removed.pluck(:character_id)
    removed.delete_all
    CharactersGallery.reorder_for(character_ids)
    gallery.characters_galleries.reset
  end
end
