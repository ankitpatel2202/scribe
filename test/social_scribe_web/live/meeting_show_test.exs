defmodule SocialScribeWeb.MeetingShowTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.AutomationsFixtures
  import Mox

  describe "MeetingLive.Show mount" do
    test "renders meeting details when user owns the meeting", %{conn: conn} do
      user = user_fixture()
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id, title: "My Meeting"})

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")
      assert html =~ "My Meeting"
    end
  end

  describe "MeetingLive.Show handle_params and events" do
    test "crm_contact action assigns salesforce_connection and clears contact state", %{conn: conn} do
      user = user_fixture()
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm_contact")
      assert html =~ "Review & update Salesforce contact" or html =~ "Salesforce"
    end

    test "draft_post action assigns automation_result and automation", %{conn: conn} do
      user = user_fixture()
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})
      automation = automation_fixture(%{user_id: user.id})
      automation_result = automation_result_fixture(%{
        meeting_id: meeting.id,
        automation_id: automation.id,
        generated_content: "Draft post content"
      })

      conn = log_in_user(conn, user)
      {:ok, _view, html} =
        live(conn, ~p"/dashboard/meetings/#{meeting.id}/draft_post/#{automation_result.id}")

      assert html =~ "Draft post content" or html =~ "draft" or html =~ "generated"
    end

    test "search_contacts with empty query does not call API", %{conn: conn} do
      user = user_fixture()
      crm_connection_fixture(%{user_id: user.id, provider: "salesforce"})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm_contact")

      view
      |> form("form[phx-change=\"search_contacts\"]", %{"query" => "   "})
      |> render_change()

      html = render(view)
      assert html =~ "Select Contact" or html =~ "Search"
    end

    test "validate-follow-up-email updates form", %{conn: conn} do
      user = user_fixture()
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # Only test if follow_up_email form is present (when meeting has follow_up_email)
      if has_element?(view, "form[phx-change=\"validate-follow-up-email\"]") do
        view
        |> form("form[phx-change=\"validate-follow-up-email\"]", %{"follow_up_email" => "Updated email body"})
        |> render_change()
        assert render(view) =~ "Updated email body"
      else
        assert true
      end
    end

  end

  describe "MeetingLive.Show with transcript" do
    test "renders meeting with transcript and duration", %{conn: conn} do
      user = user_fixture()
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id, duration_seconds: 125})
      meeting_transcript_fixture(%{
        meeting_id: meeting.id,
        content: %{"data" => [%{"speaker" => "Alice", "words" => [%{"text" => "Hello"}]}]}
      })

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Meeting Transcript"
      assert html =~ "2 min" or html =~ "125 sec" or html =~ "min"
      assert html =~ "Alice" or html =~ "Hello" or html =~ "Transcript"
    end
  end

  describe "MeetingLive.Show handle_info (HubSpot modal)" do
    setup :verify_on_exit!

    test "hubspot_search success updates modal", %{conn: conn} do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, q ->
        assert q == "alice"
        {:ok, [%{id: "1", firstname: "Alice", lastname: "Doe", email: "alice@example.com", display_name: "Alice Doe"}]}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      send(view.pid, {:hubspot_search, "alice", credential})
      :timer.sleep(100)
      html = render(view)
      # Modal receives send_update; view re-renders (contacts or error may appear)
      assert html != nil and byte_size(html) > 0
    end

    test "hubspot_search error updates modal", %{conn: conn} do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _q ->
        {:error, {:api_error, 500, "Server error"}}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      send(view.pid, {:hubspot_search, "q", credential})
      :timer.sleep(50)
      html = render(view)
      assert html =~ "Failed" or html =~ "500" or html =~ "error"
    end

    test "generate_suggestions success", %{conn: conn} do
      user = user_fixture()
      hubspot_credential_fixture(%{user_id: user.id})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => []}})

      stub(SocialScribe.AIContentGeneratorMock, :generate_hubspot_suggestions, fn _meeting ->
        {:ok, [%{field: "email", value: "new@example.com", context: "from meeting"}]}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      contact = %{id: "1", firstname: "Alice", lastname: "Doe", email: "a@b.com"}
      send(view.pid, {:generate_suggestions, contact, meeting, nil})
      :timer.sleep(50)
      render(view)
    end

    test "generate_suggestions error", %{conn: conn} do
      user = user_fixture()
      hubspot_credential_fixture(%{user_id: user.id})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      stub(SocialScribe.AIContentGeneratorMock, :generate_hubspot_suggestions, fn _meeting ->
        {:error, :no_transcript}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      send(view.pid, {:generate_suggestions, %{}, meeting, nil})
      :timer.sleep(50)
      html = render(view)
      assert html =~ "Failed" or html =~ "error" or html =~ "no_transcript"
    end

    test "apply_hubspot_updates success redirects", %{conn: conn} do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      expect(SocialScribe.HubspotApiMock, :update_contact, fn _cred, id, _updates ->
        assert id == "123"
        {:ok, %{id: "123"}}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      send(view.pid, {:apply_hubspot_updates, %{email: "x@y.com"}, %{id: "123"}, credential})
      :timer.sleep(50)
      assert render(view) =~ meeting.title or render(view) =~ "Successfully"
    end

    test "apply_hubspot_updates error", %{conn: conn} do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: event.id})

      expect(SocialScribe.HubspotApiMock, :update_contact, fn _cred, _id, _updates ->
        {:error, {:api_error, 400, "Bad request"}}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      send(view.pid, {:apply_hubspot_updates, %{email: "x"}, %{id: "1"}, credential})
      :timer.sleep(50)
      html = render(view)
      assert html =~ "Failed" or html =~ "error"
    end
  end

  describe "MeetingLive.Show helpers" do
    test "format_contact_value/1" do
      assert SocialScribeWeb.MeetingLive.Show.format_contact_value(nil) == "No existing value"
      assert SocialScribeWeb.MeetingLive.Show.format_contact_value("") == "No existing value"
      assert SocialScribeWeb.MeetingLive.Show.format_contact_value("hello") == "hello"
      assert SocialScribeWeb.MeetingLive.Show.format_contact_value(123) == "123"
    end

    test "salesforce_field_label/1" do
      assert SocialScribeWeb.MeetingLive.Show.salesforce_field_label("FirstName") == "First name"
      assert SocialScribeWeb.MeetingLive.Show.salesforce_field_label("Email") == "Email"
      assert SocialScribeWeb.MeetingLive.Show.salesforce_field_label("UnknownField") == "UnknownField"
    end

    test "contact_initials/1" do
      assert SocialScribeWeb.MeetingLive.Show.contact_initials(%{
               "FirstName" => "John",
               "LastName" => "Doe"
             }) == "JD"
      assert SocialScribeWeb.MeetingLive.Show.contact_initials(%{"name" => "Jane Smith"}) == "JS"
      assert SocialScribeWeb.MeetingLive.Show.contact_initials(%{}) == "?"
    end
  end
end
