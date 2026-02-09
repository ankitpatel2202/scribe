defmodule SocialScribe.ReleaseTest do
  use ExUnit.Case, async: false

  alias SocialScribe.Release

  # Release.migrate/0 and rollback/2 use Ecto.Migrator which requires the repo
  # outside the test sandbox. We only test that the module and API exist.
  describe "Release module" do
    test "migrate/0 and rollback/2 are defined" do
      Code.ensure_loaded!(Release)
      funcs = Release.__info__(:functions)
      assert Keyword.has_key?(funcs, :migrate)
      assert funcs[:migrate] == 0
      assert Keyword.has_key?(funcs, :rollback)
      assert funcs[:rollback] == 2
    end
  end
end
