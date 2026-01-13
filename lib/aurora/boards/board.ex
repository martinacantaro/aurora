defmodule Aurora.Boards.Board do
  use Ecto.Schema
  import Ecto.Changeset

  schema "boards" do
    field :name, :string
    field :position, :integer, default: 0

    has_many :columns, Aurora.Boards.Column, preload_order: [asc: :position]

    timestamps()
  end

  def changeset(board, attrs) do
    board
    |> cast(attrs, [:name, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
