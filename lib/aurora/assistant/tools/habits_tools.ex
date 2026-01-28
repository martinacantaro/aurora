defmodule Aurora.Assistant.Tools.HabitsTools do
  @moduledoc """
  Tool definitions and executors for habits.
  """

  alias Aurora.Habits

  def definitions do
    [
      %{
        name: "list_habits",
        description: "List all habits with today's completion status and streaks",
        input_schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      %{
        name: "get_habit",
        description: "Get a specific habit with its details and completion history",
        input_schema: %{
          type: "object",
          properties: %{
            habit_id: %{type: "integer", description: "The ID of the habit"}
          },
          required: ["habit_id"]
        }
      },
      %{
        name: "create_habit",
        description: "Create a new habit to track",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Name of the habit"},
            description: %{type: "string", description: "Description of the habit"},
            schedule_type: %{
              type: "string",
              description: "How often to track",
              enum: ["daily", "weekly", "specific_days", "every_n_days"]
            },
            time_of_day: %{
              type: "string",
              description: "Suggested time to complete",
              enum: ["morning", "afternoon", "evening", "anytime"]
            }
          },
          required: ["name"]
        }
      },
      %{
        name: "toggle_habit_today",
        description: "Toggle a habit's completion status for today",
        input_schema: %{
          type: "object",
          properties: %{
            habit_id: %{type: "integer", description: "The habit to toggle"}
          },
          required: ["habit_id"]
        }
      },
      %{
        name: "update_habit",
        description: "Update an existing habit",
        input_schema: %{
          type: "object",
          properties: %{
            habit_id: %{type: "integer", description: "The habit to update"},
            name: %{type: "string", description: "New name"},
            description: %{type: "string", description: "New description"}
          },
          required: ["habit_id"]
        }
      },
      %{
        name: "delete_habit",
        description: "Delete a habit and its history. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            habit_id: %{type: "integer", description: "The habit to delete"}
          },
          required: ["habit_id"]
        }
      }
    ]
  end

  def execute("list_habits", _args) do
    habits = Habits.list_habits_with_today_status()
    {:ok, format_habits(habits)}
  end

  def execute("get_habit", %{"habit_id" => id}) do
    try do
      habit = Habits.get_habit!(id)
      completion_rate = Habits.get_completion_rate(id, 30)
      {:ok, format_habit_detail(habit, completion_rate)}
    rescue
      Ecto.NoResultsError -> {:error, "Habit not found with ID #{id}"}
    end
  end

  def execute("create_habit", args) do
    attrs = %{
      name: args["name"],
      description: args["description"],
      schedule_type: args["schedule_type"] || "daily",
      time_of_day: args["time_of_day"] || "anytime"
    }

    case Habits.create_habit(attrs) do
      {:ok, habit} ->
        {:ok, %{id: habit.id, name: habit.name, message: "Habit '#{habit.name}' created"}}
      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("toggle_habit_today", %{"habit_id" => id}) do
    try do
      habit = Habits.get_habit!(id)
      case Habits.toggle_habit_today(habit) do
        {:ok, :completed} ->
          {:ok, %{message: "Habit '#{habit.name}' marked as complete for today"}}
        {:ok, :uncompleted} ->
          {:ok, %{message: "Habit '#{habit.name}' marked as incomplete for today"}}
        {:error, _} ->
          {:error, "Failed to toggle habit"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Habit not found with ID #{id}"}
    end
  end

  def execute("update_habit", %{"habit_id" => id} = args) do
    try do
      habit = Habits.get_habit!(id)
      attrs = args
        |> Map.drop(["habit_id"])
        |> Enum.reduce(%{}, fn {k, v}, acc ->
          Map.put(acc, String.to_existing_atom(k), v)
        end)

      case Habits.update_habit(habit, attrs) do
        {:ok, habit} ->
          {:ok, %{id: habit.id, message: "Habit updated successfully"}}
        {:error, changeset} ->
          {:error, format_errors(changeset)}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Habit not found with ID #{id}"}
    end
  end

  def execute("delete_habit", %{"habit_id" => id}) do
    try do
      habit = Habits.get_habit!(id)
      case Habits.delete_habit(habit) do
        {:ok, _} ->
          {:ok, %{message: "Habit '#{habit.name}' deleted"}}
        {:error, _} ->
          {:error, "Failed to delete habit"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Habit not found with ID #{id}"}
    end
  end

  defp format_habits(habits) do
    completed = Enum.count(habits, & &1.completed_today)
    %{
      total: length(habits),
      completed_today: completed,
      habits: Enum.map(habits, fn h ->
        %{
          id: h.habit.id,
          name: h.habit.name,
          completed_today: h.completed_today,
          streak: h.streak,
          time_of_day: h.habit.time_of_day
        }
      end)
    }
  end

  defp format_habit_detail(habit, completion_rate) do
    %{
      id: habit.id,
      name: habit.name,
      description: habit.description,
      schedule_type: habit.schedule_type,
      time_of_day: habit.time_of_day,
      completion_rate_30d: completion_rate
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
