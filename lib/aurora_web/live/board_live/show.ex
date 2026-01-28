defmodule AuroraWeb.BoardLive.Show do
  use AuroraWeb, :live_view

  alias Aurora.Boards

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    board = Boards.get_board!(id)
    labels = Boards.list_labels()
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, board.name)
     |> assign(:board, board)
     |> assign(:columns, board.columns)
     |> assign(:labels, labels)
     |> assign(:editing_column, nil)
     |> assign(:editing_task, nil)
     |> assign(:new_task_column_id, nil)
     |> assign(:selected_task, nil)
     |> assign(:modal_priority, 4)
     |> assign(:show_labels_menu, false)
     # Filters
     |> assign(:search_query, "")
     |> assign(:filter_labels, [])
     |> assign(:filter_priority, nil)
     |> assign(:filter_due_date, nil)
     |> assign(:show_filter_labels, false)
     |> assign(:show_filter_priority, false)
     |> assign(:show_filter_due, false)
     # View mode
     |> assign(:view_mode, :kanban)
     |> assign(:current_week_start, week_start(today))
     |> assign(:current_month, {today.year, today.month})
     |> assign(:selected_day, today)
     |> load_scheduling_data()}
  end

  defp week_start(date) do
    day_of_week = Date.day_of_week(date)
    Date.add(date, -(day_of_week - 1))
  end

  defp load_scheduling_data(socket) do
    board_id = socket.assigns.board.id
    week_start = socket.assigns.current_week_start
    week_end = Date.add(week_start, 6)
    {year, month} = socket.assigns.current_month
    month_start = Date.new!(year, month, 1)
    month_end = Date.end_of_month(month_start)

    socket
    |> assign(:unscheduled_tasks, Boards.list_unscheduled_tasks(board_id))
    |> assign(:weekly_tasks, Boards.list_scheduled_tasks_for_range(board_id, week_start, week_end))
    |> assign(:monthly_tasks, Boards.list_scheduled_tasks_for_range(board_id, month_start, month_end))
  end

  # Priority colors
  defp priority_color(1), do: "text-error"
  defp priority_color(2), do: "text-warning"
  defp priority_color(3), do: "text-info"
  defp priority_color(_), do: "text-base-content/40"

  defp priority_label(1), do: "P1"
  defp priority_label(2), do: "P2"
  defp priority_label(3), do: "P3"
  defp priority_label(_), do: "P4"

  defp due_date_class(nil), do: ""
  defp due_date_class(date) do
    today = Date.utc_today()
    case Date.compare(date, today) do
      :lt -> "text-error"
      :eq -> "text-warning"
      :gt -> "text-base-content/60"
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # Column events
  @impl true
  def handle_event("add_column", _params, socket) do
    board = socket.assigns.board
    position = length(socket.assigns.columns)

    case Boards.create_column(%{name: "New Column", board_id: board.id, position: position}) do
      {:ok, _column} ->
        {:noreply, reload_board(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create column")}
    end
  end

  def handle_event("edit_column", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_column, String.to_integer(id))}
  end

  def handle_event("update_column", %{"name" => name} = params, socket) do
    id = params["value"]["id"] || params["id"]
    column = Boards.get_column!(id)

    case Boards.update_column(column, %{name: name}) do
      {:ok, _column} ->
        {:noreply,
         socket
         |> assign(:editing_column, nil)
         |> reload_board()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update column")}
    end
  end

  def handle_event("cancel_edit_column", _params, socket) do
    {:noreply, assign(socket, :editing_column, nil)}
  end

  def handle_event("delete_column", %{"id" => id}, socket) do
    column = Boards.get_column!(id)

    case Boards.delete_column(column) do
      {:ok, _} ->
        {:noreply, reload_board(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete column")}
    end
  end

  # Task events
  def handle_event("show_new_task", %{"column-id" => column_id}, socket) do
    {:noreply, assign(socket, :new_task_column_id, String.to_integer(column_id))}
  end

  def handle_event("cancel_new_task", _params, socket) do
    {:noreply, assign(socket, :new_task_column_id, nil)}
  end

  def handle_event("create_task", %{"column_id" => column_id, "title" => title}, socket) do
    column = Boards.get_column!(column_id)
    tasks = Boards.list_tasks(column.id)
    position = length(tasks)

    case Boards.create_task(%{title: title, column_id: column.id, position: position}) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> assign(:new_task_column_id, nil)
         |> reload_board()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create task")}
    end
  end

  def handle_event("edit_task", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_task, String.to_integer(id))}
  end

  def handle_event("update_task", %{"title" => title} = params, socket) do
    id = params["value"]["id"] || params["id"]
    task = Boards.get_task!(id)

    case Boards.update_task(task, %{title: title}) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> assign(:editing_task, nil)
         |> reload_board()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  def handle_event("cancel_edit_task", _params, socket) do
    {:noreply, assign(socket, :editing_task, nil)}
  end

  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Boards.get_task!(id)

    case Boards.delete_task(task) do
      {:ok, _} ->
        {:noreply, reload_board(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  # Drag and drop
  def handle_event("reorder_columns", %{"ids" => column_ids}, socket) do
    board = socket.assigns.board
    Boards.reorder_columns(board.id, column_ids)
    {:noreply, reload_board(socket)}
  end

  def handle_event("move_task", %{"task_id" => task_id, "column_id" => column_id, "position" => position}, socket) do
    Boards.move_task(
      to_int(task_id),
      to_int(column_id),
      to_int(position)
    )

    {:noreply, reload_board(socket)}
  end

  defp to_int(val) when is_integer(val), do: val
  defp to_int(val) when is_binary(val), do: String.to_integer(val)

  def handle_event("reorder_tasks", %{"column_id" => column_id, "ids" => task_ids}, socket) do
    Boards.reorder_tasks(String.to_integer(column_id), task_ids)
    {:noreply, reload_board(socket)}
  end

  defp reload_board(socket) do
    board = Boards.get_board!(socket.assigns.board.id)
    labels = Boards.list_labels()

    socket
    |> assign(board: board, columns: board.columns, labels: labels)
    |> load_scheduling_data()
  end

  # Task modal events
  def handle_event("open_task", %{"id" => id}, socket) do
    task = Boards.get_task!(id)
    {:noreply,
     socket
     |> assign(:selected_task, task)
     |> assign(:modal_priority, task.priority)}
  end

  def handle_event("set_modal_priority", %{"priority" => priority}, socket) do
    {:noreply, assign(socket, :modal_priority, String.to_integer(priority))}
  end

  def handle_event("close_task_modal", _params, socket) do
    {:noreply, assign(socket, :selected_task, nil)}
  end

  def handle_event("save_task", params, socket) do
    task = socket.assigns.selected_task

    task_params = %{
      title: params["title"],
      description: params["description"],
      priority: String.to_integer(params["priority"] || "4"),
      due_date: parse_date(params["due_date"])
    }

    case Boards.update_task(task, task_params) do
      {:ok, updated_task} ->
        # Update labels if provided
        if params["label_ids"] do
          label_ids = params["label_ids"]
            |> String.split(",")
            |> Enum.map(&String.to_integer/1)
            |> Enum.reject(&(&1 == 0))
          Boards.set_task_labels(task.id, label_ids)
        end

        # Handle scheduling
        schedule_date = params["schedule_date"]
        schedule_start = params["schedule_start_time"]
        schedule_end = params["schedule_end_time"]

        cond do
          schedule_date != "" and schedule_start != "" ->
            # Schedule or update the task
            {:ok, date} = Date.from_iso8601(schedule_date)
            {:ok, start_time} = Time.from_iso8601(schedule_start <> ":00")
            start_at = DateTime.new!(date, start_time, "Etc/UTC")

            end_at =
              if schedule_end != "" do
                {:ok, end_time} = Time.from_iso8601(schedule_end <> ":00")
                DateTime.new!(date, end_time, "Etc/UTC")
              else
                DateTime.add(start_at, 3600, :second)
              end

            Boards.schedule_task(updated_task.id, start_at, end_at)

          schedule_date == "" and task.event_id != nil ->
            # Clear scheduling if date was cleared but task was scheduled
            Boards.unschedule_task(task.id)

          true ->
            :ok
        end

        {:noreply,
         socket
         |> assign(:selected_task, nil)
         |> reload_board()
         |> put_flash(:info, "Task updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  def handle_event("toggle_task_label", %{"task-id" => task_id, "label-id" => label_id}, socket) do
    task_id = String.to_integer(task_id)
    label_id = String.to_integer(label_id)
    task = Boards.get_task!(task_id)

    label_ids = Enum.map(task.labels, & &1.id)

    new_label_ids =
      if label_id in label_ids do
        Enum.reject(label_ids, &(&1 == label_id))
      else
        [label_id | label_ids]
      end

    Boards.set_task_labels(task_id, new_label_ids)

    # Reload the selected task if it's open
    socket =
      if socket.assigns.selected_task && socket.assigns.selected_task.id == task_id do
        assign(socket, :selected_task, Boards.get_task!(task_id))
      else
        socket
      end

    {:noreply, reload_board(socket)}
  end

  # Label management events
  def handle_event("toggle_labels_menu", _params, socket) do
    {:noreply, assign(socket, :show_labels_menu, !socket.assigns.show_labels_menu)}
  end

  def handle_event("create_label", %{"name" => name, "color" => color}, socket) do
    case Boards.create_label(%{name: name, color: color}) do
      {:ok, _label} ->
        {:noreply, reload_board(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create label")}
    end
  end

  def handle_event("delete_label", %{"id" => id}, socket) do
    label = Boards.get_label!(id)

    case Boards.delete_label(label) do
      {:ok, _} ->
        {:noreply, reload_board(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete label")}
    end
  end

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil
  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # Filter events
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  def handle_event("toggle_filter_labels", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_filter_labels, !socket.assigns.show_filter_labels)
     |> assign(:show_filter_priority, false)
     |> assign(:show_filter_due, false)}
  end

  def handle_event("toggle_filter_priority", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_filter_priority, !socket.assigns.show_filter_priority)
     |> assign(:show_filter_labels, false)
     |> assign(:show_filter_due, false)}
  end

  def handle_event("toggle_filter_due", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_filter_due, !socket.assigns.show_filter_due)
     |> assign(:show_filter_labels, false)
     |> assign(:show_filter_priority, false)}
  end

  def handle_event("toggle_label_filter", %{"id" => id}, socket) do
    label_id = String.to_integer(id)
    filter_labels = socket.assigns.filter_labels

    new_filter_labels =
      if label_id in filter_labels do
        Enum.reject(filter_labels, &(&1 == label_id))
      else
        [label_id | filter_labels]
      end

    {:noreply, assign(socket, :filter_labels, new_filter_labels)}
  end

  def handle_event("set_priority_filter", %{"priority" => priority}, socket) do
    priority_val = if priority == "", do: nil, else: String.to_integer(priority)
    {:noreply, assign(socket, filter_priority: priority_val, show_filter_priority: false)}
  end

  def handle_event("set_due_date_filter", %{"due" => due}, socket) do
    due_val = if due == "", do: nil, else: due
    {:noreply, assign(socket, filter_due_date: due_val, show_filter_due: false)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:filter_labels, [])
     |> assign(:filter_priority, nil)
     |> assign(:filter_due_date, nil)}
  end

  # View mode events
  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    mode = String.to_existing_atom(mode)
    {:noreply, assign(socket, :view_mode, mode)}
  end

  def handle_event("prev_week", _params, socket) do
    new_start = Date.add(socket.assigns.current_week_start, -7)
    {:noreply, socket |> assign(:current_week_start, new_start) |> load_scheduling_data()}
  end

  def handle_event("next_week", _params, socket) do
    new_start = Date.add(socket.assigns.current_week_start, 7)
    {:noreply, socket |> assign(:current_week_start, new_start) |> load_scheduling_data()}
  end

  def handle_event("today_week", _params, socket) do
    today = Date.utc_today()
    {:noreply, socket |> assign(:current_week_start, week_start(today)) |> load_scheduling_data()}
  end

  def handle_event("prev_month", _params, socket) do
    {year, month} = socket.assigns.current_month
    {new_year, new_month} = if month == 1, do: {year - 1, 12}, else: {year, month - 1}
    {:noreply, socket |> assign(:current_month, {new_year, new_month}) |> load_scheduling_data()}
  end

  def handle_event("next_month", _params, socket) do
    {year, month} = socket.assigns.current_month
    {new_year, new_month} = if month == 12, do: {year + 1, 1}, else: {year, month + 1}
    {:noreply, socket |> assign(:current_month, {new_year, new_month}) |> load_scheduling_data()}
  end

  def handle_event("select_day", %{"date" => date_str}, socket) do
    {:ok, date} = Date.from_iso8601(date_str)
    {:noreply, assign(socket, :selected_day, date)}
  end

  def handle_event("schedule_task", %{"task_id" => task_id, "date" => date_str, "hour" => hour}, socket) do
    {:ok, date} = Date.from_iso8601(date_str)
    hour = String.to_integer(hour)
    start_at = DateTime.new!(date, Time.new!(hour, 0, 0), "Etc/UTC")

    case Boards.schedule_task(String.to_integer(task_id), start_at) do
      {:ok, _task} ->
        {:noreply, reload_board(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to schedule task")}
    end
  end

  def handle_event("unschedule_task", %{"task_id" => task_id}, socket) do
    task_id = String.to_integer(task_id)

    case Boards.unschedule_task(task_id) do
      {:ok, updated_task} ->
        # Refresh selected_task if it's the one being unscheduled
        socket =
          if socket.assigns.selected_task && socket.assigns.selected_task.id == task_id do
            assign(socket, :selected_task, updated_task)
          else
            socket
          end

        {:noreply, reload_board(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to unschedule task")}
    end
  end

  # Filter helper functions
  defp filter_tasks(tasks, assigns) do
    tasks
    |> filter_by_search(assigns.search_query)
    |> filter_by_labels(assigns.filter_labels)
    |> filter_by_priority(assigns.filter_priority)
    |> filter_by_due_date(assigns.filter_due_date)
  end

  defp filter_by_search(tasks, ""), do: tasks
  defp filter_by_search(tasks, query) do
    query = String.downcase(query)
    Enum.filter(tasks, fn task ->
      String.contains?(String.downcase(task.title || ""), query) ||
        String.contains?(String.downcase(task.description || ""), query)
    end)
  end

  defp filter_by_labels(tasks, []), do: tasks
  defp filter_by_labels(tasks, label_ids) do
    Enum.filter(tasks, fn task ->
      task_label_ids = Enum.map(task.labels, & &1.id)
      Enum.any?(label_ids, &(&1 in task_label_ids))
    end)
  end

  defp filter_by_priority(tasks, nil), do: tasks
  defp filter_by_priority(tasks, priority) do
    Enum.filter(tasks, &(&1.priority == priority))
  end

  defp filter_by_due_date(tasks, nil), do: tasks
  defp filter_by_due_date(tasks, "overdue") do
    today = Date.utc_today()
    Enum.filter(tasks, fn task ->
      task.due_date && Date.compare(task.due_date, today) == :lt
    end)
  end
  defp filter_by_due_date(tasks, "today") do
    today = Date.utc_today()
    Enum.filter(tasks, fn task ->
      task.due_date && Date.compare(task.due_date, today) == :eq
    end)
  end
  defp filter_by_due_date(tasks, "week") do
    today = Date.utc_today()
    week_end = Date.add(today, 7)
    Enum.filter(tasks, fn task ->
      task.due_date &&
        Date.compare(task.due_date, today) != :lt &&
        Date.compare(task.due_date, week_end) != :gt
    end)
  end
  defp filter_by_due_date(tasks, "none") do
    Enum.filter(tasks, &is_nil(&1.due_date))
  end

  defp has_active_filters?(assigns) do
    assigns.search_query != "" ||
      assigns.filter_labels != [] ||
      assigns.filter_priority != nil ||
      assigns.filter_due_date != nil
  end

  # Weekly View Component
  defp weekly_view(assigns) do
    week_days = for i <- 0..6, do: Date.add(assigns.current_week_start, i)
    hours = for h <- 6..22, do: h
    today = Date.utc_today()

    assigns =
      assigns
      |> assign(:week_days, week_days)
      |> assign(:hours, hours)
      |> assign(:today, today)

    ~H"""
    <div class="flex-1 flex bg-base-300 overflow-hidden">
      <!-- Unscheduled Tasks Sidebar -->
      <div class="w-64 bg-base-200 border-r border-primary/20 flex flex-col">
        <div class="p-3 border-b border-primary/20 bg-base-100">
          <h3 class="font-semibold text-primary tracking-wide">Unscheduled</h3>
          <p class="text-xs text-base-content/60 mt-1">Drag to schedule</p>
        </div>
        <div
          class="flex-1 overflow-y-auto p-2 space-y-2"
          id="unscheduled-tasks"
          phx-hook="Sortable"
          data-group="schedule"
        >
          <%= for task <- @unscheduled_tasks do %>
            <div
              class="bg-base-100 border border-primary/10 rounded p-2 cursor-move hover:border-primary/40 transition-colors text-sm"
              id={"unscheduled-task-#{task.id}"}
              data-id={task.id}
              data-task-id={task.id}
            >
              <div class="flex items-center gap-2">
                <span class={"font-bold text-xs #{priority_color(task.priority)}"}>
                  <%= priority_label(task.priority) %>
                </span>
                <span class="truncate"><%= task.title %></span>
              </div>
              <%= if task.column do %>
                <div class="text-xs text-base-content/50 mt-1"><%= task.column.name %></div>
              <% end %>
            </div>
          <% end %>
          <%= if Enum.empty?(@unscheduled_tasks) do %>
            <p class="text-sm text-base-content/60 italic p-2">All tasks scheduled</p>
          <% end %>
        </div>
      </div>

      <!-- Week Grid -->
      <div class="flex-1 flex flex-col overflow-hidden">
        <!-- Week Navigation -->
        <div class="p-3 border-b border-primary/20 bg-base-200 flex items-center justify-between">
          <button phx-click="prev_week" class="btn btn-imperial btn-sm">
            <.icon name="hero-chevron-left" class="w-4 h-4" />
          </button>
          <div class="flex items-center gap-4">
            <span class="font-semibold text-primary">
              <%= Calendar.strftime(@current_week_start, "%b %d") %> - <%= Calendar.strftime(Date.add(@current_week_start, 6), "%b %d, %Y") %>
            </span>
            <button phx-click="today_week" class="btn btn-imperial btn-xs">Today</button>
          </div>
          <button phx-click="next_week" class="btn btn-imperial btn-sm">
            <.icon name="hero-chevron-right" class="w-4 h-4" />
          </button>
        </div>

        <!-- Day Headers -->
        <div class="flex border-b border-primary/20 bg-base-100">
          <!-- Spacer for time label column -->
          <div class="w-16 flex-shrink-0"></div>
          <!-- Day columns -->
          <div class="flex-1 grid grid-cols-7">
            <%= for day <- @week_days do %>
              <div class={"p-2 text-center border-r border-primary/10 last:border-r-0 #{if day == @today, do: "bg-primary/10"}"}>
                <div class="text-xs text-base-content/60"><%= Calendar.strftime(day, "%a") %></div>
                <div class={"text-lg font-semibold #{if day == @today, do: "text-primary", else: "text-base-content"}"}>
                  <%= day.day %>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Time Grid -->
        <div class="flex-1 overflow-y-auto">
          <div class="relative">
            <%= for hour <- @hours do %>
              <div class="flex border-b border-primary/10 h-16">
                <!-- Hour Label -->
                <div class="w-16 flex-shrink-0 p-1 text-xs text-base-content/60 text-right pr-2 bg-base-200">
                  <%= format_hour(hour) %>
                </div>
                <!-- Day Columns -->
                <div class="flex-1 grid grid-cols-7">
                  <%= for day <- @week_days do %>
                    <div
                      class={"border-r border-primary/10 last:border-r-0 relative hover:bg-primary/5 cursor-pointer #{if day == @today, do: "bg-primary/5"}" }
                      id={"slot-#{day}-#{hour}"}
                      phx-hook="Sortable"
                      data-group="schedule"
                      data-date={Date.to_iso8601(day)}
                      data-hour={hour}
                    >
                      <!-- Scheduled tasks for this slot -->
                      <%= for task <- tasks_at_slot(@weekly_tasks, day, hour) do %>
                        <div
                          class="absolute inset-x-0.5 top-0.5 bg-primary/20 border border-primary/40 rounded p-1 text-xs cursor-move hover:bg-primary/30 z-10"
                          id={"scheduled-task-#{task.id}"}
                          data-id={task.id}
                          data-task-id={task.id}
                          style={"height: #{task_height(task)}px;"}
                        >
                          <div class="truncate font-medium"><%= task.title %></div>
                          <%= if task.event do %>
                            <div class="text-base-content/60"><%= format_time(task.event.start_at) %></div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Calendar View Component
  defp calendar_view(assigns) do
    {year, month} = assigns.current_month
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)
    first_weekday = Date.day_of_week(first_day)
    today = Date.utc_today()

    # Build calendar grid
    days_before = for d <- (first_weekday - 1)..1, d > 0, do: Date.add(first_day, -d)
    days_in_month = for d <- 0..(last_day.day - 1), do: Date.add(first_day, d)
    days_after_count = 7 - rem(length(days_before) + length(days_in_month), 7)
    days_after_count = if days_after_count == 7, do: 0, else: days_after_count
    days_after = for d <- 1..days_after_count, do: Date.add(last_day, d)
    all_days = days_before ++ days_in_month ++ days_after

    assigns =
      assigns
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:first_day, first_day)
      |> assign(:all_days, all_days)
      |> assign(:today, today)

    ~H"""
    <div class="flex-1 flex bg-base-300 overflow-hidden">
      <!-- Calendar Grid -->
      <div class="flex-1 flex flex-col overflow-hidden">
        <!-- Month Navigation -->
        <div class="p-3 border-b border-primary/20 bg-base-200 flex items-center justify-between">
          <button phx-click="prev_month" class="btn btn-imperial btn-sm">
            <.icon name="hero-chevron-left" class="w-4 h-4" />
          </button>
          <span class="font-semibold text-primary text-lg">
            <%= Calendar.strftime(@first_day, "%B %Y") %>
          </span>
          <button phx-click="next_month" class="btn btn-imperial btn-sm">
            <.icon name="hero-chevron-right" class="w-4 h-4" />
          </button>
        </div>

        <!-- Day Headers -->
        <div class="grid grid-cols-7 border-b border-primary/20 bg-base-100">
          <%= for day_name <- ~w(Mon Tue Wed Thu Fri Sat Sun) do %>
            <div class="p-2 text-center text-sm font-semibold text-primary border-r border-primary/10 last:border-r-0">
              <%= day_name %>
            </div>
          <% end %>
        </div>

        <!-- Calendar Grid -->
        <div class="flex-1 overflow-y-auto">
          <div class="grid grid-cols-7 h-full">
            <%= for day <- @all_days do %>
              <% is_current_month = day.month == @month %>
              <% is_today = day == @today %>
              <% is_selected = day == @selected_day %>
              <% day_tasks = tasks_on_day(@monthly_tasks, day) %>
              <div
                class={"border-r border-b border-primary/10 p-1 min-h-24 cursor-pointer hover:bg-primary/5 #{unless is_current_month, do: "bg-base-300/50"} #{if is_selected, do: "ring-2 ring-primary ring-inset"}"}
                phx-click="select_day"
                phx-value-date={Date.to_iso8601(day)}
              >
                <div class={"text-sm mb-1 #{if is_today, do: "font-bold text-primary"} #{unless is_current_month, do: "text-base-content/40"}"}>
                  <%= day.day %>
                </div>
                <div class="space-y-0.5">
                  <%= for task <- Enum.take(day_tasks, 3) do %>
                    <div class="text-xs bg-primary/20 rounded px-1 py-0.5 truncate border-l-2 border-primary">
                      <%= task.title %>
                    </div>
                  <% end %>
                  <%= if length(day_tasks) > 3 do %>
                    <div class="text-xs text-base-content/60">+<%= length(day_tasks) - 3 %> more</div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Day Detail Sidebar -->
      <div class="w-80 bg-base-200 border-l border-primary/20 flex flex-col">
        <div class="p-3 border-b border-primary/20 bg-base-100">
          <h3 class="font-semibold text-primary tracking-wide">
            <%= Calendar.strftime(@selected_day, "%A, %B %d") %>
          </h3>
        </div>

        <!-- Scheduled Tasks for Selected Day -->
        <div class="flex-1 overflow-y-auto p-2">
          <h4 class="stat-block-label text-xs mb-2">Scheduled</h4>
          <div class="space-y-2 mb-4">
            <% day_tasks = tasks_on_day(@monthly_tasks, @selected_day) %>
            <%= for task <- day_tasks do %>
              <div class="bg-base-100 border border-primary/10 rounded p-2 text-sm">
                <div class="flex items-center gap-2">
                  <span class={"font-bold text-xs #{priority_color(task.priority)}"}>
                    <%= priority_label(task.priority) %>
                  </span>
                  <span class="truncate flex-1"><%= task.title %></span>
                  <button
                    phx-click="unschedule_task"
                    phx-value-task_id={task.id}
                    class="btn btn-ghost btn-xs text-error"
                    title="Unschedule"
                  >
                    <.icon name="hero-x-mark" class="w-3 h-3" />
                  </button>
                </div>
                <%= if task.event do %>
                  <div class="text-xs text-base-content/60 mt-1">
                    <.icon name="hero-clock" class="w-3 h-3 inline" />
                    <%= format_time(task.event.start_at) %> - <%= format_time(task.event.end_at) %>
                  </div>
                <% end %>
              </div>
            <% end %>
            <%= if Enum.empty?(day_tasks) do %>
              <p class="text-sm text-base-content/60 italic">No scheduled tasks</p>
            <% end %>
          </div>

          <!-- Quick Schedule -->
          <h4 class="stat-block-label text-xs mb-2 mt-4">Quick Schedule</h4>
          <div class="space-y-1">
            <%= for task <- Enum.take(@unscheduled_tasks, 5) do %>
              <div class="flex items-center gap-2 p-1 hover:bg-base-100 rounded">
                <button
                  phx-click="schedule_task"
                  phx-value-task_id={task.id}
                  phx-value-date={Date.to_iso8601(@selected_day)}
                  phx-value-hour="9"
                  class="btn btn-ghost btn-xs text-primary"
                  title="Schedule for 9 AM"
                >
                  <.icon name="hero-plus" class="w-3 h-3" />
                </button>
                <span class="text-sm truncate flex-1"><%= task.title %></span>
              </div>
            <% end %>
            <%= if length(@unscheduled_tasks) > 5 do %>
              <p class="text-xs text-base-content/60 mt-2">+<%= length(@unscheduled_tasks) - 5 %> more unscheduled</p>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions for views
  defp format_hour(hour) when hour < 12, do: "#{hour} AM"
  defp format_hour(12), do: "12 PM"
  defp format_hour(hour), do: "#{hour - 12} PM"

  defp format_time(nil), do: ""
  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%-I:%M %p")
  end

  defp tasks_at_slot(tasks, date, hour) do
    Enum.filter(tasks, fn task ->
      task.event &&
        DateTime.to_date(task.event.start_at) == date &&
        task.event.start_at.hour == hour
    end)
  end

  defp tasks_on_day(tasks, date) do
    Enum.filter(tasks, fn task ->
      task.event && DateTime.to_date(task.event.start_at) == date
    end)
  end

  defp task_height(task) do
    if task.event && task.event.end_at do
      duration_seconds = DateTime.diff(task.event.end_at, task.event.start_at)
      duration_hours = duration_seconds / 3600
      # 64px per hour (h-16 = 4rem = 64px)
      max(24, round(duration_hours * 64))
    else
      64
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-base-300">
      <!-- Header -->
      <div class="border-b border-primary/30 bg-base-200 px-4 py-3">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/boards"} class="btn btn-ghost btn-sm text-primary">
              <.icon name="hero-arrow-left" class="w-4 h-4" />
            </.link>
            <div class="flex items-center gap-3">
              <.icon name="hero-map" class="w-5 h-5 text-primary" />
              <h1 class="text-xl font-semibold text-primary tracking-wide"><%= @board.name %></h1>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <!-- View Mode Toggle -->
            <div class="btn-group">
              <button
                phx-click="set_view_mode"
                phx-value-mode="kanban"
                class={"btn btn-sm #{if @view_mode == :kanban, do: "btn-imperial-primary", else: "btn-imperial"}"}
              >
                <.icon name="hero-view-columns" class="w-4 h-4" />
                Kanban
              </button>
              <button
                phx-click="set_view_mode"
                phx-value-mode="weekly"
                class={"btn btn-sm #{if @view_mode == :weekly, do: "btn-imperial-primary", else: "btn-imperial"}"}
              >
                <.icon name="hero-calendar-days" class="w-4 h-4" />
                Weekly
              </button>
              <button
                phx-click="set_view_mode"
                phx-value-mode="calendar"
                class={"btn btn-sm #{if @view_mode == :calendar, do: "btn-imperial-primary", else: "btn-imperial"}"}
              >
                <.icon name="hero-calendar" class="w-4 h-4" />
                Calendar
              </button>
            </div>

            <!-- Labels Management -->
            <div class="dropdown dropdown-end">
              <label tabindex="0" phx-click="toggle_labels_menu" class="btn btn-imperial btn-sm">
                <.icon name="hero-tag" class="w-4 h-4" />
                Insignias
              </label>
              <%= if @show_labels_menu do %>
                <div tabindex="0" class="dropdown-content z-50 p-4 shadow-lg bg-base-200 border border-primary/30 rounded w-72">
                  <h3 class="stat-block-label mb-3">Manage Insignias</h3>

                  <!-- Existing Labels -->
                  <div class="space-y-2 mb-4">
                    <%= for label <- @labels do %>
                      <div class="flex items-center justify-between gap-2">
                        <div class="flex items-center gap-2">
                          <span class="w-4 h-4 rounded" style={"background-color: #{label.color}"}></span>
                          <span class="text-sm"><%= label.name %></span>
                        </div>
                        <button phx-click="delete_label" phx-value-id={label.id} class="btn btn-ghost btn-xs text-error">
                          <.icon name="hero-x-mark" class="w-3 h-3" />
                        </button>
                      </div>
                    <% end %>
                    <%= if Enum.empty?(@labels) do %>
                      <p class="text-sm text-base-content/60 italic">No insignias established</p>
                    <% end %>
                  </div>

                  <!-- New Label Form -->
                  <form phx-submit="create_label" class="space-y-2">
                    <div class="flex gap-2">
                      <input type="text" name="name" placeholder="Insignia name" class="input input-imperial input-sm flex-1" required />
                      <input type="color" name="color" value="#c9a227" class="w-10 h-8 rounded cursor-pointer border border-primary/30" />
                    </div>
                    <button type="submit" class="btn btn-imperial-primary btn-sm w-full">Add Insignia</button>
                  </form>
                </div>
              <% end %>
            </div>
            <.link navigate={~p"/"} class="btn btn-imperial btn-sm">Bridge</.link>
          </div>
        </div>
      </div>

      <!-- Filter Bar -->
      <div class="bg-base-200 px-4 py-2 flex items-center gap-2 border-b border-primary/20">
        <!-- Search -->
        <div class="form-control">
          <div class="flex items-center gap-2">
            <span class="text-primary"><.icon name="hero-magnifying-glass" class="w-4 h-4" /></span>
            <input
              type="text"
              placeholder="Search directives..."
              value={@search_query}
              phx-keyup="search"
              phx-value-query={@search_query}
              phx-debounce="300"
              name="query"
              class="input input-imperial input-sm w-48"
            />
          </div>
        </div>

        <!-- Label Filter -->
        <div class="dropdown">
          <label tabindex="0" phx-click="toggle_filter_labels" class={"btn btn-sm #{if @filter_labels != [], do: "btn-imperial-primary", else: "btn-imperial"}"}>
            <.icon name="hero-tag" class="w-4 h-4" />
            Insignias
            <%= if @filter_labels != [] do %>
              <span class="badge-imperial text-xs"><%= length(@filter_labels) %></span>
            <% end %>
          </label>
          <%= if @show_filter_labels do %>
            <div tabindex="0" class="dropdown-content z-50 p-3 shadow-lg bg-base-200 border border-primary/30 rounded w-56">
              <div class="space-y-2">
                <%= for label <- @labels do %>
                  <label class="flex items-center gap-2 cursor-pointer hover:bg-base-100 p-1 rounded">
                    <input
                      type="checkbox"
                      checked={label.id in @filter_labels}
                      phx-click="toggle_label_filter"
                      phx-value-id={label.id}
                      class="checkbox checkbox-sm checkbox-primary"
                    />
                    <span class="w-3 h-3 rounded" style={"background-color: #{label.color}"}></span>
                    <span class="text-sm"><%= label.name %></span>
                  </label>
                <% end %>
                <%= if Enum.empty?(@labels) do %>
                  <p class="text-sm text-base-content/60 italic">No insignias</p>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Priority Filter -->
        <div class="dropdown">
          <label tabindex="0" phx-click="toggle_filter_priority" class={"btn btn-sm #{if @filter_priority, do: "btn-imperial-primary", else: "btn-imperial"}"}>
            <.icon name="hero-flag" class="w-4 h-4" />
            Priority
            <%= if @filter_priority do %>
              <span class="badge-imperial text-xs"><%= priority_label(@filter_priority) %></span>
            <% end %>
          </label>
          <%= if @show_filter_priority do %>
            <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow-lg bg-base-200 border border-primary/30 rounded w-40">
              <li><a phx-click="set_priority_filter" phx-value-priority="" class={if @filter_priority == nil, do: "text-primary"}>All</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="1" class={"text-error #{if @filter_priority == 1, do: "font-bold"}"}>P1 - Critical</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="2" class={"text-warning #{if @filter_priority == 2, do: "font-bold"}"}>P2 - High</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="3" class={"text-info #{if @filter_priority == 3, do: "font-bold"}"}>P3 - Medium</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="4" class={if @filter_priority == 4, do: "font-bold"}>P4 - Low</a></li>
            </ul>
          <% end %>
        </div>

        <!-- Due Date Filter -->
        <div class="dropdown">
          <label tabindex="0" phx-click="toggle_filter_due" class={"btn btn-sm #{if @filter_due_date, do: "btn-imperial-primary", else: "btn-imperial"}"}>
            <.icon name="hero-calendar" class="w-4 h-4" />
            Deadline
            <%= if @filter_due_date do %>
              <span class="badge-imperial text-xs"><%= @filter_due_date %></span>
            <% end %>
          </label>
          <%= if @show_filter_due do %>
            <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow-lg bg-base-200 border border-primary/30 rounded w-40">
              <li><a phx-click="set_due_date_filter" phx-value-due="" class={if @filter_due_date == nil, do: "text-primary"}>All</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="overdue" class={"text-error #{if @filter_due_date == "overdue", do: "font-bold"}"}>Overdue</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="today" class={"text-warning #{if @filter_due_date == "today", do: "font-bold"}"}>Today</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="week" class={if @filter_due_date == "week", do: "font-bold"}>This Week</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="none" class={if @filter_due_date == "none", do: "font-bold"}>No Deadline</a></li>
            </ul>
          <% end %>
        </div>

        <!-- Clear Filters -->
        <%= if has_active_filters?(assigns) do %>
          <button phx-click="clear_filters" class="btn btn-imperial-danger btn-sm">
            <.icon name="hero-x-mark" class="w-4 h-4" />
            Clear
          </button>
        <% end %>
      </div>

      <!-- Main Content Area -->
      <%= case @view_mode do %>
        <% :kanban -> %>
          <!-- Kanban Board -->
          <div class="flex-1 overflow-x-auto p-4 bg-base-300">
            <div
              class="flex gap-4 h-full"
              id="columns-container"
              phx-hook="Sortable"
              data-group="columns"
            >
          <!-- Columns -->
          <%= for column <- @columns do %>
            <div
              class="flex-shrink-0 w-80 bg-base-200 border border-primary/20 rounded flex flex-col max-h-full"
              id={"column-#{column.id}"}
              data-id={column.id}
            >
              <!-- Column Header -->
              <div class="p-3 border-b border-primary/20 flex items-center justify-between bg-base-100">
                <%= if @editing_column == column.id do %>
                  <form phx-submit="update_column" phx-value-id={column.id} class="flex-1 flex gap-2">
                    <input
                      type="text"
                      name="name"
                      value={column.name}
                      class="input input-imperial input-sm flex-1"
                      autofocus
                    />
                    <button type="submit" class="btn btn-ghost btn-sm btn-square text-success">
                      <.icon name="hero-check" class="w-4 h-4" />
                    </button>
                    <button type="button" phx-click="cancel_edit_column" class="btn btn-ghost btn-sm btn-square text-error">
                      <.icon name="hero-x-mark" class="w-4 h-4" />
                    </button>
                  </form>
                <% else %>
                  <% filtered_count = length(filter_tasks(column.tasks, assigns)) %>
                  <% total_count = length(column.tasks) %>
                  <h3 class="font-semibold text-primary flex-1 tracking-wide">
                    <%= column.name %>
                    <span class="badge-imperial text-xs ml-2">
                      <%= if filtered_count != total_count do %>
                        <%= filtered_count %>/<%= total_count %>
                      <% else %>
                        <%= total_count %>
                      <% end %>
                    </span>
                  </h3>
                  <div class="dropdown dropdown-end">
                    <label tabindex="0" class="btn btn-ghost btn-sm btn-square text-primary">
                      <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
                    </label>
                    <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow-lg bg-base-200 border border-primary/30 rounded w-40">
                      <li><a phx-click="edit_column" phx-value-id={column.id} class="text-base-content hover:text-primary">Rename</a></li>
                      <li>
                        <a phx-click="delete_column" phx-value-id={column.id} data-confirm="Disband this division and all directives?" class="text-error hover:bg-error/20">
                          Disband
                        </a>
                      </li>
                    </ul>
                  </div>
                <% end %>
              </div>

              <!-- Tasks -->
              <% filtered_tasks = filter_tasks(column.tasks, assigns) %>
              <div
                class="flex-1 overflow-y-auto p-2 space-y-2"
                id={"tasks-#{column.id}"}
                phx-hook="Sortable"
                data-group="tasks"
                data-column-id={column.id}
              >
                <%= for task <- filtered_tasks do %>
                  <div
                    class="bg-base-100 border border-primary/10 rounded p-3 cursor-move hover:border-primary/40 transition-colors group"
                    id={"task-#{task.id}"}
                    data-id={task.id}
                  >
                    <!-- Task Header -->
                    <div class="flex items-start gap-2">
                      <!-- Priority indicator -->
                      <span class={"font-bold text-xs #{priority_color(task.priority)}"}>
                        <%= priority_label(task.priority) %>
                      </span>
                      <!-- Title - clickable to open modal -->
                      <p
                        class="text-sm flex-1 cursor-pointer hover:text-primary"
                        phx-click="open_task"
                        phx-value-id={task.id}
                      >
                        <%= task.title %>
                      </p>
                      <!-- Quick actions -->
                      <div class="flex gap-1 opacity-0 group-hover:opacity-100">
                        <button phx-click="delete_task" phx-value-id={task.id} data-confirm="Rescind this directive?" class="btn btn-ghost btn-xs btn-square text-error">
                          <.icon name="hero-trash" class="w-3 h-3" />
                        </button>
                      </div>
                    </div>

                    <!-- Labels -->
                    <%= if task.labels != [] do %>
                      <div class="flex flex-wrap gap-1 mt-2">
                        <%= for label <- task.labels do %>
                          <span
                            class="text-xs px-1.5 py-0.5 rounded text-white"
                            style={"background-color: #{label.color}"}
                          >
                            <%= label.name %>
                          </span>
                        <% end %>
                      </div>
                    <% end %>

                    <!-- Due date -->
                    <%= if task.due_date do %>
                      <div class={"text-xs mt-2 #{due_date_class(task.due_date)}"}>
                        <.icon name="hero-calendar" class="w-3 h-3 inline" />
                        <%= task.due_date %>
                        <%= if Date.compare(task.due_date, Date.utc_today()) == :lt do %>
                          <span class="text-error font-bold">(overdue)</span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <!-- Add Task -->
              <div class="p-2 border-t border-primary/20">
                <%= if @new_task_column_id == column.id do %>
                  <form phx-submit="create_task" class="space-y-2">
                    <input type="hidden" name="column_id" value={column.id} />
                    <input
                      type="text"
                      name="title"
                      placeholder="Directive description..."
                      class="input input-imperial input-sm w-full"
                      autofocus
                    />
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-imperial-primary btn-sm flex-1">Issue</button>
                      <button type="button" phx-click="cancel_new_task" class="btn btn-imperial btn-sm">Cancel</button>
                    </div>
                  </form>
                <% else %>
                  <button phx-click="show_new_task" phx-value-column-id={column.id} class="btn btn-ghost btn-sm w-full justify-start text-primary hover:bg-primary/10">
                    <.icon name="hero-plus" class="w-4 h-4" />
                    Issue Directive
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

              <!-- Add Column Button -->
              <div class="flex-shrink-0 w-80">
                <button phx-click="add_column" class="btn btn-imperial w-full justify-start">
                  <.icon name="hero-plus" class="w-4 h-4" />
                  Add Division
                </button>
              </div>
            </div>
          </div>

        <% :weekly -> %>
          <!-- Weekly View -->
          <.weekly_view
            current_week_start={@current_week_start}
            unscheduled_tasks={@unscheduled_tasks}
            weekly_tasks={@weekly_tasks}
          />

        <% :calendar -> %>
          <!-- Calendar View -->
          <.calendar_view
            current_month={@current_month}
            selected_day={@selected_day}
            monthly_tasks={@monthly_tasks}
            unscheduled_tasks={@unscheduled_tasks}
          />
      <% end %>

      <!-- Task Detail Modal -->
      <%= if @selected_task do %>
        <div class="modal modal-open">
          <div class="modal-box card-ornate border border-primary/50 max-w-2xl">
            <div class="flex justify-between items-center mb-4">
              <h3 class="panel-header mb-0 pb-0 border-0">Edit Directive</h3>
              <button phx-click="close_task_modal" class="btn btn-ghost btn-sm text-primary">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <form phx-submit="save_task" class="space-y-4">
              <!-- Title -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Directive</span></label>
                <input
                  type="text"
                  name="title"
                  value={@selected_task.title}
                  class="input input-imperial"
                  required
                />
              </div>

              <!-- Description -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Mission Details</span></label>
                <textarea
                  name="description"
                  class="textarea input-imperial h-24"
                  placeholder="Provide mission briefing..."
                ><%= @selected_task.description %></textarea>
              </div>

              <!-- Priority -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Priority Level</span></label>
                <div class="flex gap-2">
                  <%= for p <- 1..4 do %>
                    <label
                      class={"btn btn-sm cursor-pointer #{if @modal_priority == p, do: "btn-imperial-primary", else: "btn-imperial"}"}
                      phx-click="set_modal_priority"
                      phx-value-priority={p}
                    >
                      <input
                        type="radio"
                        name="priority"
                        value={p}
                        checked={@modal_priority == p}
                        class="hidden"
                      />
                      <span class={priority_color(p)}><%= priority_label(p) %></span>
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Due Date -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Deadline</span></label>
                <input
                  type="date"
                  name="due_date"
                  value={@selected_task.due_date}
                  class="input input-imperial w-full max-w-xs"
                />
              </div>

              <!-- Scheduling -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Schedule</span></label>
                <div class="flex flex-wrap gap-3">
                  <div>
                    <label class="text-xs text-base-content/60 block mb-1">Date</label>
                    <input
                      type="date"
                      name="schedule_date"
                      value={if @selected_task.event, do: DateTime.to_date(@selected_task.event.start_at)}
                      class="input input-imperial input-sm"
                    />
                  </div>
                  <div>
                    <label class="text-xs text-base-content/60 block mb-1">Start Time</label>
                    <input
                      type="time"
                      name="schedule_start_time"
                      value={if @selected_task.event, do: Calendar.strftime(@selected_task.event.start_at, "%H:%M")}
                      class="input input-imperial input-sm"
                    />
                  </div>
                  <div>
                    <label class="text-xs text-base-content/60 block mb-1">End Time</label>
                    <input
                      type="time"
                      name="schedule_end_time"
                      value={if @selected_task.event && @selected_task.event.end_at, do: Calendar.strftime(@selected_task.event.end_at, "%H:%M")}
                      class="input input-imperial input-sm"
                    />
                  </div>
                  <%= if @selected_task.event do %>
                    <div class="flex items-end">
                      <button
                        type="button"
                        phx-click="unschedule_task"
                        phx-value-task_id={@selected_task.id}
                        class="btn btn-imperial-danger btn-sm"
                      >
                        <.icon name="hero-x-mark" class="w-3 h-3" />
                        Clear
                      </button>
                    </div>
                  <% end %>
                </div>
                <p class="text-xs text-base-content/50 mt-1">Set date and time to schedule this directive on the calendar</p>
              </div>

              <!-- Labels -->
              <div class="form-control">
                <label class="label"><span class="stat-block-label">Insignias</span></label>
                <div class="flex flex-wrap gap-2">
                  <%= for label <- @labels do %>
                    <% has_label = Enum.any?(@selected_task.labels, & &1.id == label.id) %>
                    <button
                      type="button"
                      phx-click="toggle_task_label"
                      phx-value-task-id={@selected_task.id}
                      phx-value-label-id={label.id}
                      class={"px-3 py-1 rounded cursor-pointer border transition-colors #{if has_label, do: "text-white", else: "bg-transparent"}"}
                      style={if has_label, do: "background-color: #{label.color}; border-color: #{label.color}", else: "border-color: #{label.color}; color: #{label.color}"}
                    >
                      <%= if has_label do %>
                        <.icon name="hero-check" class="w-3 h-3 inline mr-1" />
                      <% end %>
                      <%= label.name %>
                    </button>
                  <% end %>
                  <%= if Enum.empty?(@labels) do %>
                    <span class="text-sm text-base-content/60 italic">No insignias available. Create insignias from the menu.</span>
                  <% end %>
                </div>
                <!-- Hidden field to track label IDs -->
                <input
                  type="hidden"
                  name="label_ids"
                  value={@selected_task.labels |> Enum.map(& &1.id) |> Enum.join(",")}
                />
              </div>

              <!-- Actions -->
              <div class="flex justify-between pt-4">
                <button
                  type="button"
                  phx-click="delete_task"
                  phx-value-id={@selected_task.id}
                  data-confirm="Rescind this directive permanently?"
                  class="btn btn-imperial-danger"
                >
                  Rescind
                </button>
                <div class="flex gap-2">
                  <button type="button" phx-click="close_task_modal" class="btn btn-imperial">Cancel</button>
                  <button type="submit" class="btn btn-imperial-primary">Confirm</button>
                </div>
              </div>
            </form>
          </div>
          <div class="modal-backdrop bg-base-300/80" phx-click="close_task_modal"></div>
        </div>
      <% end %>
    </div>
    """
  end
end
