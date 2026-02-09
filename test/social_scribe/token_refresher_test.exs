defmodule SocialScribe.TokenRefresherTest do
  use ExUnit.Case, async: false

  alias SocialScribe.TokenRefresher

  # TokenRefresher uses Application.fetch_env! for Google OAuth; set for test
  setup do
    Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth,
      client_id: "test_client_id",
      client_secret: "test_client_secret"
    )

    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)
    end)

    :ok
  end

  describe "refresh_token/1" do
    setup do
      Tesla.Mock.mock(fn %{method: :post} ->
        %Tesla.Env{status: 400, body: %{"error" => "invalid_grant"}}
      end)
      :ok
    end

    test "returns error on non-200 response" do
      assert {:error, _} = TokenRefresher.refresh_token("invalid_refresh_token")
    end
  end

  describe "client/0" do
    test "returns a Tesla client" do
      client = TokenRefresher.client()
      assert %Tesla.Client{} = client
    end
  end
end
