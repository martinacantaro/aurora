defmodule Aurora.Assistant.Tools.JournalTools do
  @moduledoc """
  Tool definitions and executors for journal entries.
  """

  alias Aurora.Journal

  def definitions do
    [
      %{
        name: "list_journal_entries",
        description: "List recent journal entries",
        input_schema: %{
          type: "object",
          properties: %{
            days: %{type: "integer", description: "Number of days to look back", default: 7}
          },
          required: []
        }
      },
      %{
        name: "get_journal_entry",
        description: "Get a journal entry for a specific date",
        input_schema: %{
          type: "object",
          properties: %{
            date: %{type: "string", format: "date", description: "Date in YYYY-MM-DD format"}
          },
          required: ["date"]
        }
      },
      %{
        name: "create_journal_entry",
        description: "Create or update a journal entry for a date",
        input_schema: %{
          type: "object",
          properties: %{
            date: %{type: "string", format: "date", description: "Date for the entry (default: today)"},
            content: %{type: "string", description: "Journal entry content"},
            mood: %{type: "integer", description: "Mood rating 1-5", minimum: 1, maximum: 5},
            energy: %{type: "integer", description: "Energy level 1-5", minimum: 1, maximum: 5}
          },
          required: []
        }
      },
      %{
        name: "update_journal_entry",
        description: "Update an existing journal entry",
        input_schema: %{
          type: "object",
          properties: %{
            entry_id: %{type: "integer", description: "The entry to update"},
            content: %{type: "string", description: "New content"},
            mood: %{type: "integer", description: "New mood 1-5"},
            energy: %{type: "integer", description: "New energy 1-5"}
          },
          required: ["entry_id"]
        }
      },
      %{
        name: "delete_journal_entry",
        description: "Delete a journal entry. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            entry_id: %{type: "integer", description: "The entry to delete"}
          },
          required: ["entry_id"]
        }
      }
    ]
  end

  def execute("list_journal_entries", args) do
    days = args["days"] || 7
    entries = Journal.recent_entries(days)
    {:ok, format_entries(entries)}
  end

  def execute("get_journal_entry", %{"date" => date_str}) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        case Journal.get_entry_for_date(date) do
          nil -> {:ok, %{message: "No journal entry for #{date_str}"}}
          entry -> {:ok, format_entry_detail(entry)}
        end
      _ ->
        {:error, "Invalid date format. Use YYYY-MM-DD"}
    end
  end

  def execute("create_journal_entry", args) do
    date = case args["date"] do
      nil -> Date.utc_today()
      date_str ->
        case Date.from_iso8601(date_str) do
          {:ok, d} -> d
          _ -> Date.utc_today()
        end
    end

    attrs = %{
      entry_date: date,
      content: args["content"],
      mood: args["mood"],
      energy: args["energy"]
    }

    case Journal.get_or_create_entry_for_date(date) do
      {:ok, entry} ->
        case Journal.update_entry(entry, attrs) do
          {:ok, entry} ->
            {:ok, %{id: entry.id, date: entry.entry_date, message: "Journal entry saved"}}
          {:error, changeset} ->
            {:error, format_errors(changeset)}
        end
      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("update_journal_entry", %{"entry_id" => id} = args) do
    try do
      entry = Journal.get_entry!(id)
      attrs = args
        |> Map.drop(["entry_id"])
        |> Enum.reduce(%{}, fn {k, v}, acc ->
          Map.put(acc, String.to_existing_atom(k), v)
        end)

      case Journal.update_entry(entry, attrs) do
        {:ok, entry} ->
          {:ok, %{id: entry.id, message: "Entry updated"}}
        {:error, changeset} ->
          {:error, format_errors(changeset)}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Entry not found with ID #{id}"}
    end
  end

  def execute("delete_journal_entry", %{"entry_id" => id}) do
    try do
      entry = Journal.get_entry!(id)
      case Journal.delete_entry(entry) do
        {:ok, _} ->
          {:ok, %{message: "Journal entry for #{entry.entry_date} deleted"}}
        {:error, _} ->
          {:error, "Failed to delete entry"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Entry not found with ID #{id}"}
    end
  end

  defp format_entries(entries) do
    %{
      count: length(entries),
      entries: Enum.map(entries, fn e ->
        %{
          id: e.id,
          date: e.entry_date,
          mood: e.mood,
          mood_label: if(e.mood, do: Journal.mood_label(e.mood)),
          energy: e.energy,
          energy_label: if(e.energy, do: Journal.energy_label(e.energy)),
          has_content: e.content != nil && e.content != ""
        }
      end)
    }
  end

  defp format_entry_detail(entry) do
    %{
      id: entry.id,
      date: entry.entry_date,
      content: entry.content,
      mood: entry.mood,
      mood_label: if(entry.mood, do: Journal.mood_label(entry.mood)),
      energy: entry.energy,
      energy_label: if(entry.energy, do: Journal.energy_label(entry.energy))
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
