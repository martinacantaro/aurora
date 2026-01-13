defmodule AuroraWeb.HabitLive.Index do
  use AuroraWeb, :live_view

  alias Aurora.Habits
  alias Aurora.Habits.Habit

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Habits")
     |> assign(:editing_habit, nil)
     |> assign(:show_new_form, false)
     |> load_habits()}
  end

  defp load_habits(socket) do
    assign(socket, :habits, Habits.list_habits_with_today_status())
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    habit_id = String.to_integer(id)

    case Habits.toggle_habit_today(habit_id) do
      {:ok, _completed} ->
        {:noreply, load_habits(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle habit")}
    end
  end

  def handle_event("show_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, true)}
  end

  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, false)}
  end

  def handle_event("create", %{"habit" => habit_params}, socket) do
    case Habits.create_habit(habit_params) do
      {:ok, _habit} ->
        {:noreply,
         socket
         |> assign(:show_new_form, false)
         |> load_habits()
         |> put_flash(:info, "Habit created!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create habit")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_habit, String.to_integer(id))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_habit, nil)}
  end

  def handle_event("update", %{"habit" => habit_params} = params, socket) do
    id = params["value"]["id"] || params["id"]
    habit = Habits.get_habit!(id)

    case Habits.update_habit(habit, habit_params) do
      {:ok, _habit} ->
        {:noreply,
         socket
         |> assign(:editing_habit, nil)
         |> load_habits()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update habit")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    habit = Habits.get_habit!(id)

    case Habits.delete_habit(habit) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_habits()
         |> put_flash(:info, "Habit deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete habit")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </.link>
          <h1 class="text-3xl font-bold">Habits</h1>
        </div>
        <button phx-click="show_new" class="btn btn-primary">
          <.icon name="hero-plus" class="w-4 h-4" />
          New Habit
        </button>
      </div>

      <!-- New Habit Form -->
      <%= if @show_new_form do %>
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">New Habit</h2>
            <form phx-submit="create" class="space-y-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name</span></label>
                <input type="text" name="habit[name]" class="input input-bordered" required autofocus />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Description (optional)</span></label>
                <textarea name="habit[description]" class="textarea textarea-bordered" rows="2"></textarea>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Schedule</span></label>
                  <select name="habit[schedule_type]" class="select select-bordered">
                    <option value="daily">Daily</option>
                    <option value="weekly">Weekly</option>
                    <option value="specific_days">Specific Days</option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Time of Day</span></label>
                  <select name="habit[time_of_day]" class="select select-bordered">
                    <option value="anytime">Anytime</option>
                    <option value="morning">Morning</option>
                    <option value="afternoon">Afternoon</option>
                    <option value="evening">Evening</option>
                  </select>
                </div>
              </div>
              <div class="flex gap-2 justify-end">
                <button type="button" phx-click="cancel_new" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">Create Habit</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Habits List -->
      <div class="space-y-4">
        <%= if Enum.empty?(@habits) do %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body text-center">
              <p class="text-base-content/60">No habits yet. Create your first habit to start tracking!</p>
            </div>
          </div>
        <% else %>
          <%= for %{habit: habit, completed_today: completed?, streak: streak} <- @habits do %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body p-4">
                <%= if @editing_habit == habit.id do %>
                  <form phx-submit="update" phx-value-id={habit.id} class="space-y-4">
                    <div class="form-control">
                      <input type="text" name="habit[name]" value={habit.name} class="input input-bordered" required autofocus />
                    </div>
                    <div class="form-control">
                      <textarea name="habit[description]" class="textarea textarea-bordered" rows="2"><%= habit.description %></textarea>
                    </div>
                    <div class="flex gap-2 justify-end">
                      <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">Cancel</button>
                      <button type="submit" class="btn btn-primary btn-sm">Save</button>
                    </div>
                  </form>
                <% else %>
                  <div class="flex items-center gap-4">
                    <!-- Checkbox -->
                    <button
                      phx-click="toggle"
                      phx-value-id={habit.id}
                      class={"btn btn-circle btn-lg #{if completed?, do: "btn-success", else: "btn-outline"}"}
                    >
                      <%= if completed? do %>
                        <.icon name="hero-check" class="w-6 h-6" />
                      <% end %>
                    </button>

                    <!-- Habit Info -->
                    <div class="flex-1">
                      <h3 class={"text-lg font-semibold #{if completed?, do: "line-through text-base-content/60"}"}><%= habit.name %></h3>
                      <%= if habit.description do %>
                        <p class="text-sm text-base-content/60"><%= habit.description %></p>
                      <% end %>
                      <div class="flex gap-4 mt-1 text-xs text-base-content/50">
                        <span>
                          <.icon name="hero-clock" class="w-3 h-3 inline" />
                          <%= String.capitalize(habit.time_of_day) %>
                        </span>
                        <span>
                          <.icon name="hero-calendar" class="w-3 h-3 inline" />
                          <%= String.capitalize(habit.schedule_type) %>
                        </span>
                      </div>
                    </div>

                    <!-- Streak Badge -->
                    <%= if streak > 0 do %>
                      <div class="badge badge-lg badge-primary gap-1">
                        <.icon name="hero-fire" class="w-4 h-4" />
                        <%= streak %> day<%= if streak > 1, do: "s" %>
                      </div>
                    <% end %>

                    <!-- Actions -->
                    <div class="dropdown dropdown-end">
                      <label tabindex="0" class="btn btn-ghost btn-sm btn-square">
                        <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
                      </label>
                      <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow bg-base-100 rounded-box w-40">
                        <li><a phx-click="edit" phx-value-id={habit.id}>Edit</a></li>
                        <li>
                          <a phx-click="delete" phx-value-id={habit.id} data-confirm="Delete this habit?" class="text-error">
                            Delete
                          </a>
                        </li>
                      </ul>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
