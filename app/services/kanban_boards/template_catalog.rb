module KanbanBoards::TemplateCatalog
  # Insertion order drives the order templates are offered in the picker.
  TEMPLATES = {
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
    },
    'blank' => {
      stages: [{ name_key: 'entry', color: '#8B8D98' }],
      won: { name_key: 'won' },
      lost: { name_key: 'lost' }
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

  # Previewed in the account locale so the picker shows the exact names ApplyTemplateService will persist.
  def self.previews(locale:)
    I18n.with_locale(locale.presence || I18n.default_locale) do
      TEMPLATES.map { |key, template| preview(key, template) }
    end
  end

  def self.preview(key, template)
    {
      key: key,
      name: translate(key, 'name'),
      description: translate(key, 'description'),
      stages: template[:stages].map { |stage| translate(key, "stages.#{stage[:name_key]}") },
      won_stage_name: translate(key, "stages.#{template[:won][:name_key]}"),
      lost_stage_name: translate(key, "stages.#{template[:lost][:name_key]}"),
      lost_reasons_count: lost_reasons(key).length,
      custom_fields_count: custom_fields(key).length
    }
  end

  def self.lost_reasons(key)
    fetch(key).fetch(:lost_reasons, [])
  end

  def self.custom_fields(key)
    fetch(key).fetch(:custom_fields, [])
  end

  def self.translate(template_key, path)
    I18n.t("kanban.board_templates.#{template_key}.#{path}")
  end
end
