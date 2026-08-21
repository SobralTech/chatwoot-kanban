# Free-text board search. Every token has to match, and a token matches a card
# through its own subject or through its contact's name, email or phone number.
class KanbanCards::SearchCondition
  MAX_TOKENS = 5

  def initialize(search_query:)
    @search_query = search_query
  end

  def call
    search_tokens
      .map { |token| token_condition(token) }
      .reduce(:and)
  end

  private

  attr_reader :search_query

  def search_tokens
    search_query.to_s.split(/\s+/).first(MAX_TOKENS).map do |token|
      ActiveSupport::Inflector.transliterate(token).downcase
    end
  end

  def token_condition(token)
    conditions = [
      card_table[:id].in(subject_ids_matching(token)),
      contact_id_matching(token)
    ]
    conditions.reduce(:or)
  end

  def subject_ids_matching(token)
    KanbanCard
      .active
      .where(unaccented_like(card_table[:subject], token))
      .select(:id)
      .arel
  end

  def contact_id_matching(token)
    card_table[:contact_id].in(contact_ids_matching(token))
  end

  def contact_ids_matching(token)
    Contact
      .where(contact_token_condition(token))
      .select(:id)
      .arel
  end

  def contact_token_condition(token)
    conditions = [
      unaccented_like(contact_table[:name], token),
      plain_like(contact_table[:email], token)
    ]
    conditions << phone_like(token) if token.match?(/\d/)
    conditions.reduce(:or)
  end

  def unaccented_like(column, token)
    named_function('immutable_unaccent', named_function('lower', column)).matches(bind_param(like_pattern(token)))
  end

  def plain_like(column, token)
    named_function('lower', column).matches(bind_param(like_pattern(token)))
  end

  def phone_like(token)
    named_function(
      'regexp_replace',
      contact_table[:phone_number],
      Arel::Nodes.build_quoted('\\D'),
      Arel::Nodes.build_quoted(''),
      Arel::Nodes.build_quoted('g')
    ).matches(bind_param(like_pattern(token.gsub(/\D/, ''))))
  end

  def like_pattern(token)
    "%#{ActiveRecord::Base.sanitize_sql_like(token)}%"
  end

  def named_function(name, *expressions)
    Arel::Nodes::NamedFunction.new(name, expressions)
  end

  def bind_param(value)
    Arel::Nodes::BindParam.new(value)
  end

  def card_table
    KanbanCard.arel_table
  end

  def contact_table
    Contact.arel_table
  end
end
