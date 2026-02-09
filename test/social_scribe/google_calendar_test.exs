defmodule SocialScribe.GoogleCalendarTest do
  use ExUnit.Case, async: true

  alias SocialScribe.GoogleCalendar

  setup do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 401, body: %{"error" => "mocked"}}
    end)
    :ok
  end

  describe "list_events/4" do
    test "returns error with invalid token" do
      assert {:error, _} =
               GoogleCalendar.list_events(
                 "invalid_token",
                 ~U[2025-01-01 00:00:00Z],
                 ~U[2025-01-02 00:00:00Z],
                 "primary"
               )
    end
  end
end
