class I18nContent < ApplicationRecord

  scope :by_key,          ->(key) { where(key: key) }

  validates :key, uniqueness: true

  translates :value, touch: true
  globalize_accessors

  # flat_hash returns a flattened hash, a hash with a single level of
  # depth in which each key is composed from the keys of the original
  # hash (whose value is not a hash) by typing in the key of the route
  # from the first level of the original hash
  #
  # Examples:
  #
  # hash = {
  #   'key1' => 'value1',
  #   'key2' => { 'key3' => 'value2',
  #               'key4' => { 'key5' => 'value3' } }
  # }
  #
  # I18nContent.flat_hash(hash) = {
  #   'key1' => 'value1',
  #   'key2.key3' => 'value2',
  #   'key2.key4.key5' => 'value3'
  # }
  #
  # I18nContent.flat_hash(hash, 'string') = {
  #   'string.key1' => 'value1',
  #   'string.key2.key3' => 'value2',
  #   'string.key2.key4.key5' => 'value3'
  # }
  #
  # I18nContent.flat_hash(hash, 'string', { 'key6' => 'value4' }) = {
  #   'key6' => 'value4',
  #   'string.key1' => 'value1',
  #   'string.key2.key3' => 'value2',
  #   'string.key2.key4.key5' => 'value3'
  # }

  def self.flat_hash(input, path = nil, output = {})
    return output.update({ path => input }) unless input.is_a? Hash
    input.map { |key, value| flat_hash(value, [path, key].compact.join("."), output) }
    return output
  end

  def self.content_for(tab)
    flat_hash(translations_for(tab)).keys.map do |string|
      I18nContent.find_or_initialize_by(key: string)
    end
  end

  def self.translations_for(tab)
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?

    if tab.to_sym == :basic
      basic_file = "#{Rails.root}/config/locales/#{I18n.locale}/basic.yml"

      if File.exists?(basic_file)
        I18n.backend.send(:load_file, basic_file)[I18n.locale.to_s]
      else
        {}
      end
    else
      I18n.backend.send(:translations)[I18n.locale].select do |key, _translations|
        key.to_s == tab.to_s
      end
    end
  end
end
