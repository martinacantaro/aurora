defmodule Aurora.Calendar do
  @moduledoc """
  The Calendar context for managing calendar events.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Calendar.Event

  # =============
  # CRUD Operations
  # =============

  @doc """
  Returns all events ordered by start time.
  """
  def list_events do
    Event
    |> order_by([e], asc: e.start_at)
    |> Repo.all()
  end

  @doc """
  Returns events for a specific date range.
  """
  def list_events_for_range(start_date, end_date) do
    start_dt = to_datetime(start_date, :start)
    end_dt = to_datetime(end_date, :end)

    Event
    |> where([e], e.start_at >= ^start_dt and e.start_at <= ^end_dt)
    |> or_where([e], e.end_at >= ^start_dt and e.end_at <= ^end_dt)
    |> or_where([e], e.start_at <= ^start_dt and e.end_at >= ^end_dt)
    |> order_by([e], asc: e.start_at)
    |> Repo.all()
  end

  @doc """
  Returns events for a specific month.
  """
  def list_events_for_month(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)
    list_events_for_range(start_date, end_date)
  end

  @doc """
  Returns events for a specific day.
  """
  def list_events_for_day(date) do
    list_events_for_range(date, date)
  end

  @doc """
  Returns upcoming events from now.
  """
  def list_upcoming_events(limit \\ 10) do
    now = DateTime.utc_now()

    Event
    |> where([e], e.start_at >= ^now or (e.end_at >= ^now and e.start_at <= ^now))
    |> order_by([e], asc: e.start_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns events for today.
  """
  def list_today_events do
    list_events_for_day(Date.utc_today())
  end

  @doc """
  Gets a single event.
  """
  def get_event!(id) do
    Event
    |> Repo.get!(id)
    |> Repo.preload([:task, :goal, :parent_event])
  end

  @doc """
  Gets a single event, returns nil if not found.
  """
  def get_event(id) do
    case Repo.get(Event, id) do
      nil -> nil
      event -> Repo.preload(event, [:task, :goal, :parent_event])
    end
  end

  @doc """
  Creates an event.
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an event.
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.
  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  # =============
  # Query Helpers
  # =============

  @doc """
  Returns a map of dates to event counts for a month (for calendar display).
  """
  def get_event_counts_for_month(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)
    events = list_events_for_range(start_date, end_date)

    Enum.reduce(events, %{}, fn event, acc ->
      date = DateTime.to_date(event.start_at)
      Map.update(acc, date, 1, &(&1 + 1))
    end)
  end

  @doc """
  Returns events grouped by date for a date range.
  """
  def get_events_grouped_by_date(start_date, end_date) do
    list_events_for_range(start_date, end_date)
    |> Enum.group_by(fn event -> DateTime.to_date(event.start_at) end)
  end

  @doc """
  Returns events for the current week.
  """
  def list_events_for_week(date \\ Date.utc_today()) do
    # Get Monday of the week
    day_of_week = Date.day_of_week(date)
    monday = Date.add(date, -(day_of_week - 1))
    sunday = Date.add(monday, 6)
    list_events_for_range(monday, sunday)
  end

  # =============
  # Recurrence Helpers
  # =============

  @doc """
  Expands a recurring event into individual instances for a date range.
  Returns a list of virtual event structs (not persisted).
  """
  def expand_recurring_event(%Event{is_recurring: false} = event, _start_date, _end_date) do
    [event]
  end

  def expand_recurring_event(%Event{is_recurring: true, recurrence_rule: rule} = event, start_date, end_date) do
    frequency = Map.get(rule, "frequency") || Map.get(rule, :frequency, "daily")
    interval = Map.get(rule, "interval") || Map.get(rule, :interval, 1)
    count = Map.get(rule, "count") || Map.get(rule, :count)
    until_date = parse_until_date(Map.get(rule, "until") || Map.get(rule, :until))

    event_date = DateTime.to_date(event.start_at)
    event_time = DateTime.to_time(event.start_at)
    duration = if event.end_at, do: DateTime.diff(event.end_at, event.start_at), else: 0

    generate_occurrences(event, event_date, event_time, duration, frequency, interval, count, until_date, start_date, end_date)
  end

  defp generate_occurrences(event, current_date, time, duration, frequency, interval, count, until_date, range_start, range_end, occurrences \\ [], occurrence_num \\ 0) do
    cond do
      # Stop if we've exceeded the count
      count && occurrence_num >= count ->
        occurrences

      # Stop if we've passed the until date
      until_date && Date.compare(current_date, until_date) == :gt ->
        occurrences

      # Stop if we've passed the range end
      Date.compare(current_date, range_end) == :gt ->
        occurrences

      true ->
        # Check if this occurrence falls within the range
        occurrences =
          if Date.compare(current_date, range_start) != :lt do
            start_at = DateTime.new!(current_date, time, "Etc/UTC")
            end_at = if duration > 0, do: DateTime.add(start_at, duration, :second), else: nil

            virtual_event = %{event | start_at: start_at, end_at: end_at, id: nil, parent_event_id: event.id}
            occurrences ++ [virtual_event]
          else
            occurrences
          end

        # Calculate next occurrence
        next_date = advance_date(current_date, frequency, interval)
        generate_occurrences(event, next_date, time, duration, frequency, interval, count, until_date, range_start, range_end, occurrences, occurrence_num + 1)
    end
  end

  defp advance_date(date, "daily", interval), do: Date.add(date, interval)
  defp advance_date(date, "weekly", interval), do: Date.add(date, interval * 7)
  defp advance_date(date, "monthly", interval) do
    {year, month, day} = Date.to_erl(date)
    new_month = month + interval
    new_year = year + div(new_month - 1, 12)
    new_month = rem(new_month - 1, 12) + 1
    # Handle day overflow for months with fewer days
    max_day = :calendar.last_day_of_the_month(new_year, new_month)
    Date.new!(new_year, new_month, min(day, max_day))
  end
  defp advance_date(date, "yearly", interval) do
    {year, month, day} = Date.to_erl(date)
    new_year = year + interval
    max_day = :calendar.last_day_of_the_month(new_year, month)
    Date.new!(new_year, month, min(day, max_day))
  end

  defp parse_until_date(nil), do: nil
  defp parse_until_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> d
      _ -> nil
    end
  end
  defp parse_until_date(%Date{} = date), do: date
  defp parse_until_date(_), do: nil

  # =============
  # Private Helpers
  # =============

  defp to_datetime(%Date{} = date, :start) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp to_datetime(%Date{} = date, :end) do
    DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
  end
end
