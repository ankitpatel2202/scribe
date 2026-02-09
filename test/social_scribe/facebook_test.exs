defmodule SocialScribe.FacebookTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.FacebookApi
  alias SocialScribe.FacebookApiMock

  import Mox

  setup :verify_on_exit!

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
