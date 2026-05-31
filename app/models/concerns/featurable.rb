module Featurable
  extend ActiveSupport::Concern

  MAX_BIGINT_FEATURE_INDEX = 63
  INTERNAL_FEATURE_FLAGS_KEY = 'feature_flags'.freeze

  QUERY_MODE = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  FEATURE_LIST = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze

  FEATURES = FEATURE_LIST.each_with_object({}) do |feature, result|
    result[result.keys.size + 1] = "feature_#{feature['name']}".to_sym
  end

  included do
    include FlagShihTzu
    has_flags FEATURES.merge(column: 'feature_flags').merge(QUERY_MODE)

    before_create :enable_default_features
  end

  def enable_features(*names)
    names.each do |name|
      if overflow_feature?(name)
        set_internal_feature(name, true)
        next
      end

      send("feature_#{name}=", true)
    end
  end

  def enable_features!(*names)
    enable_features(*names)
    save
  end

  def disable_features(*names)
    names.each do |name|
      if overflow_feature?(name)
        set_internal_feature(name, false)
        next
      end

      send("feature_#{name}=", false)
    end
  end

  def disable_features!(*names)
    disable_features(*names)
    save
  end

  def feature_enabled?(name)
    return internal_feature_enabled?(name) if overflow_feature?(name)

    send("feature_#{name}?")
  end

  def all_features
    FEATURE_LIST.pluck('name').index_with do |feature_name|
      feature_enabled?(feature_name)
    end
  end

  def enabled_features
    all_features.select { |_feature, enabled| enabled == true }
  end

  def disabled_features
    all_features.select { |_feature, enabled| enabled == false }
  end

  private

  def overflow_feature?(name)
    feature_index(name).to_i > MAX_BIGINT_FEATURE_INDEX
  end

  def feature_index(name)
    FEATURES.key("feature_#{name}".to_sym)
  end

  def internal_feature_enabled?(name)
    internal_feature_flags[name.to_s] == true
  end

  def set_internal_feature(name, enabled)
    attributes = internal_attributes.to_h.deep_dup
    attributes[INTERNAL_FEATURE_FLAGS_KEY] ||= {}
    attributes[INTERNAL_FEATURE_FLAGS_KEY][name.to_s] = enabled
    self.internal_attributes = attributes
  end

  def internal_feature_flags
    internal_attributes.to_h.fetch(INTERNAL_FEATURE_FLAGS_KEY, {})
  end

  def enable_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return true if config.blank?

    features_to_enabled = config.value.select { |f| f[:enabled] }.pluck(:name)
    enable_features(*features_to_enabled)
  end
end
