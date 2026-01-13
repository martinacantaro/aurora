defmodule AuroraWeb.JournalLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Journal

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    entry = Journal.get_entry_for_date(today)

    {:ok,
     socket
     |> assign(:page_title, "Chronicle")
     |> assign(:current_date, today)
     |> assign(:view_month, today)
     |> assign(:selected_entry, entry)
     |> assign(:editing, entry == nil)
     |> load_month_data()}
  end

  defp load_month_data(socket) do
    %{year: year, month: month} = socket.assigns.view_month
    entries = Journal.list_entries_for_month(year, month)
    entry_dates = Journal.get_entry_dates_for_month(year, month)

    socket
    |> assign(:entries, entries)
    |> assign(:entry_dates, entry_dates)
    |> assign(:calendar_weeks, build_calendar(year, month))
  end

  defp build_calendar(year, month) do
    first_day = Date.new!(year, month, 1)
    _last_day = Date.end_of_month(first_day)

    # Get the weekday of the first day (1 = Monday, 7 = Sunday)
    first_weekday = Date.day_of_week(first_day)

    # Pad the beginning with days from previous month
    start_date = Date.add(first_day, -(first_weekday - 1))

    # Build 6 weeks (42 days) to cover all possible month layouts
    Enum.chunk_every(
      Enum.map(0..41, fn offset -> Date.add(start_date, offset) end),
      7
    )
    |> Enum.take_while(fn week ->
      # Keep weeks that contain days from the current month
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
    entry = Journal.get_entry_for_date(date)

    {:noreply,
     socket
     |> assign(:current_date, date)
     |> assign(:selected_entry, entry)
     |> assign(:editing, entry == nil)}
  end

  def handle_event("edit_entry", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("save_entry", params, socket) do
    date = socket.assigns.current_date
    entry = socket.assigns.selected_entry

    entry_params = %{
      content: params["content"],
      mood: parse_int(params["mood"]),
      energy: parse_int(params["energy"]),
      entry_date: date
    }

    result =
      if entry do
        Journal.update_entry(entry, entry_params)
      else
        Journal.create_entry(entry_params)
      end

    case result do
      {:ok, saved_entry} ->
        {:noreply,
         socket
         |> assign(:selected_entry, saved_entry)
         |> assign(:editing, false)
         |> load_month_data()
         |> put_flash(:info, "Entry saved!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save entry")}
    end
  end

  def handle_event("delete_entry", _params, socket) do
    entry = socket.assigns.selected_entry

    case Journal.delete_entry(entry) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:selected_entry, nil)
         |> assign(:editing, false)
         |> load_month_data()
         |> put_flash(:info, "Entry deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete entry")}
    end
  end

  def handle_event("today", _params, socket) do
    today = Date.utc_today()
    entry = Journal.get_entry_for_date(today)

    {:noreply,
     socket
     |> assign(:current_date, today)
     |> assign(:view_month, today)
     |> assign(:selected_entry, entry)
     |> assign(:editing, entry == nil)
     |> load_month_data()}
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

  defp day_class(date, current_date, view_month, entry_dates, today) do
    classes = ["btn btn-sm w-10 h-10 btn-imperial"]

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
      if MapSet.member?(entry_dates, date) and Date.compare(date, current_date) != :eq do
        ["!bg-success/20 !border-success/50" | classes]
      else
        classes
      end

    Enum.join(classes, " ")
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
                <.icon name="hero-book-open" class="w-6 h-6 text-primary" />
                <h1 class="text-2xl tracking-wider text-primary">Chronicle</h1>
              </div>
            </div>
            <button phx-click="today" class="btn btn-imperial-primary btn-sm">
              Today
            </button>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-4 py-6 pb-24">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Calendar -->
          <div class="card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
            <!-- Month Navigation -->
            <div class="flex justify-between items-center mb-4">
              <button phx-click="prev_month" class="btn btn-imperial btn-sm">
                <.icon name="hero-chevron-left" class="w-5 h-5" />
              </button>
              <h2 class="text-lg text-primary"><%= format_month(@view_month) %></h2>
              <button phx-click="next_month" class="btn btn-imperial btn-sm">
                <.icon name="hero-chevron-right" class="w-5 h-5" />
              </button>
            </div>

            <!-- Weekday Headers -->
            <div class="grid grid-cols-7 gap-1 mb-2">
              <%= for day <- ~w(Mon Tue Wed Thu Fri Sat Sun) do %>
                <div class="text-center text-xs text-primary/60 font-medium uppercase tracking-wider">
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
                      class={day_class(date, @current_date, @view_month, @entry_dates, Date.utc_today())}
                    >
                      <%= date.day %>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Legend -->
            <div class="flex gap-4 mt-4 text-xs text-base-content/60">
              <div class="flex items-center gap-1">
                <span class="w-3 h-3 rounded bg-success/20 border border-success/50"></span>
                Has entry
              </div>
              <div class="flex items-center gap-1">
                <span class="w-3 h-3 rounded ring-2 ring-primary"></span>
                Today
              </div>
            </div>
          </div>

          <!-- Entry Editor -->
          <div class="lg:col-span-2 card card-ornate corner-tl corner-tr corner-bl corner-br p-4">
            <div class="flex justify-between items-center mb-4">
              <h2 class="panel-header mb-0 pb-0 border-0"><%= format_date(@current_date) %></h2>
              <%= if @selected_entry && !@editing do %>
                <button phx-click="edit_entry" class="btn btn-imperial btn-sm">
                  <.icon name="hero-pencil" class="w-4 h-4" />
                  Edit
                </button>
              <% end %>
            </div>

            <%= if @editing do %>
              <!-- Edit Form -->
              <form phx-submit="save_entry" class="space-y-4">
                <!-- Mood & Energy -->
                <div class="grid grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label">
                      <span class="stat-block-label">Vitality</span>
                    </label>
                    <div class="flex gap-1">
                      <%= for val <- 1..5 do %>
                        <label class={"btn btn-sm flex-1 btn-imperial #{if @selected_entry && @selected_entry.mood == val, do: "btn-imperial-primary"}"}>
                          <input
                            type="radio"
                            name="mood"
                            value={val}
                            checked={@selected_entry && @selected_entry.mood == val}
                            class="hidden"
                          />
                          <span title={Journal.mood_label(val)}><%= Journal.mood_emoji(val) %></span>
                        </label>
                      <% end %>
                    </div>
                  </div>

                  <div class="form-control">
                    <label class="label">
                      <span class="stat-block-label">Energy</span>
                    </label>
                    <div class="flex gap-1">
                      <%= for val <- 1..5 do %>
                        <label class={"btn btn-sm flex-1 btn-imperial #{if @selected_entry && @selected_entry.energy == val, do: "btn-imperial-primary"}"}>
                          <input
                            type="radio"
                            name="energy"
                            value={val}
                            checked={@selected_entry && @selected_entry.energy == val}
                            class="hidden"
                          />
                          <span title={Journal.energy_label(val)}><%= Journal.energy_emoji(val) %></span>
                        </label>
                      <% end %>
                    </div>
                  </div>
                </div>

                <!-- Content -->
                <div class="form-control">
                  <label class="label">
                    <span class="stat-block-label">Chronicle Entry</span>
                  </label>
                  <textarea
                    name="content"
                    class="textarea input-imperial h-64 font-mono"
                    placeholder="Record the events of this day..."
                  ><%= if @selected_entry, do: @selected_entry.content, else: "" %></textarea>
                </div>

                <!-- Actions -->
                <div class="flex justify-between">
                  <%= if @selected_entry do %>
                    <button
                      type="button"
                      phx-click="delete_entry"
                      data-confirm="Delete this chronicle entry?"
                      class="btn btn-imperial-danger"
                    >
                      Delete
                    </button>
                  <% else %>
                    <div></div>
                  <% end %>
                  <div class="flex gap-2">
                    <%= if @selected_entry do %>
                      <button type="button" phx-click="cancel_edit" class="btn btn-imperial">
                        Cancel
                      </button>
                    <% end %>
                    <button type="submit" class="btn btn-imperial-primary">
                      Save Entry
                    </button>
                  </div>
                </div>
              </form>
            <% else %>
              <!-- View Mode -->
              <%= if @selected_entry do %>
                <!-- Mood & Energy Display -->
                <%= if @selected_entry.mood || @selected_entry.energy do %>
                  <div class="flex gap-6 mb-4">
                    <%= if @selected_entry.mood do %>
                      <div class="flex items-center gap-2">
                        <span class="text-2xl"><%= Journal.mood_emoji(@selected_entry.mood) %></span>
                        <span class="stat-block-label"><%= Journal.mood_label(@selected_entry.mood) %></span>
                      </div>
                    <% end %>
                    <%= if @selected_entry.energy do %>
                      <div class="flex items-center gap-2">
                        <span class="text-2xl"><%= Journal.energy_emoji(@selected_entry.energy) %></span>
                        <span class="stat-block-label"><%= Journal.energy_label(@selected_entry.energy) %></span>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <!-- Content -->
                <%= if @selected_entry.content && @selected_entry.content != "" do %>
                  <div class="prose max-w-none">
                    <pre class="whitespace-pre-wrap font-body text-base bg-transparent p-0 text-base-content/90"><%= @selected_entry.content %></pre>
                  </div>
                <% else %>
                  <p class="text-base-content/50 italic">No content written for this day.</p>
                <% end %>
              <% else %>
                <div class="text-center py-12">
                  <p class="text-base-content/50 mb-4 italic">No chronicle entry for this day.</p>
                  <button phx-click="edit_entry" class="btn btn-imperial-primary">
                    <.icon name="hero-pencil" class="w-4 h-4" />
                    Write Entry
                  </button>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <!-- Recent Entries List -->
        <div class="mt-8">
          <h2 class="panel-header">Recent Entries</h2>
          <div class="space-y-4">
            <%= if Enum.empty?(@entries) do %>
              <p class="text-base-content/50 italic">No entries this month.</p>
            <% else %>
              <%= for entry <- Enum.take(@entries, 5) do %>
                <div
                  class={"card card-ornate p-4 cursor-pointer hover:border-primary/50 transition-colors #{if @selected_entry && @selected_entry.id == entry.id, do: "border-primary"}"}
                  phx-click="select_date"
                  phx-value-date={Date.to_iso8601(entry.entry_date)}
                >
                  <div class="flex justify-between items-start">
                    <div>
                      <h3 class="font-semibold text-primary"><%= format_date(entry.entry_date) %></h3>
                      <%= if entry.content do %>
                        <p class="text-sm text-base-content/60 mt-1 line-clamp-2 italic">
                          "<%= String.slice(entry.content || "", 0, 150) %><%= if String.length(entry.content || "") > 150, do: "..." %>"
                        </p>
                      <% end %>
                    </div>
                    <div class="flex gap-2">
                      <%= if entry.mood do %>
                        <span title={Journal.mood_label(entry.mood)}><%= Journal.mood_emoji(entry.mood) %></span>
                      <% end %>
                      <%= if entry.energy do %>
                        <span title={Journal.energy_label(entry.energy)}><%= Journal.energy_emoji(entry.energy) %></span>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </main>

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
        <.link navigate={~p"/journal"} class="hud-nav-item hud-nav-item-active">
          <.icon name="hero-book-open" class="hud-nav-icon" />
          <span class="hud-nav-label">Chronicle</span>
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
