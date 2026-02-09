defmodule SocialScribe.LinkedInTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.LinkedInApi
  alias SocialScribe.LinkedInApiMock

  import Mox

  setup :verify_on_exit!

  describe "LinkedInApi with mock" do
    test "post_text_share uses mock and returns error" do
      LinkedInApiMock
      |> stub(:post_text_share, fn _token, _urn, _text ->
        {:error, {:api_error, 401, "mocked", %{}}}
      end)

      assert {:error, {:api_error, 401, "mocked", %{}}} =
               LinkedInApi.post_text_share("token", "urn:li:person:123", "Hello")
    end
  end
end
