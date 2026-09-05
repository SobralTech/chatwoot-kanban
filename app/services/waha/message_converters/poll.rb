# A WhatsApp poll. GOWS exposes its creation message under one of the three
# pollCreationMessage proto versions. The options and selection limit are kept
# in content_attributes so subsequent poll.vote events can update the same
# Chatwoot message without manufacturing a second poll bubble.
class Waha::MessageConverters::Poll < Waha::MessageConverters::Base
  pattr_initialize [:poll!]

  def self.extract(payload)
    node = poll_node(payload)
    return unless node.is_a?(Hash)

    question = node['name'].presence || node['question'].presence
    options = options_from(node)
    return if question.blank? || options.blank?

    { question: question, options: options, selectable_options_count: selectable_options_count(node) }.compact
  end

  def self.render(poll, votes: {})
    question = value(poll, :question)
    options = Array(value(poll, :options))
    (poll_lines(question, options, value(poll, :selectable_options_count)) + observed_vote_lines(options, votes)).compact_blank.join("\n")
  end

  def content
    self.class.render(poll)
  end

  def metadata
    { poll: poll }
  end

  def self.poll_node(payload)
    message = payload.dig('_data', 'Message')
    gows_poll_node(message) || payload['poll']
  end
  private_class_method :poll_node

  def self.gows_poll_node(message)
    return unless message.is_a?(Hash)

    %w[pollCreationMessage pollCreationMessageV2 pollCreationMessageV3].filter_map { |key| message[key] }.first
  end
  private_class_method :gows_poll_node

  def self.options_from(node)
    Array(node['options']).filter_map do |option|
      option.is_a?(Hash) ? option['optionName'].presence || option['name'].presence : option.presence
    end
  end
  private_class_method :options_from

  def self.selectable_options_count(node)
    count = node['selectableOptionsCount'] || node['selectable_options_count']
    count.to_i.presence if count.present?
  end
  private_class_method :selectable_options_count

  def self.poll_lines(question, options, selectable_options_count)
    selection_limit = if selectable_options_count.present?
                        I18n.t('conversations.messages.waha_poll.selectable_options', count: selectable_options_count.to_i)
                      end
    [I18n.t('conversations.messages.waha_poll.header'), question, selection_limit] +
      options.map { |option| I18n.t('conversations.messages.waha_poll.option', option: option) }
  end
  private_class_method :poll_lines

  def self.observed_vote_lines(options, votes)
    observed_votes = vote_counts(options, votes)
    return [] if observed_votes.blank?

    [I18n.t('conversations.messages.waha_poll.observed_votes')] + observed_votes.map do |option, count|
      I18n.t('conversations.messages.waha_poll.observed_vote', option: option, count: count)
    end
  end
  private_class_method :observed_vote_lines

  def self.value(hash, key)
    hash[key] || hash[key.to_s]
  end
  private_class_method :value

  def self.vote_counts(options, votes)
    counts = Hash.new(0)
    votes.each_value do |vote|
      Array(value(vote, :selected_options)).each { |option| counts[option] += 1 if options.include?(option) }
    end
    counts.select { |_option, count| count.positive? }
  end
  private_class_method :vote_counts
end
