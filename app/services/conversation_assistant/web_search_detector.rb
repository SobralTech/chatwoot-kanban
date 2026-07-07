class ConversationAssistant::WebSearchDetector
  # Matches tokens mixing letters and digits (e.g. "TN-660", "HP107w", "M404dn"),
  # the typical shape of a product/model number.
  MODEL_TOKEN_REGEX = /\b(?=[a-zA-Z0-9-]*\d)(?=[a-zA-Z0-9-]*[a-zA-Z])[a-zA-Z0-9-]{3,}\b/

  def self.required?(question)
    question.to_s.match?(MODEL_TOKEN_REGEX)
  end
end
