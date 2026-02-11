defmodule SocialScribe.ReleaseTest do
  use ExUnit.Case, async: false

  alias SocialScribe.Release

  describe "Release module" do
    test "migrate/0 and rollback/2 are defined" do
      Code.ensure_loaded!(Release)
      funcs = Release.__info__(:functions)
      assert Keyword.has_key?(funcs, :migrate)
      assert funcs[:migrate] == 0
      assert Keyword.has_key?(funcs, :rollback)
      assert funcs[:rollback] == 2
    end

    test "migrate/0 runs load_app and repos when ecto_repos is temporarily empty" do
      # Run migrate with no repos so we exercise load_app and the migrate loop without touching DB
      original = Application.fetch_env!(:social_scribe, :ecto_repos)
      Application.put_env(:social_scribe, :ecto_repos, [])

      try do
        # migrate/0 returns the result of the for comprehension ([] when no repos)
        assert [] = Release.migrate()
      after
        Application.put_env(:social_scribe, :ecto_repos, original)
      end
    end
  end
end
