defmodule Phoenix.LiveView.Async do
  @moduledoc """
  Task-based system for asynchronously assigning data to a LiveView socket

  ## Usage

  Use the `assign_async/3` function to create an asynchronous task that will update the socket
  state at a future time.

  ## Setup

  Use of the `assign_async/3` function requires some additional data on the LiveView socket. The
  easiest way to set up a view is by using this module:

      use #{inspect(__MODULE__)}

  Alternatively, you can call use the `on_mount` macro directly:

      on_mount {#{inspect(__MODULE__)}, :setup}

  This will place an assign called `_async` on the socket. It is important that other LiveView
  callbacks do not modify this key.
  """
  require Phoenix.LiveView

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Async.Private
  alias Phoenix.LiveView.Socket

  #
  # Public Function
  #

  @doc """
  Spawn an async task and assign the results to the socket once available

  This function is meant to unblock the LiveView process while expensive operations (such as long
  database queries) are in progress. The caller must supply a function that returns a keyword list
  of updated assigns. Once received, these updated assigns will be integrated into the socket once
  the task is complete.

  The `key` acts as a name for the task, and **does not** translate to a key in the `assigns` of
  the socket. Keys can be reused, however older task results will be ignored if their keys are
  used to start a new task before they complete.

  > #### Note {:.info}
  >
  > Due to the async nature of the assignment, this function will only perform the asynchronous
  > work if the socket is connected (not on an initial, disconnected load).

  It is the responsibility of the supplied function to handle errors appropriately.

  ## Setup

  Use of this function requires some initial setup in the view. See this module's documentation
  for more details.

  ## Return Values

  The function given for the async task must return a keyword list. Except for values that are
  wrapped in an `:update` tuple (see below), all of the returned values will be integrated into
  the socket using `Component.assign/2`:

  ```
  [data: [...], loading: false]  =>  assign(socket, data: [...], loading: false)
  ```

  This happens at the time when the LiveView process handles the task's completion message. It is
  important to note that the socket's assigns may have changed between the spawn and the
  completion of the task, so atomic updates (ex. incrementing numbers) should not be handled in
  this way.

  Instead, values can be expressed as an update function wrapped in an `:update` tuple. In this
  case, the values will be integrated into the socket using `Component.update/3`:

  ```
  [data: {:update, fn x -> x + 1 end}]  =>  Component.update(socket, :data, fn x -> x + 1 end)
  ```

  Tasks may return a mix of each type of assign.

  ## Examples

  It is likely that the caller will want to assign default values for the assigns returned by the
  async function in order to avoid rendering with missing assigns.

      def mount(_params, _session, socket) do
        socket =
          socket
          |> assign(data: [], loading: true)
          |> assign_async(:data, &get_data/0)

        {:ok, socket}
      end

      defp get_data do
        data = MyApp.Repo.all(...)
        [data: data, loading: false]
      end

  Callers may use anonymous functions to create a closure for values present in the caller,
  however it is important to note that those values may change by the time the task completes and
  updates are made to the socket.

      def mount(params, _session, socket) do
        socket =
          socket
          |> assign(data: [], loading: true)
          |> assign_async(:data, fn -> get_other_data(params) end)

        {:ok, socket}
      end

      defp get_other_data(params) do
        # ...
      end

  If atomic updates are required, the task may return an update function wrapped in a tuple:

      defp get_data do
        count = MyApp.Repo.aggregate(...)

        [
          data: {:update, fn current_value -> current_value + count end}
          loading: false
        ]
      end

  """
  @spec assign_async(Socket.t(), atom, (-> keyword)) :: Socket.t()
  def assign_async(%Socket{assigns: %{_async: private}} = socket, key, function) do
    cond do
      not LiveView.connected?(socket) ->
        socket

      Private.has_key?(private, key) ->
        private =
          private
          |> Private.ignore(key)
          |> Private.add(key, function)

        Component.assign(socket, _async: Private.add(private, key, function))

      :else ->
        Component.assign(socket, _async: Private.add(private, key, function))
    end
  end

  #
  # Hooks
  #

  @doc false
  defmacro __using__(_opts) do
    quote do
      LiveView.on_mount({Phoenix.LiveView.Async, :setup})
    end
  end

  @doc false
  def on_mount(:setup, _params, _session, socket) do
    socket =
      Component.assign(socket, _async: Private.new())
      |> LiveView.attach_hook(:setup_assign_async, :handle_info, &assign_async_handle_info/2)

    {:cont, socket}
  end

  # Takes the role of the receive block in `Task.await/1`.
  @spec assign_async_handle_info(term, Socket.t()) :: {:cont | :halt, Socket.t()}
  defp assign_async_handle_info(
         {ref, assigns},
         %Socket{assigns: %{_async: private}} = socket
       )
       when is_reference(ref) do
    cond do
      Private.ref_active?(private, ref) ->
        {updates, overwrites} =
          Enum.split_with(assigns, fn
            {_key, {:update, fun}} when is_function(fun, 1) -> true
            _else -> false
          end)

        socket =
          socket
          |> Component.assign(_async: Private.remove(private, ref))
          |> Component.assign(overwrites)

        socket =
          for {key, update_fun} <- updates, reduce: socket do
            socket -> Component.update(socket, key, update_fun)
          end

        {:halt, socket}

      Private.ref_known?(private, ref) ->
        {:halt, Component.assign(socket, _async: Private.remove(private, ref))}

      # Unrelated Task or message
      :else ->
        {:cont, socket}
    end
  end

  defp assign_async_handle_info(
         {:DOWN, ref, _, _proc, reason},
         %Socket{assigns: %{_async: private}} = socket
       ) do
    cond do
      Private.ref_active?(private, ref) ->
        exit(reason)

      Private.ref_known?(private, ref) ->
        {:halt, Component.assign(socket, _async: Private.remove(private, ref))}

      :else ->
        {:cont, socket}
    end
  end

  defp assign_async_handle_info(_message, socket), do: {:cont, socket}
end
