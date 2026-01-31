defmodule Aurora.Notes do
  @moduledoc """
  Handles saving voice note transcriptions to local files.
  Notes are stored in priv/notes/ and are gitignored for privacy.
  """

  @notes_dir "priv/notes"

  @doc """
  Saves a voice transcription to a dated file.
  Appends to the file if it already exists (for multiple notes in a day).
  """
  def save_transcription(content, opts \\ []) do
    ensure_notes_dir()

    date = Keyword.get(opts, :date, Date.utc_today())
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    filename = date_to_filename(date)
    filepath = Path.join(notes_dir(), filename)

    entry = format_entry(content, timestamp)

    # Append to file (creates if doesn't exist)
    case File.write(filepath, entry, [:append]) do
      :ok -> {:ok, filepath}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reads the transcription file for a given date.
  """
  def get_transcription(date \\ Date.utc_today()) do
    filename = date_to_filename(date)
    filepath = Path.join(notes_dir(), filename)

    case File.read(filepath) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all transcription files.
  """
  def list_transcriptions do
    ensure_notes_dir()

    notes_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.map(fn filename ->
      %{
        filename: filename,
        date: filename_to_date(filename),
        path: Path.join(notes_dir(), filename)
      }
    end)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  @doc """
  Gets the notes directory path.
  """
  def notes_dir do
    Application.app_dir(:aurora, @notes_dir)
  end

  # Private functions

  defp ensure_notes_dir do
    dir = notes_dir()
    unless File.exists?(dir) do
      File.mkdir_p!(dir)
    end
  end

  defp date_to_filename(date) do
    "#{Date.to_iso8601(date)}.md"
  end

  defp filename_to_date(filename) do
    filename
    |> String.replace(".md", "")
    |> Date.from_iso8601!()
  rescue
    _ -> nil
  end

  defp format_entry(content, timestamp) do
    time_str = Calendar.strftime(timestamp, "%H:%M")

    """

    ---
    ## #{time_str}

    #{content}

    """
  end
end
