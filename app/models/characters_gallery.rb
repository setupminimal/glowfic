# frozen_string_literal: true
class CharactersGallery < ApplicationRecord
  belongs_to :character, inverse_of: :characters_galleries, optional: false
  belongs_to :gallery, inverse_of: :characters_galleries, optional: false

  before_create :autofill_order
  after_destroy :reorder_others

  validates :character, uniqueness: { scope: :gallery }

  scope :ordered, -> { order(section_order: :asc) }

  # Adds galleries to characters on behalf of their gallery groups, given [character_id, gallery_id] pairs that
  # aren't already joined, in two queries instead of several for each pair (the same as creating each one
  # with added_by_group: true, which validates and takes its place in the character's order)
  def self.add_by_group(pairs)
    return if pairs.empty?
    next_orders = where(character_id: pairs.map(&:first).uniq).group(:character_id).count
    rows = pairs.map do |character_id, gallery_id|
      section_order = next_orders[character_id].to_i
      next_orders[character_id] = section_order + 1
      { character_id: character_id, gallery_id: gallery_id, added_by_group: true, section_order: section_order }
    end
    insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
  end

  # Closes the gaps in the order of the characters' galleries, as Character#reorder_galleries does
  # for one character, for all of them in one query
  def self.reorder_for(character_ids)
    return if character_ids.empty?
    sql = sanitize_sql_array([<<~SQL.squish, character_ids.uniq])
      UPDATE characters_galleries SET section_order = reordered.new_order
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY character_id ORDER BY section_order, id) - 1 AS new_order
        FROM characters_galleries WHERE character_id IN (?)
      ) reordered
      WHERE characters_galleries.id = reordered.id AND characters_galleries.section_order <> reordered.new_order
    SQL
    with_connection { |connection| connection.exec_update(sql) }
  end

  def reorder_others
    character.reorder_galleries
  end

  def autofill_order
    self.section_order = CharactersGallery.where(character_id: character_id).count
  end
end
