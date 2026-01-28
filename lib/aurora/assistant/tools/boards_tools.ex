defmodule Aurora.Assistant.Tools.BoardsTools do
  @moduledoc """
  Tool definitions and executors for Kanban boards, columns, and tasks.
  """

  alias Aurora.Boards

  def definitions do
    [
      # Read operations
      %{
        name: "list_boards",
        description: "List all kanban boards",
        input_schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      %{
        name: "get_board",
        description: "Get a specific board with all its columns and tasks",
        input_schema: %{
          type: "object",
          properties: %{
            board_id: %{type: "integer", description: "The ID of the board to retrieve"}
          },
          required: ["board_id"]
        }
      },
      %{
        name: "list_tasks",
        description: "List all tasks in a specific column",
        input_schema: %{
          type: "object",
          properties: %{
            column_id: %{type: "integer", description: "The ID of the column"}
          },
          required: ["column_id"]
        }
      },

      # Create operations
      %{
        name: "create_board",
        description: "Create a new kanban board",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Name of the board"}
          },
          required: ["name"]
        }
      },
      %{
        name: "create_column",
        description: "Create a new column in a board",
        input_schema: %{
          type: "object",
          properties: %{
            board_id: %{type: "integer", description: "The board to add the column to"},
            name: %{type: "string", description: "Name of the column"}
          },
          required: ["board_id", "name"]
        }
      },
      %{
        name: "create_task",
        description: "Create a new task in a column",
        input_schema: %{
          type: "object",
          properties: %{
            column_id: %{type: "integer", description: "The column to add the task to"},
            title: %{type: "string", description: "Title of the task"},
            description: %{type: "string", description: "Optional description"},
            priority: %{
              type: "integer",
              description: "Priority 1-4 (1 is highest)",
              minimum: 1,
              maximum: 4
            },
            due_date: %{type: "string", format: "date", description: "Due date in YYYY-MM-DD format"}
          },
          required: ["column_id", "title"]
        }
      },

      # Update operations
      %{
        name: "update_task",
        description: "Update an existing task",
        input_schema: %{
          type: "object",
          properties: %{
            task_id: %{type: "integer", description: "The task to update"},
            title: %{type: "string", description: "New title"},
            description: %{type: "string", description: "New description"},
            priority: %{type: "integer", description: "New priority 1-4"},
            due_date: %{type: "string", format: "date", description: "New due date"}
          },
          required: ["task_id"]
        }
      },
      %{
        name: "move_task",
        description: "Move a task to a different column",
        input_schema: %{
          type: "object",
          properties: %{
            task_id: %{type: "integer", description: "The task to move"},
            column_id: %{type: "integer", description: "The destination column"},
            position: %{type: "integer", description: "Position in the column (0 is top)"}
          },
          required: ["task_id", "column_id"]
        }
      },

      # Delete operations
      %{
        name: "delete_task",
        description: "Delete a task permanently. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            task_id: %{type: "integer", description: "The task to delete"}
          },
          required: ["task_id"]
        }
      },
      %{
        name: "delete_column",
        description: "Delete a column and all its tasks. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            column_id: %{type: "integer", description: "The column to delete"}
          },
          required: ["column_id"]
        }
      },
      %{
        name: "delete_board",
        description: "Delete a board and all its contents. This action requires confirmation.",
        input_schema: %{
          type: "object",
          properties: %{
            board_id: %{type: "integer", description: "The board to delete"}
          },
          required: ["board_id"]
        }
      }
    ]
  end

  def execute("list_boards", _args) do
    boards = Boards.list_boards()
    {:ok, format_boards(boards)}
  end

  def execute("get_board", %{"board_id" => id}) do
    try do
      board = Boards.get_board!(id)
      {:ok, format_board_detail(board)}
    rescue
      Ecto.NoResultsError -> {:error, "Board not found with ID #{id}"}
    end
  end

  def execute("list_tasks", %{"column_id" => id}) do
    tasks = Boards.list_tasks(id)
    {:ok, format_tasks(tasks)}
  end

  def execute("create_board", %{"name" => name}) do
    case Boards.create_board(%{name: name, position: 0}) do
      {:ok, board} ->
        {:ok, %{id: board.id, name: board.name, message: "Board '#{name}' created successfully"}}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("create_column", %{"board_id" => board_id, "name" => name}) do
    case Boards.create_column(%{board_id: board_id, name: name, position: 0}) do
      {:ok, column} ->
        {:ok, %{id: column.id, name: column.name, message: "Column '#{name}' created"}}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("create_task", args) do
    attrs = %{
      column_id: args["column_id"],
      title: args["title"],
      description: args["description"],
      priority: args["priority"] || 4,
      due_date: parse_date(args["due_date"]),
      position: 0
    }

    case Boards.create_task(attrs) do
      {:ok, task} ->
        {:ok, %{id: task.id, title: task.title, message: "Task '#{task.title}' created"}}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def execute("update_task", %{"task_id" => id} = args) do
    try do
      task = Boards.get_task!(id)

      attrs =
        args
        |> Map.drop(["task_id"])
        |> Enum.reduce(%{}, fn {k, v}, acc ->
          key = String.to_existing_atom(k)
          value = if key == :due_date, do: parse_date(v), else: v
          Map.put(acc, key, value)
        end)

      case Boards.update_task(task, attrs) do
        {:ok, task} ->
          {:ok, %{id: task.id, message: "Task updated successfully"}}

        {:error, changeset} ->
          {:error, format_errors(changeset)}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Task not found with ID #{id}"}
    end
  end

  def execute("move_task", %{"task_id" => task_id, "column_id" => column_id} = args) do
    position = args["position"] || 0

    case Boards.move_task(task_id, column_id, position) do
      {:ok, _} ->
        {:ok, %{message: "Task moved successfully"}}

      {:error, reason} ->
        {:error, "Failed to move task: #{inspect(reason)}"}
    end
  end

  def execute("delete_task", %{"task_id" => id}) do
    try do
      task = Boards.get_task!(id)

      case Boards.delete_task(task) do
        {:ok, _} ->
          {:ok, %{message: "Task '#{task.title}' deleted"}}

        {:error, _} ->
          {:error, "Failed to delete task"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Task not found with ID #{id}"}
    end
  end

  def execute("delete_column", %{"column_id" => id}) do
    try do
      column = Boards.get_column!(id)

      case Boards.delete_column(column) do
        {:ok, _} ->
          {:ok, %{message: "Column '#{column.name}' deleted"}}

        {:error, _} ->
          {:error, "Failed to delete column"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Column not found with ID #{id}"}
    end
  end

  def execute("delete_board", %{"board_id" => id}) do
    try do
      board = Boards.get_board!(id)

      case Boards.delete_board(board) do
        {:ok, _} ->
          {:ok, %{message: "Board '#{board.name}' deleted"}}

        {:error, _} ->
          {:error, "Failed to delete board"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Board not found with ID #{id}"}
    end
  end

  # Formatters

  defp format_boards(boards) do
    %{
      count: length(boards),
      boards: Enum.map(boards, fn b -> %{id: b.id, name: b.name} end)
    }
  end

  defp format_board_detail(board) do
    %{
      id: board.id,
      name: board.name,
      columns:
        Enum.map(board.columns, fn col ->
          %{
            id: col.id,
            name: col.name,
            task_count: length(col.tasks),
            tasks:
              Enum.map(col.tasks, fn task ->
                %{
                  id: task.id,
                  title: task.title,
                  priority: task.priority,
                  due_date: task.due_date
                }
              end)
          }
        end)
    }
  end

  defp format_tasks(tasks) do
    %{
      count: length(tasks),
      tasks:
        Enum.map(tasks, fn t ->
          %{
            id: t.id,
            title: t.title,
            description: t.description,
            priority: t.priority,
            due_date: t.due_date
          }
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

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
