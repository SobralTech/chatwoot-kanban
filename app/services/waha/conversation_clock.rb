class Waha::ConversationClock
  MAX_BACKLOG = 30_000
  MIN_GAP = 1_000

  SCRIPT = <<~LUA.freeze
    -- KEYS[1] = waha:typing_clock:<conversation_id>
    -- ARGV = now_ms, duration_ms, MAX_BACKLOG, MIN_GAP
    local now, dur   = tonumber(ARGV[1]), tonumber(ARGV[2])
    local cap, gap   = tonumber(ARGV[3]), tonumber(ARGV[4])

    local clock   = tonumber(redis.call('GET', KEYS[1]) or 0)
    local start   = math.max(clock, now)     -- quando ESTA mensagem começa a digitar
    local backlog = start - now              -- fila que já existia (0 no caso normal)

    -- Acima do teto, comprime a digitação até o incremento mínimo,
    -- preservando a monotonicidade dos horários.
    local effective = dur
    if backlog + dur > cap then
      effective = math.max(cap - backlog, gap)
    end

    local finish = start + effective
    redis.call('SET', KEYS[1], finish, 'PX', finish - now + 5000)
    return { backlog, finish - now }
  LUA

  pattr_initialize [:conversation_id!]

  def reserve(duration_ms)
    now = now_ms
    Redis::Alfred.with do |redis|
      redis.eval(SCRIPT, keys: [key], argv: [now, duration_ms, MAX_BACKLOG, MIN_GAP]).map(&:to_i)
    end
  end

  def backlog?
    (Redis::Alfred.get(key) || 0).to_i > now_ms
  end

  private

  def key
    "waha:typing_clock:#{conversation_id}"
  end

  def now_ms
    (Time.now.to_f * 1000).to_i
  end
end
