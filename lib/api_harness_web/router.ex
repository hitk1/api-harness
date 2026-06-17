defmodule ApiHarnessWeb.Router do
  use ApiHarnessWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :accepts, ["json"]
    plug ApiHarnessWeb.Plugs.Authenticate
  end

  # Public endpoints — no authentication required.
  scope "/api", ApiHarnessWeb do
    pipe_through :api

    post "/login", AuthController, :login
  end

  # Protected endpoints — JWT required (assigns current_user).
  scope "/api", ApiHarnessWeb do
    pipe_through :api_auth

    resources "/chats", ChatController, only: [:index, :create, :show] do
      post "/messages", MessageController, :create, as: :message
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:api_harness, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: ApiHarnessWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
