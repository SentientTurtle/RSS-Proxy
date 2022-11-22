defmodule Tweetrss.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  import Cachex.Spec

  @impl true
  def start(_type, _args) do
    if Application.get_env(:tweetrss, TweetrssWeb.Endpoint)[:twitter_token] == "OVERRIDE_BEARER_TOKEN_AT_RUNTIME" do
      raise "Twitter API bearer token not set"
    end

    children = [
      # Start the Telemetry supervisor
      TweetrssWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Tweetrss.PubSub},
      # Start the Endpoint (http/https)
      TweetrssWeb.Endpoint,
      # Start caches
      %{
        id: :feed_cache,
        start: {
          Cachex,
          :start_link,
          [
            :feed_cache,
            [
              expiration: expiration(
                default: :timer.hours(5),  # TODO: Move to config
                interval: :timer.minutes(30),
                lazy: true
              )
            ]
          ]
        }
      },
      %{
        id: :rate_limit_cache,
        start: {
          Cachex,
          :start_link,
          [
            :rate_limit_cache,
            [
              expiration: expiration(
                default: :timer.minutes(15),  # Twitter API returns 15-minute rate limit intervals; At most 15 minutes after we exceed the rate limit, we can continue issuing requests
                interval: :timer.seconds(5),
                lazy: true
              )
            ]
          ],
        }
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tweetrss.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TweetrssWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
