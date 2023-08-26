# Async Assigns for Phoenix LiveView

Task-based system for asynchronously assigning data to a LiveView socket

## Installation

This package is not available on `hex.pm`.
Instead, install it directly from GitHub:

```elixir
def deps do
  [
    {:live_view_async, github: "aj-foster/live-view-async"}
  ]
end
```

## Usage

To use the `assign_async/3` function at the heart of this library, it is necessary to set up some additional data on the LiveView socket first.
The easiest way to set up a view is by using this module:

```elixir
use Phoenix.LiveView.Async
```

Alternatively, you can call use the `on_mount` macro directly (and separately `import Phoenix.LiveView.Async`):

```elixir
on_mount {Phoenix.LiveView.Async, :setup}
```

This will place an assign called `_async` on the socket.
It is important that other LiveView callbacks do not modify this key.

Now, use `assign_async/3` to create an asynchronous task that will update the LiveView socket at a later time:

```elixir
socket =
  socket
  |> assign(data: [], loading: false)
  |> assign_async(:get_data, fn ->
    data = MyApp.Repo.all(...)
    [data: data, loading: false]
  end)
```

The function given for the async task must return a keyword list.
Except for values that are wrapped in an `:update` tuple (see below), all of the returned values will be integrated into the socket using `Component.assign/2`:

```elixir
[data: [...], loading: false]  =>  assign(socket, data: [...], loading: false)
```

This happens at the time when the LiveView process handles the task's completion message.
It is important to note that the socket's assigns may have changed between the spawn and the completion of the task, so atomic updates (ex. incrementing numbers) should not be handled in this way.

Instead, values can be expressed as an update function wrapped in an `:update` tuple.
In this case, the values will be integrated into the socket using `Component.update/3`:

```elixir
[data: {:update, fn x -> x + 1 end}]  =>  Component.update(socket, :data, fn x -> x + 1 end)
```

Tasks may return a mix of each type of assign.

## Configuration

This library has one piece of configuration available:

```elixir
config :live_view_async, async: false
```

This causes all tasks to be run synchronously, in the same process as the caller, immediately upon calling `assign_async/3`.
This can be useful for test environments.

## Acknowledgements

The following resources were helpful while building this library:

* [_Phoenix LiveView: Async Assign Pattern_ by Andy Glassman](https://blog.andyglassman.com/2023/06/phoenix-liveview-async-assign-pattern.html)
* [_Async processing in LiveView_ by Berenice Medel](https://fly.io/phoenix-files/liveview-async-task/)
