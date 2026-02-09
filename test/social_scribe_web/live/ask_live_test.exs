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
      |> expect(:generate_contact_question_answer, fn _q, _data ->
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
  end
end
