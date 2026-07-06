defmodule ExNtfy.Attachment do
  @moduledoc """
  An attachment on a received ntfy message.

  For server-hosted uploads all five fields are set; for attach-by-URL messages
  only `name` and `url` are present.
  """

  @enforce_keys [:name, :url]
  defstruct [:name, :url, :type, :size, :expires]

  @type t :: %__MODULE__{
          name: String.t(),
          url: String.t(),
          type: String.t() | nil,
          size: non_neg_integer() | nil,
          expires: integer() | nil
        }

  @doc """
  Builds an attachment from a decoded JSON map.

  Lenient: missing fields become `nil`, unknown fields are ignored.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: map["name"],
      url: map["url"],
      type: map["type"],
      size: map["size"],
      expires: map["expires"]
    }
  end
end
