defmodule Phoenix.LiveView.Async.Private do
  @moduledoc false

  defstruct [:active_refs, :canceled_refs, :ignored_refs, :tasks]

  def new do
    %__MODULE__{
      active_refs: MapSet.new(),
      canceled_refs: MapSet.new(),
      ignored_refs: MapSet.new(),
      tasks: %{}
    }
  end

  def add(private, key, function) do
    %Task{ref: ref} =
      task =
      if Application.get_env(:live_view_async, :async) == false do
        Task.completed(function.())
      else
        Task.async(function)
      end

    active_refs = MapSet.put(private.active_refs, ref)
    tasks = Map.put(private.tasks, key, task)

    %__MODULE__{private | active_refs: active_refs, tasks: tasks}
  end

  def cancel(private, key) do
    case Map.fetch(private.tasks, key) do
      {:ok, %Task{ref: ref} = task} ->
        Task.shutdown(task)

        canceled_refs = MapSet.delete(private.canceled_refs, ref)
        tasks = Map.delete(private.tasks, key)

        %__MODULE__{private | canceled_refs: canceled_refs, tasks: tasks}

      :error ->
        private
    end
  end

  def has_key?(private, key), do: Map.has_key?(private.tasks, key)

  def ignore(private, key) do
    case Map.fetch(private.tasks, key) do
      {:ok, %Task{ref: ref} = task} ->
        Task.ignore(task)

        ignored_refs = MapSet.delete(private.ignored_refs, ref)
        tasks = Map.delete(private.tasks, key)

        %__MODULE__{private | ignored_refs: ignored_refs, tasks: tasks}

      :error ->
        private
    end
  end

  def ref_active?(private, ref), do: ref in private.active_refs

  def ref_known?(private, ref) do
    ref in private.active_refs or ref in private.canceled_refs or ref in private.ignored_refs
  end

  def remove(private, ref) do
    Process.demonitor(ref, [:flush])

    active_refs = MapSet.delete(private.active_refs, ref)
    canceled_refs = MapSet.delete(private.canceled_refs, ref)
    ignored_refs = MapSet.delete(private.ignored_refs, ref)
    tasks = Map.reject(private, fn {_key, %Task{ref: r}} -> r == ref end)

    %__MODULE__{
      private
      | active_refs: active_refs,
        canceled_refs: canceled_refs,
        ignored_refs: ignored_refs,
        tasks: tasks
    }
  end
end
