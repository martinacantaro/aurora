defmodule AuroraWeb.CalendarLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Calendar, as: Cal
  alias Aurora.Calendar.Event

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, "Calendar")
     |> assign(:current_date, today)
     |> assign(:view_month, today)
     |> assign(:view_mode, :month)
     |> assign(:selected_event, nil)
     |> assign(:show_form, false)
     |> assign(:editing_event, nil)
     |> load_month_data()}
  end

  defp load_month_data(socket) do
    %{year: year, month: month} = socket.assigns.view_month
    events = Cal.list_events_for_month(year, month)
    event_counts = Cal.get_event_counts_for_month(year, month)

    socket
    |> assign(:events, events)
    |> assign(:event_counts, event_counts)
    |> assign(:calendar_weeks, build_calendar(year, month))
  end

  defp build_calendar(year, month) do
    first_day = Date.new!(year, month, 1)
    first_weekday = Date.day_of_week(first_day)
    start_date = Date.add(first_day, -(first_weekday - 1))

    Enum.chunk_every(
      Enum.map(0..41, fn offset -> Date.add(start_date, offset) end),
      7
    )
    |> Enum.take_while(fn week ->
      Enum.any?(week, fn date -> date.month == month end)
    end)
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    new_month = socket.assigns.view_month |> Date.beginning_of_month() |> Date.add(-1)
    {:noreply, socket |> assign(:view_month, new_month) |> load_month_data()}
  end

  def handle_event("next_month", _params, socket) do
    new_month = socket.assigns.view_month |> Date.end_of_month() |> Date.add(1)
    {:noreply, socket |> assign(:view_month, new_month) |> load_month_data()}
  end

  def handle_event("select_date", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)
    events_for_day = Cal.list_events_for_day(date)

    {:noreply,
     socket
     |> assign(:current_date, date)
     |> assign(:day_events, events_for_day)}
  end

  def handle_event("today", _params, socket) do
    today = Date.utc_today()

    {:noreply,
     socket
     |> assign(:current_date, today)
     |> assign(:view_month, today)
     |> load_month_data()}
  end

  def handle_event("show_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_event, nil)}
  end

  def handle_event("edit_event", %{"id" => id}, socket) do
    event = Cal.get_event!(id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_event, event)}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_event, nil)}
  end

  def handle_event("save_event", params, socket) do
    event_params = build_event_params(params, socket.assigns.current_date)

    result =
      if socket.assigns.editing_event do
        Cal.update_event(socket.assigns.editing_event, event_params)
      else
        Cal.create_event(event_params)
      end

    case result do
      {:ok, _event} ->
        action = if socket.assigns.editing_event, do: "updated", else: "created"

        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:editing_event, nil)
         |> load_month_data()
         |> put_flash(:info, "Event #{action} successfully!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save event")}
    end
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    event = Cal.get_event!(id)

    case Cal.delete_event(event) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:selected_event, nil)
         |> load_month_data()
         |> put_flash(:info, "Event deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete event")}
    end
  end

  def handle_event("view_event", %{"id" => id}, socket) do
    event = Cal.get_event!(id)
    {:noreply, assign(socket, :selected_event, event)}
  end

  def handle_event("close_event_detail", _params, socket) do
    {:noreply, assign(socket, :selected_event, nil)}
  end

  defp build_event_params(params, current_date) do
    start_time = parse_time(params["start_time"]) || ~T[09:00:00]
    end_time = parse_time(params["end_time"])

    start_date = parse_date(params["start_date"]) || current_date
    start_at = DateTime.new!(start_date, start_time, "Etc/UTC")

    end_at =
      if end_time do
        end_date = parse_date(params["end_date"]) || start_date
        DateTime.new!(end_date, end_time, "Etc/UTC")
      else
        nil
      end

    %{
      title: params["title"],
      description: params["description"],
      start_at: start_at,
      end_at: end_at,
      all_day: params["all_day"] == "true",
      location: params["location"],
      color: params["color"] || "#3b82f6",
      is_recurring: params["is_recurring"] == "true",
      recurrence_rule: build_recurrence_rule(params)
    }
  end

  defp build_recurrence_rule(%{"is_recurring" => "true"} = params) do
    %{
      "frequency" => params["frequency"] || "weekly",
      "interval" => parse_int(params["interval"]) || 1,
      "until" => params["until"]
    }
  end

  defp build_recurrence_rule(_), do: nil

  defp parse_time(nil), do: nil
  defp parse_time(""), do: nil

  defp parse_time(time_str) do
    case Time.from_iso8601(time_str <> ":00") do
      {:ok, time} -> time
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
  defp parse_int(val) when is_integer(val), do: val

  defp format_month(date) do
    Calendar.strftime(date, "%B %Y")
  end

  defp format_date(date) do
    Calendar.strftime(date, "%A, %B %d, %Y")
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_event_time(%Event{all_day: true}), do: "All day"

  defp format_event_time(%Event{start_at: start_at, end_at: nil}) do
    format_time(start_at)
  end

  defp format_event_time(%Event{start_at: start_at, end_at: end_at}) do
    "#{format_time(start_at)} - #{format_time(end_at)}"
  end

  defp day_class(date, current_date, view_month, event_counts, today) do
    classes = ["btn btn-sm w-10 h-10 btn-imperial relative"]

    classes =
      if date.month != view_month.month do
        ["opacity-30" | classes]
      else
        classes
      end

    classes =
      if Date.compare(date, current_date) == :eq do
        ["!btn-imperial-primary" | classes]
      else
        classes
      end

    classes =
      if Date.compare(date, today) == :eq and Date.compare(date, current_date) != :eq do
        ["ring-2 ring-primary" | classes]
      else
        classes
      end

    classes =
      if Map.get(event_counts, date, 0) > 0 and Date.compare(date, current_date) != :eq do
        ["!bg-info/20 !border-info/50" | classes]
      else
        classes
      end

    Enum.join(classes, " ")
  end

  defp events_for_date(events, date) do
    Enum.filter(events, fn event ->
      event_date = DateTime.to_date(event.start_at)
      Date.compare(event_date, date) == :eq
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300">
      <!-- Header -->
      <header class="border-b border-primary/30 bg-base-200">
        <div class="container mx-auto px-4 py-4">
          <div class="flex justify-between items-center">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm text-primary">
                <.icon name="hero-arrow-left" class="w-4 h-4" />
              </.link>
              <div class="flex items-center gap-3">
                <.icon name="hero-calendar-days" class="w-6 h-6 text-primary" />
                <h1 class="text-2xl tracking-wider text-primary">Calendar</h1>
              </div>
            </div>
            <div class="flex gap-2">
              <button phx-click="today" class="btn btn-imperial btn-sm">
                Today
              </button>
              <button phx-click="show_form" class="btn btn-imperial-primary btn-sm">
                <.icon name="hero-plus" class="w-4 h-4" />
                New Event
              </button>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-4 py-6 pb-24">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Calendar -->
          <div class="lg:col-span-2 card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
            <!-- Month Navigation -->
            <div class="flex justify-between items-center mb-4">
              <button phx-click="prev_month" class="btn btn-imperial btn-sm">
                <.icon name="hero-chevron-left" class="w-5 h-5" />
              </button>
              <h2 class="text-xl text-primary font-semibold"><%= format_month(@view_month) %></h2>
              <button phx-click="next_month" class="btn btn-imperial btn-sm">
                <.icon name="hero-chevron-right" class="w-5 h-5" />
              </button>
            </div>

            <!-- Weekday Headers -->
            <div class="grid grid-cols-7 gap-1 mb-2">
              <%= for day <- ~w(Mon Tue Wed Thu Fri Sat Sun) do %>
                <div class="text-center text-xs text-primary/60 font-medium uppercase tracking-wider py-2">
                  <%= day %>
                </div>
              <% end %>
            </div>

            <!-- Calendar Grid -->
            <div class="space-y-1">
              <%= for week <- @calendar_weeks do %>
                <div class="grid grid-cols-7 gap-1">
                  <%= for date <- week do %>
                    <button
                      phx-click="select_date"
                      phx-value-date={Date.to_iso8601(date)}
                      class={day_class(date, @current_date, @view_month, @event_counts, Date.utc_today())}
                    >
                      <%= date.day %>
                      <%= if Map.get(@event_counts, date, 0) > 0 do %>
                        <span class="absolute -bottom-0.5 left-1/2 -translate-x-1/2 w-1.5 h-1.5 rounded-full bg-info"></span>
                      <% end %>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Legend -->
            <div class="flex gap-4 mt-4 text-xs text-base-content/60">
              <div class="flex items-center gap-1">
                <span class="w-3 h-3 rounded bg-info/20 border border-info/50"></span>
                Has events
              </div>
              <div class="flex items-center gap-1">
                <span class="w-3 h-3 rounded ring-2 ring-primary"></span>
                Today
              </div>
            </div>
          </div>

          <!-- Day Detail -->
          <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
            <h2 class="panel-header"><%= format_date(@current_date) %></h2>

            <div class="space-y-3">
              <%= if events_for_date(@events, @current_date) == [] do %>
                <p class="text-base-content/50 italic text-center py-8">No events scheduled</p>
              <% else %>
                <%= for event <- events_for_date(@events, @current_date) do %>
                  <div
                    class="p-3 rounded border-l-4 bg-base-200 hover:bg-base-300 cursor-pointer transition-colors"
                    style={"border-left-color: #{event.color}"}
                    phx-click="view_event"
                    phx-value-id={event.id}
                  >
                    <div class="flex justify-between items-start">
                      <div>
                        <h3 class="font-semibold text-base-content"><%= event.title %></h3>
                        <p class="text-sm text-base-content/60"><%= format_event_time(event) %></p>
                        <%= if event.location do %>
                          <p class="text-xs text-base-content/50 mt-1">
                            <.icon name="hero-map-pin" class="w-3 h-3 inline" />
                            <%= event.location %>
                          </p>
                        <% end %>
                      </div>
                      <div class="flex gap-1">
                        <button
                          phx-click="edit_event"
                          phx-value-id={event.id}
                          class="btn btn-ghost btn-xs"
                        >
                          <.icon name="hero-pencil" class="w-3 h-3" />
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>

            <button
              phx-click="show_form"
              class="btn btn-imperial w-full mt-4"
            >
              <.icon name="hero-plus" class="w-4 h-4" />
              Add Event
            </button>
          </div>
        </div>

        <!-- Upcoming Events -->
        <div class="mt-8">
          <h2 class="panel-header">Upcoming Events</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for event <- Enum.take(@events, 6) do %>
              <div
                class="card card-ornate p-4 cursor-pointer hover:border-primary/50 transition-colors"
                phx-click="view_event"
                phx-value-id={event.id}
              >
                <div class="flex gap-3">
                  <div
                    class="w-1 rounded-full"
                    style={"background-color: #{event.color}"}
                  ></div>
                  <div class="flex-1">
                    <h3 class="font-semibold text-base-content"><%= event.title %></h3>
                    <p class="text-sm text-primary">
                      <%= Calendar.strftime(event.start_at, "%b %d") %>
                      <span class="text-base-content/60"><%= format_event_time(event) %></span>
                    </p>
                    <%= if event.location do %>
                      <p class="text-xs text-base-content/50 mt-1">
                        <.icon name="hero-map-pin" class="w-3 h-3 inline" />
                        <%= event.location %>
                      </p>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </main>

      <!-- Event Form Modal -->
      <%= if @show_form do %>
        <div class="modal modal-open">
          <div class="modal-box card-ornate border border-primary/50 max-w-lg">
            <div class="flex justify-between items-center mb-4">
              <h3 class="panel-header mb-0 pb-0 border-0">
                <%= if @editing_event, do: "Edit Event", else: "New Event" %>
              </h3>
              <button phx-click="close_form" class="btn btn-ghost btn-sm">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <form phx-submit="save_event" class="space-y-4">
              <!-- Title -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Title</span></label>
                <input
                  type="text"
                  name="title"
                  value={if @editing_event, do: @editing_event.title, else: ""}
                  class="input input-imperial"
                  placeholder="Event title"
                  required
                />
              </div>

              <!-- Date & Time -->
              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="stat-block-label">Start Date</span></label>
                  <input
                    type="date"
                    name="start_date"
                    value={if @editing_event, do: DateTime.to_date(@editing_event.start_at) |> Date.to_iso8601(), else: Date.to_iso8601(@current_date)}
                    class="input input-imperial"
                    required
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="stat-block-label">Start Time</span></label>
                  <input
                    type="time"
                    name="start_time"
                    value={if @editing_event && !@editing_event.all_day, do: format_time(@editing_event.start_at), else: "09:00"}
                    class="input input-imperial"
                  />
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="stat-block-label">End Date</span></label>
                  <input
                    type="date"
                    name="end_date"
                    value={if @editing_event && @editing_event.end_at, do: DateTime.to_date(@editing_event.end_at) |> Date.to_iso8601(), else: ""}
                    class="input input-imperial"
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="stat-block-label">End Time</span></label>
                  <input
                    type="time"
                    name="end_time"
                    value={if @editing_event && @editing_event.end_at, do: format_time(@editing_event.end_at), else: ""}
                    class="input input-imperial"
                  />
                </div>
              </div>

              <!-- All Day Toggle -->
              <div class="form-control">
                <label class="label cursor-pointer justify-start gap-3">
                  <input
                    type="checkbox"
                    name="all_day"
                    value="true"
                    checked={@editing_event && @editing_event.all_day}
                    class="checkbox checkbox-primary"
                  />
                  <span class="stat-block-label">All day event</span>
                </label>
              </div>

              <!-- Location -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Location</span></label>
                <input
                  type="text"
                  name="location"
                  value={if @editing_event, do: @editing_event.location, else: ""}
                  class="input input-imperial"
                  placeholder="Optional location"
                />
              </div>

              <!-- Color -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Color</span></label>
                <div class="flex gap-2">
                  <%= for {_name, hex} <- Event.colors() do %>
                    <label class="cursor-pointer">
                      <input
                        type="radio"
                        name="color"
                        value={hex}
                        checked={(@editing_event && @editing_event.color == hex) || (!@editing_event && hex == "#3b82f6")}
                        class="hidden peer"
                      />
                      <div
                        class="w-8 h-8 rounded-full border-2 border-transparent peer-checked:border-white peer-checked:ring-2 peer-checked:ring-primary"
                        style={"background-color: #{hex}"}
                      ></div>
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Description -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Description</span></label>
                <textarea
                  name="description"
                  class="textarea input-imperial h-20"
                  placeholder="Optional description"
                ><%= if @editing_event, do: @editing_event.description, else: "" %></textarea>
              </div>

              <!-- Recurrence -->
              <div class="form-control">
                <label class="label cursor-pointer justify-start gap-3">
                  <input
                    type="checkbox"
                    name="is_recurring"
                    value="true"
                    checked={@editing_event && @editing_event.is_recurring}
                    class="checkbox checkbox-primary"
                    phx-change="toggle_recurring"
                  />
                  <span class="stat-block-label">Repeat</span>
                </label>
              </div>

              <!-- Actions -->
              <div class="flex justify-between pt-4">
                <%= if @editing_event do %>
                  <button
                    type="button"
                    phx-click="delete_event"
                    phx-value-id={@editing_event.id}
                    data-confirm="Delete this event?"
                    class="btn btn-imperial-danger"
                  >
                    Delete
                  </button>
                <% else %>
                  <div></div>
                <% end %>
                <div class="flex gap-2">
                  <button type="button" phx-click="close_form" class="btn btn-imperial">
                    Cancel
                  </button>
                  <button type="submit" class="btn btn-imperial-primary">
                    <%= if @editing_event, do: "Update", else: "Create" %>
                  </button>
                </div>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="close_form"></div>
        </div>
      <% end %>

      <!-- Event Detail Modal -->
      <%= if @selected_event do %>
        <div class="modal modal-open">
          <div class="modal-box card-ornate border border-primary/50">
            <div class="flex justify-between items-start mb-4">
              <div>
                <h3 class="text-xl font-semibold text-primary"><%= @selected_event.title %></h3>
                <p class="text-base-content/60">
                  <%= Calendar.strftime(@selected_event.start_at, "%A, %B %d, %Y") %>
                </p>
              </div>
              <button phx-click="close_event_detail" class="btn btn-ghost btn-sm">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <div class="space-y-3">
              <div class="flex items-center gap-3">
                <.icon name="hero-clock" class="w-5 h-5 text-primary" />
                <span><%= format_event_time(@selected_event) %></span>
              </div>

              <%= if @selected_event.location do %>
                <div class="flex items-center gap-3">
                  <.icon name="hero-map-pin" class="w-5 h-5 text-primary" />
                  <span><%= @selected_event.location %></span>
                </div>
              <% end %>

              <%= if @selected_event.description do %>
                <div class="pt-3 border-t border-base-content/10">
                  <p class="text-base-content/80 whitespace-pre-wrap"><%= @selected_event.description %></p>
                </div>
              <% end %>

              <%= if @selected_event.is_recurring do %>
                <div class="flex items-center gap-3 text-sm text-base-content/60">
                  <.icon name="hero-arrow-path" class="w-4 h-4" />
                  <span>Recurring event</span>
                </div>
              <% end %>
            </div>

            <div class="flex justify-end gap-2 mt-6">
              <button
                phx-click="edit_event"
                phx-value-id={@selected_event.id}
                class="btn btn-imperial"
              >
                <.icon name="hero-pencil" class="w-4 h-4" />
                Edit
              </button>
              <button phx-click="close_event_detail" class="btn btn-imperial-primary">
                Close
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="close_event_detail"></div>
        </div>
      <% end %>

      <!-- HUD Navigation -->
      <nav class="fixed bottom-0 left-0 right-0 hud-nav">
        <.link navigate={~p"/boards"} class="hud-nav-item">
          <.icon name="hero-view-columns" class="hud-nav-icon" />
          <span class="hud-nav-label">Operations</span>
        </.link>
        <.link navigate={~p"/goals"} class="hud-nav-item">
          <.icon name="hero-flag" class="hud-nav-icon" />
          <span class="hud-nav-label">Quests</span>
        </.link>
        <.link navigate={~p"/habits"} class="hud-nav-item">
          <.icon name="hero-bolt" class="hud-nav-icon" />
          <span class="hud-nav-label">Rituals</span>
        </.link>
        <.link navigate={~p"/journal"} class="hud-nav-item">
          <.icon name="hero-book-open" class="hud-nav-icon" />
          <span class="hud-nav-label">Chronicle</span>
        </.link>
        <.link navigate={~p"/calendar"} class="hud-nav-item hud-nav-item-active">
          <.icon name="hero-calendar-days" class="hud-nav-icon" />
          <span class="hud-nav-label">Calendar</span>
        </.link>
        <.link navigate={~p"/finance"} class="hud-nav-item">
          <.icon name="hero-banknotes" class="hud-nav-icon" />
          <span class="hud-nav-label">Treasury</span>
        </.link>
      </nav>
    </div>
    """
  end
end
