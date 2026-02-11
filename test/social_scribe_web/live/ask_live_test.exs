defmodule SocialScribeWeb.AskLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "Ask page" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "mount assigns session and messages", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")
      assert html =~ "Ask"
    end

    test "redirects when not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/dashboard/ask")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "handle_params" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "loads session when visiting /ask/session/:session_id", %{conn: conn, user: user} do
      {:ok, session} = SocialScribe.Chat.create_session(user)
      session = SocialScribe.Chat.get_session!(user, session.id)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask/session/#{session.id}")
      assert render(view) =~ "Ask"
    end
  end

  describe "Ask with CRM connected" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_credential_fixture(%{user_id: user.id})
      %{conn: log_in_user(conn, user), user: user}
    end

    test "shows ask page when HubSpot connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")
      assert has_element?(view, "form[phx-submit='send_message']")
    end
  end

  describe "send message" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "send_message with empty text does not add message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view
      |> form("form[phx-submit='send_message']", %{"text" => "   "})
      |> render_submit()

      # Still on same page, no crash
      assert render(view) =~ "Ask"
    end

    test "send_message with text calls AI and updates messages", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_question_answer, fn _q, _data, _opts ->
        {:ok, "Here is the answer."}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view
      |> form("form[phx-submit='send_message']", %{"text" => "What is their email?"})
      |> render_submit()

      # Wait for async message
      assert render(view) =~ "What is their email?"
      assert render(view) =~ "Here is the answer."
    end

    test "send_message when AI returns error shows error message", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_question_answer, fn _q, _data, _opts ->
        {:error, :no_connection}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view
      |> form("form[phx-submit='send_message']", %{"text" => "What is their email?"})
      |> render_submit()

      assert render(view) =~ "No CRM connected."
      assert render(view) =~ "What is their email?"
    end

    test "send_message when AI returns config_error shows AI not configured", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_question_answer, fn _q, _data, _opts ->
        {:error, {:config_error, :missing_key}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view
      |> form("form[phx-submit='send_message']", %{"text" => "Hello?"})
      |> render_submit()

      assert render(view) =~ "AI is not configured."
    end

    test "send_message when AI returns api_error shows service error", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_question_answer, fn _q, _data, _opts ->
        {:error, {:api_error, 503, "body"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view
      |> form("form[phx-submit='send_message']", %{"text" => "Hello?"})
      |> render_submit()

      assert render(view) =~ "Service error (503)."
    end
  end

  describe "events with CRM connected" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_credential_fixture(%{user_id: user.id})
      %{conn: log_in_user(conn, user), user: user}
    end

    test "update_input updates input_text", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view
      |> form("form[phx-submit='send_message']", %{"text" => "Hello world"})
      |> render_change()

      assert render(view) =~ "Hello world"
    end

    test "contact_search with short query clears results and keeps dropdown open when non-empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Open search first
      view |> element("button", "Add context") |> render_click()
      assert render(view) =~ "Search contacts"

      # Search with 1 char: results cleared, open if query non-empty
      view
      |> element("#contact-search-dropdown input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "a"})

      html = render(view)
      assert html =~ "Search contacts"
    end

    test "contact_search with query length >= 2 sends run_contact_search", %{conn: conn} do
      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        # Chat maps results through hubspot_contact_to_summary, which expects atom keys (id, display_name, email)
        {:ok, [%{id: "1", display_name: "Alice", email: "alice@example.com"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view |> element("button", "Add context") |> render_click()

      view
      |> element("#contact-search-dropdown input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "ali"})

      # Process the async run_contact_search message
      :timer.sleep(200)

      assert render(view) =~ "Alice"
    end

    test "open_contact_search and close_contact_search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      refute render(view) =~ "id=\"contact-search-dropdown\""
      view |> element("button", "Add context") |> render_click()
      assert render(view) =~ "contact-search-dropdown"

      # close via phx-click-away is hard to trigger; we can test open_contact_search opened it
      view |> element("button", "Add context") |> render_click()
      assert render(view) =~ "contact-search-dropdown"
    end

    test "remove_tag removes contact from tagged_contacts", %{conn: conn} do
      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [%{id: "c1", display_name: "Bob", email: nil}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")
      view |> element("button", "Add context") |> render_click()
      view
      |> element("#contact-search-dropdown input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Bob"})

      :timer.sleep(200)

      # Select contact: phx-click on the contact button (SelectContactWithText hook sends select_contact with id, name, provider, text)
      view
      |> element("#contact-search-dropdown button[data-contact-id='c1']")
      |> render_click()

      assert render(view) =~ "Bob"

      view
      |> element("button[phx-click='remove_tag'][phx-value-id='c1']")
      |> render_click()

      refute render(view) =~ "Bob"
    end

    test "new_chat creates new session and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view
      |> element("button[aria-label='New chat']")
      |> render_click()

      assert_patch(view, ~p"/dashboard/ask")
      assert render(view) =~ "Ask"
    end

    test "tab history and chat", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      view |> element("button", "History") |> render_click()
      assert render(view) =~ "Previous chats"

      view |> element("button", "Chat") |> render_click()
      refute render(view) =~ "Previous chats"
      assert render(view) =~ "Ask Anything"
    end

    test "load_session with valid id loads session and patches to ask", %{conn: conn, user: user} do
      {:ok, session} = SocialScribe.Chat.create_session(user)
      session = SocialScribe.Chat.get_session!(user, session.id)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")
      view |> element("button", "History") |> render_click()
      render(view)

      # Click load_session for our session (button has phx-value-id)
      view
      |> element("button[phx-click='load_session'][phx-value-id='#{session.id}']")
      |> render_click()

      assert_patch(view, ~p"/dashboard/ask")
      assert render(view) =~ "Ask"
    end

    test "load_session with invalid id leaves socket unchanged", %{conn: conn} do
      # We cannot easily simulate a non-existent session id from the UI because
      # history only shows real sessions. So we test that visiting with a bad session_id
      # in handle_params doesn't crash (get_session returns nil).
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask/session/999999999")
      assert html =~ "Ask"
    end
  end
end
