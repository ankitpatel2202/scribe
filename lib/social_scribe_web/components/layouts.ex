defmodule SocialScribeWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use SocialScribeWeb, :controller` and
  `use SocialScribeWeb, :live_view`.
  """
  use SocialScribeWeb, :html

  import SocialScribeWeb.Sidebar

  embed_templates "layouts/*"

  @doc "Returns layout names (used by tests so coverage attributes runtime execution to this module)."
  def layout_names, do: ["root", "app", "dashboard"]
end
