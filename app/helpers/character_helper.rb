# frozen_string_literal: true
module CharacterHelper
  def settings_info(characters)
    settings = characters.joins(:settings).group(:id)
    sql = Arel.sql('ARRAY_AGG(tags.id ORDER BY character_tags.id ASC) AS setting_ids, ARRAY_AGG(tags.name ORDER BY character_tags.id ASC)')
    settings = settings.pluck(:id, sql)
    settings.to_h { |i| [i[0], i[1].zip(i[2])] }
  end

  def characters_list(characters, show_template, extra_attributes: [])
    characters = characters.left_outer_joins(:template) if show_template
    attributes = [:id, :name, :nickname, :screenname, :pb, :cluster, :user_id, 'users.username', Arel.sql('users.deleted as user_deleted')]
    attributes += ['templates.id', 'templates.name'] if show_template
    characters.joins(:user).pluck(*attributes, *extra_attributes)
  end

  # Icon view equivalent of characters_list: the [id, name, screenname, user_id, url, keyword] of each character
  def characters_icons_list(characters, extra_attributes: [])
    characters.left_outer_joins(:default_icon).pluck(:id, :name, :screenname, :user_id, :url, :keyword, *extra_attributes)
  end

  # For pages showing a section per template: loads what every section shows in a fixed number of queries,
  # instead of each section (characters/list_section or characters/icon_view) loading its own.
  # Takes the (ordered) characters that could be shown, the ids of the templates being shown (nil for none), and the
  # page view. Returns the rows for each section keyed by template id (pass a section its rows as rows:) and the
  # settings of all the characters (pass as settings:). Retired characters are filtered out here, as the sections do.
  def preloaded_character_sections(characters, template_ids, page_view)
    characters = characters.where(template_id: template_ids)
    characters = characters.not_retired unless show_retired
    rows = if page_view == 'list'
      characters_list(characters, false, extra_attributes: ['characters.template_id'])
    else
      characters_icons_list(characters, extra_attributes: ['characters.template_id'])
    end
    sections = rows.group_by(&:last).transform_values { |section| section.map { |row| row[0...-1] } }
    [sections, page_view == 'list' ? settings_info(characters.unscope(:order)) : {}]
  end

  def character_menu_link(link_params)
    link_params = params.permit(:character_split, :retired, :view).to_h.merge(link_params)
    url_for(**link_params.symbolize_keys)
  end
end
