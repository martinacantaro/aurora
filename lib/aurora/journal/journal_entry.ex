defmodule Aurora.Journal.JournalEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "journal_entries" do
    field :content, :string
    field :mood, :integer
    field :energy, :integer
    field :entry_date, :date

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:content, :mood, :energy, :entry_date])
    |> validate_required([:entry_date])
    |> validate_number(:mood, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:energy, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> unique_constraint(:entry_date)
  end
end
