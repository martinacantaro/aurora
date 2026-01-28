defmodule AuroraWeb.Router do
  use AuroraWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AuroraWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug AuroraWeb.Plugs.Auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes (no auth required)
  scope "/", AuroraWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # Protected routes (auth required)
  scope "/", AuroraWeb do
    pipe_through [:browser, :authenticated]

    live "/", DashboardLive.Index, :index
    live "/boards", BoardLive.Index, :index
    live "/boards/new", BoardLive.Index, :new
    live "/boards/:id", BoardLive.Show, :show
    live "/boards/:id/edit", BoardLive.Show, :edit
    live "/habits", HabitLive.Index, :index
    live "/goals", GoalLive.Index, :index
    live "/journal", JournalLive.Index, :index
    live "/finance", FinanceLive.Index, :index
    live "/calendar", CalendarLive.Index, :index
    live "/assistant", AssistantLive.Index, :index
    live "/assistant/:id", AssistantLive.Index, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", AuroraWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:aurora, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AuroraWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
