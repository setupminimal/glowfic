# frozen_string_literal: true
class Gallery < ApplicationRecord
  belongs_to :user, optional: false

  has_many :galleries_icons, dependent: :destroy, inverse_of: :gallery
  accepts_nested_attributes_for :galleries_icons, allow_destroy: true
  has_many :icons, -> { ordered }, through: :galleries_icons, dependent: :destroy

  has_many :characters_galleries, inverse_of: :gallery, dependent: :destroy
  has_many :characters, through: :characters_galleries, dependent: :destroy

  has_many :gallery_tags, inverse_of: :gallery, dependent: :destroy
  has_many :gallery_groups, -> { ordered_by_gallery_tag }, through: :gallery_tags, source: :gallery_group, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }

  scope :ordered, -> { order('characters_galleries.section_order ASC') }

  scope :ordered_by_name, -> { order(Arel.sql('lower(name) asc'), id: :asc) }

  scope :ordered_by_id, -> { order(id: :asc) }

  scope :with_icon_count, -> {
    joins('LEFT JOIN galleries_icons ON galleries.id = galleries_icons.gallery_id')
      .select("galleries.*, count(galleries_icons.id) as icon_count")
      .group("galleries.id")
  }

  # rubocop:disable-next Style/TrailingCommaInArguments
  scope :with_gallery_groups, -> {
    # fetches an array of
    # galleries.map(&:gallery_groups).map{|group| [f1: group.id, f2: group.name]}
    # ordered by tag name
    select(
      <<~SQL.squish
        ARRAY(
          SELECT row_to_json(ROW(tags.id, tags.name)) FROM tags
          LEFT JOIN gallery_tags ON gallery_tags.tag_id = tags.id
          WHERE gallery_tags.gallery_id = galleries.id AND tags.type = 'GalleryGroup'
          ORDER BY gallery_tags.id ASC
        ) AS gallery_groups_data_internal
      SQL
    )
  }

  # Converts the internal [{'f1' => id, 'f2' => name}] structure of the retrieved data
  # to [{id => id, name => name}]
  def gallery_groups_data
    return @gallery_groups_data unless @gallery_groups_data.nil?
    if has_attribute?(:gallery_groups_data_internal)
      data_internal = read_attribute(:gallery_groups_data_internal)
      faked = Struct.new(:id, :name)
      @gallery_groups_data = data_internal.map do |old|
        faked.new(old['f1'], old['f2'])
      end
    else
      @gallery_groups_data = gallery_groups
    end
    @gallery_groups_data
  end

  # The [id, keyword, url, credit] of each icon in each of the galleries, in the order of gallery.icons,
  # keyed by gallery id; for showing several galleries without loading the icons of each separately
  def self.icon_rows_for(galleries)
    rows = Icon.joins(:galleries_icons).where(galleries_icons: { gallery_id: galleries.map(&:id) })
      .ordered.pluck('galleries_icons.gallery_id', :id, :keyword, :url, :credit)
    rows.group_by(&:first).transform_values { |gallery_rows| gallery_rows.map { |row| row[1..] } }
  end

  def character_gallery_for(character)
    characters_galleries.find_by(character_id: character)
  end
end
