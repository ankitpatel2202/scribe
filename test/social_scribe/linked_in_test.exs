defmodule SocialScribe.LinkedInTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.LinkedIn
  alias SocialScribe.LinkedInApi
  alias SocialScribe.LinkedInApiMock

  import Mox

  setup :verify_on_exit!

  describe "LinkedIn (implementation) post_text_share/3" do
    @describetag :capture_log

    test "returns ok and response body on 201" do
      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "/ugcPosts"
        {:ok, %Tesla.Env{status: 201, body: %{"id" => "share_123"}}}
      end)

      assert {:ok, %{"id" => "share_123"}} =
               LinkedIn.post_text_share("token", "urn:li:person:123", "Hello world")
    end

    test "returns api_error on non-201 status" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 401, body: %{"message" => "Unauthorized"}}}
      end)

      assert {:error, {:api_error, 401, "Unauthorized", _}} =
               LinkedIn.post_text_share("bad", "urn:li:person:123", "Hi")
    end

    test "returns http_error on request failure" do
      Tesla.Mock.mock(fn %{method: :post} -> {:error, :timeout} end)

      assert {:error, {:http_error, :timeout}} =
               LinkedIn.post_text_share("token", "urn:li:person:123", "Hi")
    end
  end

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
