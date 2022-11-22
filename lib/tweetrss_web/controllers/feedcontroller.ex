defmodule TweetrssWeb.FeedController do
  use TweetrssWeb, :controller
  plug :put_layout, false

  # Utility function; Convert twitter's date format to RFC3339 (for use in atom feeds)
  def date_to_rfc3339(datestring) do
    Timex.parse!(datestring, "{WDshort} {Mshort} {D} {h24}:{m}:{s} {Z} {YYYY}")
    |> Timex.format!("{RFC3339}")
  end

  def index(conn, %{"id"=> id}) do
    index(conn, id, "https://api.twitter.com/1.1/statuses/user_timeline.json?user_id=#{URI.encode(id)}&tweet_mode=extended")
  end

  def index(conn, %{"name"=> name}) do
    index(conn, name, "https://api.twitter.com/1.1/statuses/user_timeline.json?screen_name=#{URI.encode(name)}&tweet_mode=extended")
  end

  # No parameters given
  def index(conn, %{}) do
    conn
    |> put_status(400)
    |> text("Must provide 'id' or 'name' parameter")
  end

  def index(conn, cache_key, twitter_user_timeline_url) do
    cached = Cachex.fetch!(:feed_cache, cache_key, fn(_key) ->
      if Cachex.get(:rate_limit_cache, :rate_limit) <= 0 do # Guard clause for rate limit
        {:ignore, {:too_many_requests}}
      else
        response = HTTPoison.request(
          :get,
          twitter_user_timeline_url,
          "",
          [{"Authorization", "Bearer #{Application.get_env(:tweetrss, TweetrssWeb.Endpoint)[:twitter_token]}"}]
        )

        case response do
          {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}} ->
            # Insert rate limit into cache
            {_, rate_limit_string} = Enum.find(headers, {nil, "0"}, fn {key, _} -> key == "x-rate-limit-remaining" end)
            {rate_limit, _} = Integer.parse(rate_limit_string)
            Cachex.put(:rate_limit_cache, :rate_limit, rate_limit)

            json = Jason.decode!(body);
            if is_list(json) and length(json) > 0 do
              [first | _] = json;
              metadata = %Feed{
                id: Phoenix.HTML.html_escape(first["user"]["id_str"]),
                title: Phoenix.HTML.html_escape("#{first["user"]["name"]} on twitter"),
                updated: Phoenix.HTML.html_escape(date_to_rfc3339(first["created_at"]))
              };

              entries = json |> Stream.filter(fn tweet -> tweet["in_reply_to_status_id"] == nil end) |> Enum.map(fn tweet ->
                [first, last] = tweet["display_text_range"]
                content = String.slice(tweet["full_text"], first..last)
                images = if is_list(tweet["extended_entities"]["media"]) and length(tweet["extended_entities"]["media"]) do
                  tweet["extended_entities"]["media"]
                  |> Stream.map(fn media -> "<img src=\"#{media["media_url_https"]}\"/>" end)
                  |> Enum.join("<br/>")
                else
                  ""
                end
                %Tweet {
                  id: Phoenix.HTML.html_escape(tweet["id_str"]),
                  title: Phoenix.HTML.html_escape(tweet["full_text"]),
                  link: "https://twitter.com/#{tweet["user"]["screen_name"]}/status/#{tweet["id_str"]}",
                  date: Phoenix.HTML.html_escape(date_to_rfc3339(tweet["created_at"])),
                  author: Phoenix.HTML.html_escape(tweet["user"]["name"]),
                  content: Phoenix.HTML.html_escape([content | images])
                }
              end)

              {:commit, {:ok, %{metadata: metadata, entries: entries}}}
            else
              {:ignore, {:empty}}
            end
          {:ok, %HTTPoison.Response{status_code: 429}} ->
            Cachex.put(:rate_limit_cache, :rate_limit, 0)
            {:commit, {:not_found}}
          {:ok, %HTTPoison.Response{status_code: 404}} -> {:commit, {:not_found}}
          {:error, %HTTPoison.Error{reason: reason}} -> {:ignore, {:error, reason}}
          b ->
            IO.inspect(b)
            {:ignore, {:error}}
        end
      end
    end)
    case cached do
      {:ok, assigns} -> conn
        |> put_resp_content_type("application/xml")
        |> render("feed.xml", assigns)
      {:empty} -> conn
        |> put_status(200)
        |> text("<?xml version=\"1.0\" encoding=\"utf-8\"?><feed xmlns=\"http://www.w3.org/2005/Atom\"/>")
      {:not_found} -> conn
        |> put_status(404)
        |> text("Not found")
      {:too_many_requests} -> conn
        |> put_status(429)
        |> text("Too many requests")
      {:error, reason} -> conn
        |> put_status(500)
        |> text(reason)
      {:error} -> conn
        |> put_status(500)
        |> text("Internal server error")
    end
  end
end
