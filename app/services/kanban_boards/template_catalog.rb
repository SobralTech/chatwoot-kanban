module KanbanBoards::TemplateCatalog
  TEMPLATES = {
    'blank' => {
      stages: [{ name_key: 'entry', color: '#8B8D98' }],
      won: { name_key: 'won' },
      lost: { name_key: 'lost' }
    },
    'sales' => {
      stages: [
        { name_key: 'new_contact', color: '#8B8D98' },
        { name_key: 'qualification', color: '#6E56CF' },
        { name_key: 'quote_sent', color: '#0090FF' },
        { name_key: 'negotiation', color: '#F76B15' }
      ],
      won: { name_key: 'won' },
      lost: { name_key: 'lost' },
      lost_reasons: %w[price delivery_time out_of_stock bought_elsewhere no_reply]
    },
    'tech_support' => {
      stages: [
        { name_key: 'received', color: '#8B8D98' },
        { name_key: 'diagnosis', color: '#6E56CF' },
        { name_key: 'awaiting_approval', color: '#0090FF' },
        { name_key: 'in_repair', color: '#F76B15' },
        { name_key: 'ready_for_pickup', color: '#30A46C' }
      ],
      won: { name_key: 'delivered' },
      lost: { name_key: 'cancelled' },
      lost_reasons: %w[quote_refused unrepairable gave_up abandoned],
      custom_fields: [
        { key: 'service_order', field_type: :text },
        { key: 'equipment', field_type: :text },
        { key: 'device_password', field_type: :text },
        { key: 'promised_date', field_type: :date }
      ]
    },
    'quotes' => {
      stages: [
        { name_key: 'request', color: '#8B8D98' },
        { name_key: 'assessment', color: '#6E56CF' },
        { name_key: 'proposal_sent', color: '#0090FF' },
        { name_key: 'follow_up', color: '#F76B15' }
      ],
      won: { name_key: 'closed' },
      lost: { name_key: 'refused' },
      lost_reasons: %w[price scope_changed postponed competitor],
      custom_fields: [
        { key: 'company', field_type: :text },
        { key: 'valid_until', field_type: :date }
      ]
    }
  }.freeze

  DEFAULT_KEY = 'blank'.freeze
  WON_COLOR = '#2A7E3B'.freeze
  LOST_COLOR = '#CE2C31'.freeze

  def self.fetch(key)
    TEMPLATES.fetch(key)
  end

  def self.key_for(key)
    normalized_key = key.presence || DEFAULT_KEY
    TEMPLATES.key?(normalized_key) ? normalized_key : DEFAULT_KEY
  end

  def self.previews(locale:)
    preview_locale = locale.presence || I18n.default_locale

    (TEMPLATES.keys.reject { |key| key == DEFAULT_KEY } + [DEFAULT_KEY]).map do |key|
      template = fetch(key)

      {
        key: key,
        name: translate(preview_locale, key, 'name'),
        description: translate(preview_locale, key, 'description'),
        stages: template[:stages].map { |stage| translate(preview_locale, key, "stages.#{stage[:name_key]}") },
        won_stage_name: translate(preview_locale, key, "stages.#{template[:won][:name_key]}"),
        lost_stage_name: translate(preview_locale, key, "stages.#{template[:lost][:name_key]}"),
        lost_reasons_count: template.fetch(:lost_reasons, []).length,
        custom_fields_count: template.fetch(:custom_fields, []).length
      }
    end
  end

  def self.translate(locale, template_key, path)
    I18n.t("kanban.board_templates.#{template_key}.#{path}", locale: locale)
  end
end
