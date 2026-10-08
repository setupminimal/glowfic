# frozen_string_literal: true
class CharacterTag < ApplicationRecord
  belongs_to :character, inverse_of: :character_tags, optional: false
  belongs_to :tag, inverse_of: :character_tags, optional: true # TODO: This is required, fix bug around validation if it is set as such
  belongs_to :setting, foreign_key: :tag_id, inverse_of: :character_tags, optional: true
  belongs_to :gallery_group, foreign_key: :tag_id, inverse_of: :character_tags, optional: true

  validates :character, uniqueness: { scope: :tag }

  after_create :add_galleries_to_character
  after_destroy :remove_galleries_from_character

  def add_galleries_to_character
    return if association(:setting).target.present? # built as a setting, so not a gallery group; avoids loading gallery_group
    return if gallery_group.nil? # skip non-gallery_groups
    joined_gallery_ids = character.characters_galleries.map(&:gallery_id)
    gallery_ids = gallery_group.galleries.where(user_id: character.user_id).where.not(id: joined_gallery_ids).pluck(:id)
    CharactersGallery.add_by_group(gallery_ids.map { |gallery_id| [character.id, gallery_id] })
    character.characters_galleries.reset
  end

  def remove_galleries_from_character
    return if gallery_group.nil? # skip non-gallery_groups
    galleries = gallery_group.galleries.where(user_id: character.user_id)
    joined_group_galleries = character.gallery_groups.joins(:galleries).where(galleries: { user_id: character.user_id }).pluck(:gallery_id)
    galleries = galleries.where.not(id: joined_group_galleries)
    character.characters_galleries.where(gallery: galleries, added_by_group: true).delete_all
    CharactersGallery.reorder_for([character.id])
    character.characters_galleries.reload
  end
end
