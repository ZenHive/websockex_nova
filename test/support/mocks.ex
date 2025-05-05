defmodule WebsockexNova.Mocks do
  @moduledoc """
  Mock definitions for WebsockexNova tests.
  """

  # Define mock for the Client behavior
  Mox.defmock(WebsockexNova.ClientMock, for: WebsockexNova.Behaviours.ClientBehavior)
end
