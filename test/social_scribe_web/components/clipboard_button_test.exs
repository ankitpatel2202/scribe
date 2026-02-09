defmodule SocialScribeWeb.ClipboardButtonTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "ClipboardButtonComponent" do
    test "render shows Copy text and copy button" do
      html =
        render_component(SocialScribeWeb.ClipboardButtonComponent,
          id: "test-clipboard",
          text: "copy me"
        )

      assert html =~ "Copy"
      assert html =~ "copy me"
      assert html =~ "phx-click=\"copy\""
    end
  end
end
