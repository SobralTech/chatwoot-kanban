class Waha::TypingSimulator
  CHARS_PER_SECOND = 20.0
  MIN_SECONDS = 1.0
  MAX_SECONDS = 8.0
  JITTER = 0.3

  def self.duration_for(text)
    base = text.to_s.length / CHARS_PER_SECOND
    clamped = base.clamp(MIN_SECONDS, MAX_SECONDS)
    (clamped * rand((1 - JITTER)..(1 + JITTER))).round(1)
  end
end
