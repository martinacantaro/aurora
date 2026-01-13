defmodule Aurora.Journal do
  @moduledoc """
  The Journal context for managing daily journal entries.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Journal.JournalEntry

  @doc """
  Lists all journal entries, most recent first.
  """
  def list_entries do
    JournalEntry
    |> order_by(desc: :entry_date)
    |> Repo.all()
  end

  @doc """
  Lists journal entries for a specific month.
  """
  def list_entries_for_month(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    JournalEntry
    |> where([e], e.entry_date >= ^start_date and e.entry_date <= ^end_date)
    |> order_by(desc: :entry_date)
    |> Repo.all()
  end

  @doc """
  Gets entries for a date range.
  """
  def list_entries_for_range(start_date, end_date) do
    JournalEntry
    |> where([e], e.entry_date >= ^start_date and e.entry_date <= ^end_date)
    |> order_by(desc: :entry_date)
    |> Repo.all()
  end

  @doc """
  Gets a single journal entry by ID.
  """
  def get_entry!(id) do
    Repo.get!(JournalEntry, id)
  end

  @doc """
  Gets a journal entry for a specific date.
  """
  def get_entry_for_date(date) do
    Repo.get_by(JournalEntry, entry_date: date)
  end

  @doc """
  Gets or creates an entry for a specific date.
  """
  def get_or_create_entry_for_date(date) do
    case get_entry_for_date(date) do
      nil -> create_entry(%{entry_date: date})
      entry -> {:ok, entry}
    end
  end

  @doc """
  Creates a journal entry.
  """
  def create_entry(attrs \\ %{}) do
    %JournalEntry{}
    |> JournalEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a journal entry.
  """
  def update_entry(%JournalEntry{} = entry, attrs) do
    entry
    |> JournalEntry.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a journal entry.
  """
  def delete_entry(%JournalEntry{} = entry) do
    Repo.delete(entry)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking entry changes.
  """
  def change_entry(%JournalEntry{} = entry, attrs \\ %{}) do
    JournalEntry.changeset(entry, attrs)
  end

  @doc """
  Gets dates that have journal entries for a given month.
  Returns a MapSet of dates.
  """
  def get_entry_dates_for_month(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    JournalEntry
    |> where([e], e.entry_date >= ^start_date and e.entry_date <= ^end_date)
    |> select([e], e.entry_date)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns recent entries (last N days).
  """
  def recent_entries(days \\ 7) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -days)

    list_entries_for_range(start_date, end_date)
  end

  @doc """
  Gets mood/energy averages for a date range.
  """
  def get_averages_for_range(start_date, end_date) do
    query =
      from e in JournalEntry,
        where: e.entry_date >= ^start_date and e.entry_date <= ^end_date,
        where: not is_nil(e.mood) or not is_nil(e.energy),
        select: %{
          avg_mood: avg(e.mood),
          avg_energy: avg(e.energy),
          count: count(e.id)
        }

    Repo.one(query) || %{avg_mood: nil, avg_energy: nil, count: 0}
  end

  @doc """
  Returns mood label for a value.
  """
  def mood_label(1), do: "Very Low"
  def mood_label(2), do: "Low"
  def mood_label(3), do: "Neutral"
  def mood_label(4), do: "Good"
  def mood_label(5), do: "Great"
  def mood_label(_), do: "Not set"

  @doc """
  Returns energy label for a value.
  """
  def energy_label(1), do: "Exhausted"
  def energy_label(2), do: "Tired"
  def energy_label(3), do: "Normal"
  def energy_label(4), do: "Energized"
  def energy_label(5), do: "Peak"
  def energy_label(_), do: "Not set"

  @doc """
  Returns mood emoji for a value.
  """
  def mood_emoji(1), do: "😢"
  def mood_emoji(2), do: "😕"
  def mood_emoji(3), do: "😐"
  def mood_emoji(4), do: "🙂"
  def mood_emoji(5), do: "😄"
  def mood_emoji(_), do: "❓"

  @doc """
  Returns energy emoji for a value.
  """
  def energy_emoji(1), do: "🪫"
  def energy_emoji(2), do: "😴"
  def energy_emoji(3), do: "⚡"
  def energy_emoji(4), do: "💪"
  def energy_emoji(5), do: "🔥"
  def energy_emoji(_), do: "❓"
end
