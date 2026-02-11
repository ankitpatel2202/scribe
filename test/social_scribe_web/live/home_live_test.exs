defmodule SocialScribeWeb.HomeLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.CalendarFixtures

  describe "HomeLive" do
    setup :register_and_log_in_user

    test "mount assigns page title and loading", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Upcoming Meetings"
      assert html =~ "Syncing your calendars"
    end

    test "mount shows page and sync message", %{conn: conn, user: user} do
      _event =
        calendar_event_fixture(%{
          user_id: user.id,
          start_time: DateTime.add(DateTime.utc_now(), 3600, :second),
          end_time: DateTime.add(DateTime.utc_now(), 7200, :second),
          summary: "Team standup"
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Upcoming Meetings"
      assert html =~ "Syncing your calendars" or html =~ "Team standup"
    end

    test "toggle_record toggles record_meeting", %{conn: conn, user: user} do
      event =
        calendar_event_fixture(%{
          user_id: user.id,
          start_time: DateTime.add(DateTime.utc_now(), 3600, :second),
          end_time: DateTime.add(DateTime.utc_now(), 7200, :second),
          summary: "Toggle test",
          record_meeting: false
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      send(view.pid, {:sync_calendars_done, {:ok, [event]}})
      render(view)

      view
      |> element("input[phx-click=\"toggle_record\"][phx-value-id=\"#{event.id}\"]")
      |> render_click()

      updated = SocialScribe.Calendar.get_calendar_event!(event.id)
      assert updated.record_meeting == true
    end

    test "handle_info sync_calendars_done error sets flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      send(view.pid, {:sync_calendars_done, {:error, :timeout}})
      html = render(view)
      assert html =~ "Calendar sync failed"
    end
  end
end
