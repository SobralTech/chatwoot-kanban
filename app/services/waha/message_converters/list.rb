# WhatsApp list messages and their legacy listResponseMessage selections. The
# raw GOWS proto is the primary source; WAHA's normalized top-level `list`
# covers compatible engines without changing the routing layer.
class Waha::MessageConverters::List < Waha::MessageConverters::Base
  pattr_initialize [:list!]

  def self.extract(payload)
    message = payload.dig('_data', 'Message')
    raw_list = message['listMessage'] if message.is_a?(Hash)
    list = from_list_message(raw_list) || from_list_message(payload['list'])
    return list if list

    from_list_response(message['listResponseMessage']) if message.is_a?(Hash)
  end

  def content
    ([I18n.t('conversations.messages.waha_list.header'), list[:title], list[:description]] + section_lines + optional_lines).compact_blank.join("\n")
  end

  def metadata
    { list: list }
  end

  private

  def section_lines
    list[:sections].flat_map { |section| section_lines_for(section) }
  end

  def section_lines_for(section)
    heading = I18n.t('conversations.messages.waha_list.section', title: section[:title]) if section[:title].present?
    [heading] + section[:rows].map { |row| row_line(row) }
  end

  def row_line(row)
    description = row[:description].present? ? " — #{row[:description]}" : ''
    I18n.t('conversations.messages.waha_list.option', title: row[:title], description: description)
  end

  def optional_lines
    selected = I18n.t('conversations.messages.waha_list.selected', option: list[:selected]) if list[:selected].present?
    [selected, list[:footer]]
  end

  class << self
    private

    def from_list_message(node)
      return unless node.is_a?(Hash)

      sections = sections_from(node)
      title = node['title'].presence
      return if title.blank? || sections.blank?

      {
        title: title,
        description: node['description'].presence,
        footer: node['footerText'].presence || node['footer'].presence,
        button: node['buttonText'].presence || node['button'].presence,
        sections: sections,
        selected: selected_option(sections, selected_id(node)) || node['selectedRowTitle'].presence
      }.compact
    end

    def sections_from(node)
      Array(node['sections']).filter_map { |section| section_from(section) }
    end

    def section_from(section)
      return unless section.is_a?(Hash)

      rows = Array(section['rows']).filter_map { |row| row_from(row) }
      return if rows.blank?

      { title: section['title'].presence, rows: rows }.compact
    end

    def row_from(row)
      return unless row.is_a?(Hash)

      title = row['title'].presence
      return if title.blank?

      { title: title, description: row['description'].presence, id: row['rowId'].presence || row['rowID'].presence }.compact
    end

    def selected_id(node)
      node['selectedRowId'].presence || node['selectedRowID'].presence || node.dig('singleSelectReply', 'selectedRowId').presence ||
        node.dig('singleSelectReply', 'selectedRowID').presence
    end

    def from_list_response(node)
      return unless node.is_a?(Hash)

      selected = node['title'].presence || node['description'].presence || selected_id(node)
      return if selected.blank?

      { title: node['listTitle'].presence || I18n.t('conversations.messages.waha_list.response'), sections: [], selected: selected }
    end

    def selected_option(sections, selected_id)
      return if selected_id.blank?

      sections.flat_map { |section| section[:rows] }.find { |row| row[:id] == selected_id }&.dig(:title) || selected_id
    end
  end
end
