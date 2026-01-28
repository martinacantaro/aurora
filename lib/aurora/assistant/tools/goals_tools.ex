defmodule Aurora.Assistant.Tools.GoalsTools do
  @moduledoc """
  Tool definitions and executors for goals.
  """

  alias Aurora.Goals

  def definitions do
    [
      %{
        name: "list_goals",
        description: "List all goals, optionally filtered by timeframe or category",
        input_schema: %{
          type: "object",
          properties: %{
            timeframe: %{
              type: "string",
              description: "Filter by timeframe",
              enum: ["daily", "weekly", "monthly", "quarterly", "yearly", "multi_year"]
            },
            category: %{
              type: "string",
              description: "Filter by category",
              enum: ["health", "career", "relationships", "finance", "personal_growth", "other"]
            }
          },
          required: []
        }
      },
      %{
        name: "get_goal",
        description: "Get a specific goal with its details and sub-goals",
        input_schema: %{
          type: "object",
          properties: %{
            goal_id: %{type: "integer", description: "The ID of the goal"}
          },
          required: ["goal_id"]
        }
      },
      %{
        name: "create_goal",
        description: "Create a new goal",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{type: "string", description: "Title of the goal"},
            description: %{type: "string", description: "Description of the goal"},
            timeframe: %{
              type: "string",
              description: "Timeframe for the goal",
              enum: ["daily", "weekly", "monthly", "quarterly", "yearly", "multi_year"]
            },
            category: %{
              type: "string",
              description: "Category of the goal",
              enum: ["health", "career", "relationships", "finance", "personal_growth", "other"]
            },
            parent_id: %{type: "integer", description: "Parent goal ID for sub-goals"}
          },
          required: ["title"]
        }
      },
      %{
        name: "update_goal",
        description: "Update an existing goal",
        input_schema: %{
          type: "object",
          properties: %{
            goal_id: %{type: "integer", description: "The goal to update"},
            title: %{type: "string", description: "New title"},
            description: %{type: "string", description: "New description"},
            progress: %{type: "integer", description: "Progress percentage (0-100)", minimum: 0, maximum: 100}
          },
          required: ["goal_id"]
        }
      },
      %{
        name: "delete_goal",
        description: "Delete a goal and its sub-goals. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            goal_id: %{type: "integer", description: "The goal to delete"}
          },
          required: ["goal_id"]
        }
      }
    ]
  end

  def execute("list_goals", args) do
    goals = cond do
      args["timeframe"] -> Goals.list_goals_by_timeframe(args["timeframe"])
      args["category"] -> Goals.list_goals_by_category(args["category"])
      true -> Goals.list_goals()
    end

    {:ok, format_goals(goals)}
  end

  def execute("get_goal", %{"goal_id" => id}) do
    try do
      goal = Goals.get_goal!(id)
      {:ok, format_goal_detail(goal)}
    rescue
      Ecto.NoResultsError -> {:error, "Goal not found with ID #{id}"}
    end
  end

  def execute("create_goal", args) do
    attrs = %{
      title: args["title"],
      description: args["description"],
      timeframe: args["timeframe"] || "monthly",
      category: args["category"],
      parent_id: args["parent_id"],
      progress: 0
    }

    case Goals.create_goal(attrs) do
      {:ok, goal} ->
        {:ok, %{id: goal.id, title: goal.title, message: "Goal '#{goal.title}' created"}}
      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("update_goal", %{"goal_id" => id} = args) do
    try do
      goal = Goals.get_goal!(id)

      attrs = args
        |> Map.drop(["goal_id"])
        |> Enum.reduce(%{}, fn {k, v}, acc ->
          Map.put(acc, String.to_existing_atom(k), v)
        end)

      case Goals.update_goal(goal, attrs) do
        {:ok, goal} ->
          {:ok, %{id: goal.id, message: "Goal updated successfully"}}
        {:error, changeset} ->
          {:error, format_errors(changeset)}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Goal not found with ID #{id}"}
    end
  end

  def execute("delete_goal", %{"goal_id" => id}) do
    try do
      goal = Goals.get_goal!(id)
      case Goals.delete_goal(goal) do
        {:ok, _} ->
          {:ok, %{message: "Goal '#{goal.title}' deleted"}}
        {:error, _} ->
          {:error, "Failed to delete goal"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Goal not found with ID #{id}"}
    end
  end

  defp format_goals(goals) do
    %{
      count: length(goals),
      goals: Enum.map(goals, fn g ->
        %{
          id: g.id,
          title: g.title,
          timeframe: g.timeframe,
          category: g.category,
          progress: g.progress,
          has_children: g.children && length(g.children) > 0
        }
      end)
    }
  end

  defp format_goal_detail(goal) do
    %{
      id: goal.id,
      title: goal.title,
      description: goal.description,
      timeframe: goal.timeframe,
      category: goal.category,
      progress: goal.progress,
      parent: if(goal.parent, do: %{id: goal.parent.id, title: goal.parent.title}, else: nil),
      children: Enum.map(goal.children || [], fn c ->
        %{id: c.id, title: c.title, progress: c.progress}
      end)
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
