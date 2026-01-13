defmodule AuroraWeb.BoardLive.Show do
  use AuroraWeb, :live_view

  alias Aurora.Boards

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    board = Boards.get_board!(id)
    labels = Boards.list_labels()

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
     |> assign(:show_labels_menu, false)
     # Filters
     |> assign(:search_query, "")
     |> assign(:filter_labels, [])
     |> assign(:filter_priority, nil)
     |> assign(:filter_due_date, nil)
     |> assign(:show_filter_labels, false)
     |> assign(:show_filter_priority, false)
     |> assign(:show_filter_due, false)}
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
    assign(socket, board: board, columns: board.columns, labels: labels)
  end

  # Task modal events
  def handle_event("open_task", %{"id" => id}, socket) do
    task = Boards.get_task!(id)
    {:noreply, assign(socket, :selected_task, task)}
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
      {:ok, _task} ->
        # Update labels if provided
        if params["label_ids"] do
          label_ids = params["label_ids"]
            |> String.split(",")
            |> Enum.map(&String.to_integer/1)
            |> Enum.reject(&(&1 == 0))
          Boards.set_task_labels(task.id, label_ids)
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <!-- Header -->
      <div class="navbar bg-base-100 shadow-sm px-4">
        <div class="flex-1 gap-4">
          <.link navigate={~p"/boards"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </.link>
          <h1 class="text-xl font-bold"><%= @board.name %></h1>
        </div>
        <div class="flex-none gap-2">
          <!-- Labels Management -->
          <div class="dropdown dropdown-end">
            <label tabindex="0" phx-click="toggle_labels_menu" class="btn btn-ghost btn-sm">
              <.icon name="hero-tag" class="w-4 h-4" />
              Labels
            </label>
            <%= if @show_labels_menu do %>
              <div tabindex="0" class="dropdown-content z-50 p-4 shadow bg-base-100 rounded-box w-72">
                <h3 class="font-semibold mb-3">Manage Labels</h3>

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
                    <p class="text-sm text-base-content/60">No labels yet</p>
                  <% end %>
                </div>

                <!-- New Label Form -->
                <form phx-submit="create_label" class="space-y-2">
                  <div class="flex gap-2">
                    <input type="text" name="name" placeholder="Label name" class="input input-sm input-bordered flex-1" required />
                    <input type="color" name="color" value="#3b82f6" class="w-10 h-8 rounded cursor-pointer" />
                  </div>
                  <button type="submit" class="btn btn-primary btn-sm w-full">Add Label</button>
                </form>
              </div>
            <% end %>
          </div>
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">Dashboard</.link>
        </div>
      </div>

      <!-- Filter Bar -->
      <div class="bg-base-100 px-4 py-2 flex items-center gap-2 border-b border-base-200">
        <!-- Search -->
        <div class="form-control">
          <div class="input-group input-group-sm">
            <span class="bg-base-200"><.icon name="hero-magnifying-glass" class="w-4 h-4" /></span>
            <input
              type="text"
              placeholder="Search tasks..."
              value={@search_query}
              phx-keyup="search"
              phx-value-query={@search_query}
              phx-debounce="300"
              name="query"
              class="input input-sm input-bordered w-48"
            />
          </div>
        </div>

        <!-- Label Filter -->
        <div class="dropdown">
          <label tabindex="0" phx-click="toggle_filter_labels" class={"btn btn-sm #{if @filter_labels != [], do: "btn-primary", else: "btn-ghost"}"}>
            <.icon name="hero-tag" class="w-4 h-4" />
            Labels
            <%= if @filter_labels != [] do %>
              <span class="badge badge-sm"><%= length(@filter_labels) %></span>
            <% end %>
          </label>
          <%= if @show_filter_labels do %>
            <div tabindex="0" class="dropdown-content z-50 p-3 shadow bg-base-100 rounded-box w-56">
              <div class="space-y-2">
                <%= for label <- @labels do %>
                  <label class="flex items-center gap-2 cursor-pointer hover:bg-base-200 p-1 rounded">
                    <input
                      type="checkbox"
                      checked={label.id in @filter_labels}
                      phx-click="toggle_label_filter"
                      phx-value-id={label.id}
                      class="checkbox checkbox-sm"
                    />
                    <span class="w-3 h-3 rounded" style={"background-color: #{label.color}"}></span>
                    <span class="text-sm"><%= label.name %></span>
                  </label>
                <% end %>
                <%= if Enum.empty?(@labels) do %>
                  <p class="text-sm text-base-content/60">No labels</p>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Priority Filter -->
        <div class="dropdown">
          <label tabindex="0" phx-click="toggle_filter_priority" class={"btn btn-sm #{if @filter_priority, do: "btn-primary", else: "btn-ghost"}"}>
            <.icon name="hero-flag" class="w-4 h-4" />
            Priority
            <%= if @filter_priority do %>
              <span class="badge badge-sm"><%= priority_label(@filter_priority) %></span>
            <% end %>
          </label>
          <%= if @show_filter_priority do %>
            <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow bg-base-100 rounded-box w-40">
              <li><a phx-click="set_priority_filter" phx-value-priority="" class={if @filter_priority == nil, do: "active"}>All</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="1" class={"text-error #{if @filter_priority == 1, do: "active"}"}>P1 - Critical</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="2" class={"text-warning #{if @filter_priority == 2, do: "active"}"}>P2 - High</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="3" class={"text-info #{if @filter_priority == 3, do: "active"}"}>P3 - Medium</a></li>
              <li><a phx-click="set_priority_filter" phx-value-priority="4" class={if @filter_priority == 4, do: "active"}>P4 - Low</a></li>
            </ul>
          <% end %>
        </div>

        <!-- Due Date Filter -->
        <div class="dropdown">
          <label tabindex="0" phx-click="toggle_filter_due" class={"btn btn-sm #{if @filter_due_date, do: "btn-primary", else: "btn-ghost"}"}>
            <.icon name="hero-calendar" class="w-4 h-4" />
            Due
            <%= if @filter_due_date do %>
              <span class="badge badge-sm"><%= @filter_due_date %></span>
            <% end %>
          </label>
          <%= if @show_filter_due do %>
            <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow bg-base-100 rounded-box w-40">
              <li><a phx-click="set_due_date_filter" phx-value-due="" class={if @filter_due_date == nil, do: "active"}>All</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="overdue" class={"text-error #{if @filter_due_date == "overdue", do: "active"}"}>Overdue</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="today" class={"text-warning #{if @filter_due_date == "today", do: "active"}"}>Today</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="week" class={if @filter_due_date == "week", do: "active"}>This Week</a></li>
              <li><a phx-click="set_due_date_filter" phx-value-due="none" class={if @filter_due_date == "none", do: "active"}>No Date</a></li>
            </ul>
          <% end %>
        </div>

        <!-- Clear Filters -->
        <%= if has_active_filters?(assigns) do %>
          <button phx-click="clear_filters" class="btn btn-ghost btn-sm text-error">
            <.icon name="hero-x-mark" class="w-4 h-4" />
            Clear
          </button>
        <% end %>
      </div>

      <!-- Kanban Board -->
      <div class="flex-1 overflow-x-auto p-4 bg-base-200">
        <div
          class="flex gap-4 h-full"
          id="columns-container"
          phx-hook="Sortable"
          data-group="columns"
        >
          <!-- Columns -->
          <%= for column <- @columns do %>
            <div
              class="flex-shrink-0 w-80 bg-base-100 rounded-lg shadow-md flex flex-col max-h-full"
              id={"column-#{column.id}"}
              data-id={column.id}
            >
              <!-- Column Header -->
              <div class="p-3 border-b border-base-200 flex items-center justify-between">
                <%= if @editing_column == column.id do %>
                  <form phx-submit="update_column" phx-value-id={column.id} class="flex-1 flex gap-2">
                    <input
                      type="text"
                      name="name"
                      value={column.name}
                      class="input input-sm input-bordered flex-1"
                      autofocus
                    />
                    <button type="submit" class="btn btn-ghost btn-sm btn-square">
                      <.icon name="hero-check" class="w-4 h-4" />
                    </button>
                    <button type="button" phx-click="cancel_edit_column" class="btn btn-ghost btn-sm btn-square">
                      <.icon name="hero-x-mark" class="w-4 h-4" />
                    </button>
                  </form>
                <% else %>
                  <% filtered_count = length(filter_tasks(column.tasks, assigns)) %>
                  <% total_count = length(column.tasks) %>
                  <h3 class="font-semibold flex-1">
                    <%= column.name %>
                    <span class="badge badge-sm ml-2">
                      <%= if filtered_count != total_count do %>
                        <%= filtered_count %>/<%= total_count %>
                      <% else %>
                        <%= total_count %>
                      <% end %>
                    </span>
                  </h3>
                  <div class="dropdown dropdown-end">
                    <label tabindex="0" class="btn btn-ghost btn-sm btn-square">
                      <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
                    </label>
                    <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow bg-base-100 rounded-box w-40">
                      <li><a phx-click="edit_column" phx-value-id={column.id}>Rename</a></li>
                      <li>
                        <a phx-click="delete_column" phx-value-id={column.id} data-confirm="Delete this column and all its tasks?">
                          Delete
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
                    class="card bg-base-200 shadow-sm cursor-move hover:shadow-md transition-shadow"
                    id={"task-#{task.id}"}
                    data-id={task.id}
                  >
                    <div class="card-body p-3">
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
                          <button phx-click="delete_task" phx-value-id={task.id} data-confirm="Delete this task?" class="btn btn-ghost btn-xs btn-square text-error">
                            <.icon name="hero-trash" class="w-3 h-3" />
                          </button>
                        </div>
                      </div>

                      <!-- Labels -->
                      <%= if task.labels != [] do %>
                        <div class="flex flex-wrap gap-1 mt-2">
                          <%= for label <- task.labels do %>
                            <span
                              class="badge badge-sm text-white"
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
                            <span class="text-error">(overdue)</span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Add Task -->
              <div class="p-2 border-t border-base-200">
                <%= if @new_task_column_id == column.id do %>
                  <form phx-submit="create_task" class="space-y-2">
                    <input type="hidden" name="column_id" value={column.id} />
                    <input
                      type="text"
                      name="title"
                      placeholder="Task title..."
                      class="input input-sm input-bordered w-full"
                      autofocus
                    />
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary btn-sm flex-1">Add</button>
                      <button type="button" phx-click="cancel_new_task" class="btn btn-ghost btn-sm">Cancel</button>
                    </div>
                  </form>
                <% else %>
                  <button phx-click="show_new_task" phx-value-column-id={column.id} class="btn btn-ghost btn-sm w-full justify-start">
                    <.icon name="hero-plus" class="w-4 h-4" />
                    Add task
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Add Column Button -->
          <div class="flex-shrink-0 w-80">
            <button phx-click="add_column" class="btn btn-ghost w-full justify-start">
              <.icon name="hero-plus" class="w-4 h-4" />
              Add Column
            </button>
          </div>
        </div>
      </div>

      <!-- Task Detail Modal -->
      <%= if @selected_task do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-2xl">
            <div class="flex justify-between items-center mb-4">
              <h3 class="font-bold text-lg">Edit Task</h3>
              <button phx-click="close_task_modal" class="btn btn-ghost btn-sm btn-circle">
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <form phx-submit="save_task" class="space-y-4">
              <!-- Title -->
              <div class="form-control">
                <label class="label"><span class="label-text font-semibold">Title</span></label>
                <input
                  type="text"
                  name="title"
                  value={@selected_task.title}
                  class="input input-bordered"
                  required
                />
              </div>

              <!-- Description -->
              <div class="form-control">
                <label class="label"><span class="label-text font-semibold">Description</span></label>
                <textarea
                  name="description"
                  class="textarea textarea-bordered h-24"
                  placeholder="Add a description..."
                ><%= @selected_task.description %></textarea>
              </div>

              <!-- Priority -->
              <div class="form-control">
                <label class="label"><span class="label-text font-semibold">Priority</span></label>
                <div class="flex gap-2">
                  <%= for p <- 1..4 do %>
                    <label class={"btn btn-sm #{if @selected_task.priority == p, do: "btn-primary", else: "btn-outline"}"}>
                      <input
                        type="radio"
                        name="priority"
                        value={p}
                        checked={@selected_task.priority == p}
                        class="hidden"
                      />
                      <span class={priority_color(p)}><%= priority_label(p) %></span>
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Due Date -->
              <div class="form-control">
                <label class="label"><span class="label-text font-semibold">Due Date</span></label>
                <input
                  type="date"
                  name="due_date"
                  value={@selected_task.due_date}
                  class="input input-bordered w-full max-w-xs"
                />
              </div>

              <!-- Labels -->
              <div class="form-control">
                <label class="label"><span class="label-text font-semibold">Labels</span></label>
                <div class="flex flex-wrap gap-2">
                  <%= for label <- @labels do %>
                    <% has_label = Enum.any?(@selected_task.labels, & &1.id == label.id) %>
                    <button
                      type="button"
                      phx-click="toggle_task_label"
                      phx-value-task-id={@selected_task.id}
                      phx-value-label-id={label.id}
                      class={"badge badge-lg cursor-pointer #{if has_label, do: "text-white", else: "badge-outline"}"}
                      style={if has_label, do: "background-color: #{label.color}; border-color: #{label.color}", else: "border-color: #{label.color}; color: #{label.color}"}
                    >
                      <%= if has_label do %>
                        <.icon name="hero-check" class="w-3 h-3 mr-1" />
                      <% end %>
                      <%= label.name %>
                    </button>
                  <% end %>
                  <%= if Enum.empty?(@labels) do %>
                    <span class="text-sm text-base-content/60">No labels available. Create labels from the Labels menu.</span>
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
              <div class="modal-action">
                <button
                  type="button"
                  phx-click="delete_task"
                  phx-value-id={@selected_task.id}
                  data-confirm="Are you sure you want to delete this task?"
                  class="btn btn-error btn-outline mr-auto"
                >
                  Delete
                </button>
                <button type="button" phx-click="close_task_modal" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">Save</button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="close_task_modal"></div>
        </div>
      <% end %>
    </div>
    """
  end
end
