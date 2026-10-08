# frozen_string_literal: true
module Taggable
  private

  # Replaces the tags a record has through a join model (e.g. post.settings = tags). Rails decides which join records
  # to remove by loading the tag behind each of them separately, and the join models' callbacks may too, so this
  # loads the tags of all the join records first, in one query.
  def replace_tags(record, association, tags)
    unless record.new_record?
      reflection = record.class.reflect_on_association(association)
      load_join_tags(record.public_send(reflection.through_reflection.name).to_a, reflection.source_reflection.foreign_key)
    end
    record.public_send(:"#{association}=", tags)
  end

  # Gives each join record the tag it points to as every typed association of that tag (e.g. a character tag's
  # tag, setting and gallery_group), as if each had been loaded, with nil for the types it is not.
  def load_join_tags(join_records, foreign_key)
    return if join_records.empty?
    tags = Tag.where(id: join_records.pluck(foreign_key)).index_by(&:id)
    tag_reflections = join_records.first.class.reflect_on_all_associations(:belongs_to).select do |reflection|
      reflection.foreign_key.to_s == foreign_key.to_s
    end
    join_records.each do |join_record|
      tag = tags[join_record[foreign_key]]
      tag_reflections.each do |reflection|
        join_record.association(reflection.name).target = (tag if tag.is_a?(reflection.klass))
      end
    end
  end

  def process_tags(klass, obj_param:, id_param:)
    # fetch and clean tag ids
    ids = params.fetch(obj_param, {}).fetch(id_param, [])
    ids = ids.compact_blank.map(&:to_s)
    return [] unless ids.present?

    # store formatted for creation-order sorting later
    match_ids = ids.map { |id| id.start_with?('_') ? id.upcase[1..-1].strip : id }

    # separate existing tags from new tags which start with _
    new_names = ids.select { |id| id.start_with?('_') }
    existing_tags = klass.where(id: (ids - new_names))
    new_names.map! { |name| name[1..-1].strip }

    # locate anything that already exists with the same name (locale unfriendly) and substitute it
    matched_new_tags = klass.where(name: new_names)
    matched_new_names = matched_new_tags.map { |tag| tag.name.upcase }
    new_names.reject! { |name| matched_new_names.include?(name.upcase) }

    # create anything case-insensitively (locale unfriendly) unique that remains
    new_names = new_names.uniq(&:upcase)
    new_tags = new_names.map { |name| klass.new(user: current_user, name: name) }

    # consolidate, sort and purge duplicates (locale unfriendly)
    all_tags = existing_tags + matched_new_tags + new_tags
    all_tags.sort_by! do |tag|
      match_ids.index(tag.name.upcase) || match_ids.index(tag.id.to_s)
    end
    all_tags.uniq { |tag| tag.name.upcase }
  end
end
