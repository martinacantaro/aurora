defmodule Aurora.Assistant.Tools.CalendarTools do
  @moduledoc """
  Tool definitions and executors for calendar events.
  """

  alias Aurora.Calendar, as: Cal

  def definitions do
    [
      %{
        name: "list_calendar_events",
        description: "List calendar events for a date range or upcoming events",
        input_schema: %{
          type: "object",
          properties: %{
            start_date: %{type: "string", format: "date", description: "Start date (YYYY-MM-DD)"},
            end_date: %{type: "string", format: "date", description: "End date (YYYY-MM-DD)"},
            limit: %{type: "integer", description: "Number of upcoming events to return"}
          },
          required: []
        }
      },
      %{
        name: "list_upcoming_events",
        description: "List upcoming calendar events",
        input_schema: %{
          type: "object",
          properties: %{
            limit: %{type: "integer", description: "Number of events to return", default: 10}
          },
          required: []
        }
      },
      %{
        name: "get_calendar_event",
        description: "Get details of a specific calendar event",
        input_schema: %{
          type: "object",
          properties: %{
            event_id: %{type: "integer", description: "The event ID"}
          },
          required: ["event_id"]
        }
      },
      %{
        name: "create_calendar_event",
        description: "Create a new calendar event",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{type: "string", description: "Event title"},
            description: %{type: "string", description: "Event description"},
            start_date: %{type: "string", format: "date", description: "Start date (YYYY-MM-DD)"},
            start_time: %{type: "string", description: "Start time (HH:MM, 24-hour format)"},
            end_date: %{type: "string", format: "date", description: "End date (optional)"},
            end_time: %{type: "string", description: "End time (optional, HH:MM)"},
            all_day: %{type: "boolean", description: "Is this an all-day event?"},
            location: %{type: "string", description: "Event location"},
            color: %{type: "string", description: "Event color (hex code like #3b82f6)"}
          },
          required: ["title", "start_date"]
        }
      },
      %{
        name: "update_calendar_event",
        description: "Update an existing calendar event",
        input_schema: %{
          type: "object",
          properties: %{
            event_id: %{type: "integer", description: "The event to update"},
            title: %{type: "string", description: "New title"},
            description: %{type: "string", description: "New description"},
            start_date: %{type: "string", format: "date", description: "New start date"},
            start_time: %{type: "string", description: "New start time"},
            location: %{type: "string", description: "New location"}
          },
          required: ["event_id"]
        }
      },
      %{
        name: "delete_calendar_event",
        description: "Delete a calendar event. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            event_id: %{type: "integer", description: "The event to delete"}
          },
          required: ["event_id"]
        }
      }
    ]
  end

  def execute("list_calendar_events", args) do
    events = cond do
      args["start_date"] && args["end_date"] ->
        start_date = parse_date(args["start_date"]) || Date.utc_today()
        end_date = parse_date(args["end_date"]) || Date.add(start_date, 30)
        Cal.list_events_for_range(start_date, end_date)
      args["limit"] ->
        Cal.list_upcoming_events(args["limit"])
      true ->
        Cal.list_upcoming_events(10)
    end
    {:ok, format_events(events)}
  end

  def execute("list_upcoming_events", args) do
    limit = args["limit"] || 10
    events = Cal.list_upcoming_events(limit)
    {:ok, format_events(events)}
  end

  def execute("get_calendar_event", %{"event_id" => id}) do
    try do
      event = Cal.get_event!(id)
      {:ok, format_event_detail(event)}
    rescue
      Ecto.NoResultsError -> {:error, "Event not found with ID #{id}"}
    end
  end

  def execute("create_calendar_event", args) do
    start_date = parse_date(args["start_date"]) || Date.utc_today()
    start_time = parse_time(args["start_time"]) || ~T[09:00:00]
    start_at = DateTime.new!(start_date, start_time, "Etc/UTC")

    end_at = if args["end_time"] do
      end_date = parse_date(args["end_date"]) || start_date
      end_time = parse_time(args["end_time"])
      if end_time, do: DateTime.new!(end_date, end_time, "Etc/UTC"), else: nil
    else
      nil
    end

    attrs = %{
      title: args["title"],
      description: args["description"],
      start_at: start_at,
      end_at: end_at,
      all_day: args["all_day"] || false,
      location: args["location"],
      color: args["color"] || "#3b82f6"
    }

    case Cal.create_event(attrs) do
      {:ok, event} ->
        {:ok, %{
          id: event.id,
          title: event.title,
          message: "Event '#{event.title}' created for #{format_date(start_date)}"
        }}
      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("update_calendar_event", %{"event_id" => id} = args) do
    try do
      event = Cal.get_event!(id)

      # Build attrs, handling date/time specially
      attrs = %{}

      attrs = if args["title"], do: Map.put(attrs, :title, args["title"]), else: attrs
      attrs = if args["description"], do: Map.put(attrs, :description, args["description"]), else: attrs
      attrs = if args["location"], do: Map.put(attrs, :location, args["location"]), else: attrs

      attrs = if args["start_date"] do
        start_date = parse_date(args["start_date"]) || Date.utc_today()
        start_time = if args["start_time"] do
          parse_time(args["start_time"]) || ~T[09:00:00]
        else
          DateTime.to_time(event.start_at)
        end
        Map.put(attrs, :start_at, DateTime.new!(start_date, start_time, "Etc/UTC"))
      else
        attrs
      end

      case Cal.update_event(event, attrs) do
        {:ok, event} ->
          {:ok, %{id: event.id, message: "Event updated"}}
        {:error, changeset} ->
          {:error, format_errors(changeset)}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Event not found with ID #{id}"}
    end
  end

  def execute("delete_calendar_event", %{"event_id" => id}) do
    try do
      event = Cal.get_event!(id)
      case Cal.delete_event(event) do
        {:ok, _} ->
          {:ok, %{message: "Event '#{event.title}' deleted"}}
        {:error, _} ->
          {:error, "Failed to delete event"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Event not found with ID #{id}"}
    end
  end

  defp format_events(events) do
    %{
      count: length(events),
      events: Enum.map(events, fn e ->
        %{
          id: e.id,
          title: e.title,
          date: DateTime.to_date(e.start_at),
          time: format_time(e.start_at),
          all_day: e.all_day,
          location: e.location
        }
      end)
    }
  end

  defp format_event_detail(event) do
    %{
      id: event.id,
      title: event.title,
      description: event.description,
      start_at: event.start_at,
      end_at: event.end_at,
      all_day: event.all_day,
      location: event.location,
      color: event.color,
      is_recurring: event.is_recurring
    }
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_time(nil), do: nil
  defp parse_time(""), do: nil
  defp parse_time(time_str) do
    case Time.from_iso8601(time_str <> ":00") do
      {:ok, time} -> time
      _ -> nil
    end
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
