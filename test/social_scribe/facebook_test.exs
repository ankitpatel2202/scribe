defmodule SocialScribe.FacebookTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.Facebook
  alias SocialScribe.FacebookApi
  alias SocialScribe.FacebookApiMock

  import Mox

  setup :verify_on_exit!

  describe "Facebook (implementation) post_message_to_page/3" do
    @describetag :capture_log

    test "returns ok and response body on 200" do
      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "/feed"
        {:ok, %Tesla.Env{status: 200, body: %{"id" => "post_123"}}}
      end)

      assert {:ok, %{"id" => "post_123"}} =
               Facebook.post_message_to_page("page_1", "token", "Hello world")
    end

    test "returns api_error on non-200 status" do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 400,
           body: %{"error" => %{"message" => "Invalid token"}}
         }}
      end)

      assert {:error, {:api_error_posting, 400, "Invalid token", _}} =
               Facebook.post_message_to_page("page_1", "bad", "Hi")
    end

    test "returns http_error on request failure" do
      Tesla.Mock.mock(fn %{method: :post} -> {:error, :timeout} end)

      assert {:error, {:http_error_posting, :timeout}} =
               Facebook.post_message_to_page("page_1", "token", "Hi")
    end
  end

  describe "Facebook (implementation) fetch_user_pages/2" do
    test "returns list of pages on 200 with CREATE_CONTENT or MANAGE" do
      Tesla.Mock.mock(fn %{method: :get, url: url} ->
        assert url =~ "/accounts"
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "data" => [
               %{"id" => "p1", "name" => "Page 1", "category" => "Brand", "access_token" => "at1", "tasks" => ["CREATE_CONTENT"]},
               %{"id" => "p2", "name" => "Page 2", "category" => "Biz", "access_token" => "at2", "tasks" => ["MANAGE"]}
             ]
           }
         }}
      end)

      assert {:ok, pages} = Facebook.fetch_user_pages("user_1", "user_token")
      assert length(pages) == 2
      assert Enum.any?(pages, fn p -> p.id == "p1" and p.name == "Page 1" end)
    end

    test "returns error on non-200" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 401, body: %{"error" => "Unauthorized"}}}
      end)

      assert {:error, msg} = Facebook.fetch_user_pages("user_1", "bad")
      assert msg =~ "401"
    end
  end

  describe "FacebookApi with mock" do
    test "post_message_to_page uses mock and returns error" do
      FacebookApiMock
      |> stub(:post_message_to_page, fn _page_id, _token, _message ->
        {:error, {:api_error_posting, 400, "mocked", %{}}}
      end)

      assert {:error, {:api_error_posting, 400, "mocked", %{}}} =
               FacebookApi.post_message_to_page("page_id", "token", "hello")
    end

    test "fetch_user_pages uses mock and returns error" do
      FacebookApiMock
      |> stub(:fetch_user_pages, fn _user_id, _token ->
        {:error, "mocked"}
      end)

      assert {:error, "mocked"} = FacebookApi.fetch_user_pages("user_id", "token")
    end
  end
end
