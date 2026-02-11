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

    test "update assigns copied_text and shows Copied! when true" do
      html =
        render_component(SocialScribeWeb.ClipboardButtonComponent,
          id: "test-clipboard",
          text: "copy me",
          copied_text: "copy me"
        )

      assert html =~ "Copied!"
    end

    test "assign_new sets copied_text to false when not provided" do
      html =
        render_component(SocialScribeWeb.ClipboardButtonComponent,
          id: "test-clipboard",
          text: "copy me"
        )

      assert html =~ "Copy"
      refute html =~ "Copied!"
    end
  end

end
