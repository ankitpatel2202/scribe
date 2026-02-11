defmodule SocialScribeWeb.MeetingLive.DraftPostFormComponentTest do
  use SocialScribeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.AutomationsFixtures
  import Mox

  setup :verify_on_exit!

  describe "DraftPostFormComponent" do
    test "renders with draft content and form", %{conn: conn} do
      user = user_fixture()
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})
      automation = automation_fixture(%{user_id: user.id, platform: :linkedin})
      automation_result =
        automation_result_fixture(%{
          automation_id: automation.id,
          meeting_id: meeting.id,
          generated_content: "My draft post content"
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/draft_post/#{automation_result.id}")

      assert html =~ "Draft Post"
      assert html =~ "My draft post content"
      assert has_element?(view, "#draft-post-form")
    end

    test "validate event updates form", %{conn: conn} do
      user = user_fixture()
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})
      automation = automation_fixture(%{user_id: user.id, platform: :linkedin})
      automation_result =
        automation_result_fixture(%{
          automation_id: automation.id,
          meeting_id: meeting.id,
          generated_content: "Original"
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/draft_post/#{automation_result.id}")

      view
      |> form("#draft-post-form", %{"generated_content" => "Updated content"})
      |> render_change()

      assert render(view) =~ "Updated content"
    end

    test "post event success shows flash and patches", %{conn: conn} do
      user = user_fixture()
      _cred = user_credential_fixture(%{user_id: user.id, provider: "linkedin", uid: "urn:li:person:1", token: "t"})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})
      automation = automation_fixture(%{user_id: user.id, platform: :linkedin})
      automation_result =
        automation_result_fixture(%{
          automation_id: automation.id,
          meeting_id: meeting.id,
          generated_content: "Post this"
        })

      SocialScribe.LinkedInApiMock
      |> stub(:post_text_share, fn _token, _urn, _text -> {:ok, %{"id" => "share_1"}} end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/draft_post/#{automation_result.id}")

      view
      |> form("#draft-post-form", %{"generated_content" => "Post this"})
      |> render_submit()

      assert render(view) =~ "Post successful"
    end

    test "post event error shows flash", %{conn: conn} do
      user = user_fixture()
      _cred = user_credential_fixture(%{user_id: user.id, provider: "linkedin", uid: "urn:li:person:1", token: "t"})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})
      automation = automation_fixture(%{user_id: user.id, platform: :linkedin})
      automation_result =
        automation_result_fixture(%{
          automation_id: automation.id,
          meeting_id: meeting.id,
          generated_content: "Post this"
        })

      SocialScribe.LinkedInApiMock
      |> stub(:post_text_share, fn _token, _urn, _text -> {:error, "Post failed"} end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/draft_post/#{automation_result.id}")

      view
      |> form("#draft-post-form", %{"generated_content" => "Post this"})
      |> render_submit()

      assert render(view) =~ "Post failed"
    end
  end
end
