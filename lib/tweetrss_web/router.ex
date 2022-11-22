defmodule TweetrssWeb.Router do
  use TweetrssWeb, :router

  pipeline :api do
    plug :put_format, "xml"
  end

  scope "/", TweetrssWeb do
    pipe_through :api

    get "/feed", FeedController, :index
  end
end
