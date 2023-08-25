defmodule LiveViewAsyncTest do
  use ExUnit.Case
  doctest LiveViewAsync

  test "greets the world" do
    assert LiveViewAsync.hello() == :world
  end
end
