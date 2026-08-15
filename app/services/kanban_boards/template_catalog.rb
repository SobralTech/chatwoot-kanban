module KanbanBoards::TemplateCatalog
  TEMPLATES = {
    'blank' => {
      stages: [{ name_key: 'entry', color: '#8B8D98' }],
      won: { name_key: 'won' },
      lost: { name_key: 'lost' },
      lost_reasons: []
    }
  }.freeze

  DEFAULT_KEY = 'blank'.freeze
  WON_COLOR = '#2A7E3B'.freeze
  LOST_COLOR = '#CE2C31'.freeze

  def self.fetch(key)
    TEMPLATES.fetch(key_for(key))
  end

  def self.key_for(key)
    normalized_key = key.presence || DEFAULT_KEY
    TEMPLATES.key?(normalized_key) ? normalized_key : DEFAULT_KEY
  end
end
