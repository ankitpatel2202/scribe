defmodule SocialScribe.PosterTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Poster

  import SocialScribe.AccountsFixtures

  describe "post_on_social_media/3" do
    test "returns error for unsupported platform" do
      user = user_fixture()
      assert {:error, "Unsupported platform"} =
               Poster.post_on_social_media(:twitter, "content", user)
    end

    test "returns error when LinkedIn credential not found" do
      user = user_fixture()
      assert {:error, "LinkedIn credential not found"} =
               Poster.post_on_social_media(:linkedin, "content", user)
    end

    test "returns error when Facebook page credential not found" do
      user = user_fixture()
      assert {:error, "Facebook page credential not found"} =
               Poster.post_on_social_media(:facebook, "content", user)
    end
  end
end
