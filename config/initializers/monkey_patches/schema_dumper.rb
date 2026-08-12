# When working with experimental extensions, which doesn't have support on all providers
# This monkey patch will help us to ignore the extensions when dumping the schema
# Additionally we will also ignore the tables associated with those features and exentions

# Once the feature stabilizes, we can remove the tables/extension from the ignore list
# Ensure you write appropriate migrations when you do that.

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      class SchemaDumper < ConnectionAdapters::SchemaDumper
        cattr_accessor :ignore_extentions, default: []

        # schema.rb has no DSL for SQL functions, so we re-emit the ones listed here.
        # They are dumped between the extensions and the tables because expression
        # indexes (eg. kanban search) reference them at create_table time.
        cattr_accessor :dump_functions, default: %w[immutable_unaccent]

        private

        def extensions(stream)
          extensions = @connection.extensions
          return unless extensions.any?

          stream.puts '  # These extensions should be enabled to support this database'
          extensions.sort.each do |extension|
            stream.puts "  enable_extension #{extension.inspect}" unless ignore_extentions.include?(extension)
          end
          stream.puts
        end

        def types(stream)
          super
          functions(stream)
        end

        def functions(stream)
          definitions = dump_functions.filter_map { |name| function_definition(name) }
          return if definitions.empty?

          definitions.each do |definition|
            stream.puts "  execute <<~'SQL'"
            definition.each_line { |line| stream.puts "    #{line.rstrip}".rstrip }
            stream.puts '  SQL'
          end
          stream.puts
        end

        def function_definition(name)
          @connection.select_value(
            "SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = #{@connection.quote(name)} LIMIT 1"
          )
        end
      end
    end
  end
end
