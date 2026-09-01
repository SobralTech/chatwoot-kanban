class FixImmutableUnaccentFunctionSearchPath < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION public.immutable_unaccent(text)
      RETURNS text AS $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$
      LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT;
    SQL
  end

  def down
    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION public.immutable_unaccent(text)
      RETURNS text AS $$ SELECT unaccent('unaccent', $1) $$
      LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT;
    SQL
  end
end
