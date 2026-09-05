module WahaSpecHelpers
  # Loads one of the anonymized GOWS `message` payloads in
  # spec/fixtures/waha/gows. Merges are applied on top so a scenario can move a
  # fixture into a group chat or drop a field without editing the capture.
  def gows_payload(name, overrides = {})
    payload = JSON.parse(Rails.root.join("spec/fixtures/waha/gows/#{name}.json").read)
    payload.merge(overrides.deep_stringify_keys)
  end
end
