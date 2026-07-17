defmodule WekuiWeb.PageController do
  use WekuiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
