# A Pix payment request. GOWS ships this as an interactiveMessage carrying a
# nativeFlowMessage `payment_info` button whose buttonParamsJSON is itself a
# JSON string with the payment settings — the same shape the more mature
# reference WAHA→Chatwoot app already parses. Only the fields needed to pay
# (merchant, key, amount, reference) are rendered; the surrounding WhatsApp
# interactive-message chrome (header/body/footer copy) is not.
class Waha::MessageConverters::Pix < Waha::MessageConverters::Base
  pattr_initialize [:pix!]

  def self.extract(payload)
    button = payment_button(payload)
    return unless button

    params = parse_params(button['buttonParamsJSON'])
    return unless params

    pix_code = pix_static_code(params)
    key = pix_code['key'].presence
    return unless key

    {
      merchant_name: pix_code['merchant_name'].presence,
      key: key,
      key_type: pix_code['key_type'].presence,
      amount: format_amount(params['total_amount'], params['currency']),
      reference_id: params['reference_id'].presence
    }.compact
  end

  def content
    ([I18n.t('conversations.messages.waha_pix.header')] + details).compact_blank.join("\n")
  end

  def metadata
    { pix: pix }
  end

  # GOWS nests the oneof variant under a second `interactiveMessage` key
  # instead of flattening it directly onto the outer one.
  def self.payment_button(payload)
    message = payload.dig('_data', 'Message')
    return unless message.is_a?(Hash)

    outer = message['interactiveMessage']
    return unless outer.is_a?(Hash)

    inner = outer['interactiveMessage'].is_a?(Hash) ? outer['interactiveMessage'] : outer
    buttons = inner.dig('nativeFlowMessage', 'buttons')
    Array(buttons).find { |button| button.is_a?(Hash) && button['name'] == 'payment_info' && button['buttonParamsJSON'].present? }
  end
  private_class_method :payment_button

  def self.parse_params(json)
    JSON.parse(json)
  rescue JSON::ParserError
    nil
  end
  private_class_method :parse_params

  def self.pix_static_code(params)
    setting = Array(params['payment_settings']).find { |entry| entry.is_a?(Hash) && entry['type'] == 'pix_static_code' }
    setting.is_a?(Hash) ? setting['pix_static_code'] || {} : {}
  end
  private_class_method :pix_static_code

  # `value`/`offset` encode the amount as an integer shifted by `offset` decimal
  # places (e.g. value 4590, offset 2 => 45.90), the same fixed-point encoding
  # WhatsApp uses for every native-flow price.
  def self.format_amount(total_amount, currency)
    return unless total_amount.is_a?(Hash) && total_amount['value'].present?

    amount = total_amount['value'].to_i / (10**total_amount['offset'].to_i).to_f
    [format('%.2f', amount), currency].compact_blank.join(' ')
  end
  private_class_method :format_amount

  private

  def details
    [
      (I18n.t('conversations.messages.waha_pix.merchant', name: pix[:merchant_name]) if pix[:merchant_name]),
      key_line,
      (I18n.t('conversations.messages.waha_pix.amount', amount: pix[:amount]) if pix[:amount]),
      (I18n.t('conversations.messages.waha_pix.reference', reference: pix[:reference_id]) if pix[:reference_id])
    ]
  end

  def key_line
    return I18n.t('conversations.messages.waha_pix.key_with_type', key: pix[:key], key_type: pix[:key_type]) if pix[:key_type]

    I18n.t('conversations.messages.waha_pix.key', key: pix[:key])
  end
end
