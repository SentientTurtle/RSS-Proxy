defmodule Tweet do
  defstruct(
    id: nil,
    title: nil,
    link: nil,
    date: nil,
    author: nil,
    content: nil
  )
end

defmodule Feed do
  defstruct(
    id: nil,
    title: nil,
    icon: "https://abs.twimg.com/favicons/twitter.2.ico", # Default to twitter's favicon
    updated: nil
  )
end
