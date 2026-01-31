defmodule Aurora.Boards do
  @moduledoc """
  The Boards context for managing Kanban boards, columns, and tasks.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Boards.{Board, Column, Task, Label}
  alias Aurora.Calendar
  alias Aurora.Calendar.Event

  # ============================================================================
  # Boards
  # ============================================================================

  def list_boards do
    Board
    |> order_by(asc: :position)
    |> Repo.all()
  end

  def get_board!(id) do
    Board
    |> Repo.get!(id)
    |> Repo.preload(columns: [tasks: [:labels]])
  end

  def create_board(attrs \\ %{}) do
    %Board{}
    |> Board.changeset(attrs)
    |> Repo.insert()
  end

  def update_board(%Board{} = board, attrs) do
    board
    |> Board.changeset(attrs)
    |> Repo.update()
  end

  def delete_board(%Board{} = board) do
    Repo.delete(board)
  end

  def change_board(%Board{} = board, attrs \\ %{}) do
    Board.changeset(board, attrs)
  end

  # ============================================================================
  # Columns
  # ============================================================================

  def list_columns(board_id) do
    Column
    |> where(board_id: ^board_id)
    |> order_by(asc: :position)
    |> Repo.all()
    |> Repo.preload(tasks: {from(t in Task, order_by: [asc: t.position]), [:labels]})
  end

  def get_column!(id) do
    Repo.get!(Column, id)
  end

  def create_column(attrs \\ %{}) do
    %Column{}
    |> Column.changeset(attrs)
    |> Repo.insert()
  end

  def update_column(%Column{} = column, attrs) do
    column
    |> Column.changeset(attrs)
    |> Repo.update()
  end

  def delete_column(%Column{} = column) do
    Repo.delete(column)
  end

  def change_column(%Column{} = column, attrs \\ %{}) do
    Column.changeset(column, attrs)
  end

  def reorder_columns(board_id, column_ids) do
    Repo.transaction(fn ->
      column_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        from(c in Column, where: c.id == ^id and c.board_id == ^board_id)
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  # ============================================================================
  # Tasks
  # ============================================================================

  def list_tasks(column_id) do
    Task
    |> where(column_id: ^column_id)
    |> order_by(asc: :position)
    |> Repo.all()
  end

  def get_task!(id) do
    Task
    |> Repo.get!(id)
    |> Repo.preload([:labels, :event])
  end

  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  @doc """
  Toggle the completed status of a task.
  """
  def toggle_task_completed(task_id) do
    task = get_task!(task_id)
    new_completed = !task.completed
    completed_at = if new_completed, do: DateTime.utc_now() |> DateTime.truncate(:second), else: nil

    update_task(task, %{completed: new_completed, completed_at: completed_at})
  end

  def move_task(task_id, new_column_id, new_position) do
    Repo.transaction(fn ->
      task = get_task!(task_id)
      old_column_id = task.column_id

      # Update positions in old column
      if old_column_id != new_column_id do
        from(t in Task, where: t.column_id == ^old_column_id and t.position > ^task.position)
        |> Repo.update_all(inc: [position: -1])
      end

      # Make room in new column
      from(t in Task, where: t.column_id == ^new_column_id and t.position >= ^new_position)
      |> Repo.update_all(inc: [position: 1])

      # Update the task
      task
      |> Task.changeset(%{column_id: new_column_id, position: new_position})
      |> Repo.update!()
    end)
  end

  def reorder_tasks(column_id, task_ids) do
    Repo.transaction(fn ->
      task_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        from(t in Task, where: t.id == ^id and t.column_id == ^column_id)
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  # ============================================================================
  # Task Scheduling
  # ============================================================================

  @doc """
  Schedule a task by creating/updating a linked calendar event.
  """
  def schedule_task(task_id, start_at, end_at \\ nil) do
    task = get_task!(task_id)

    end_at = end_at || DateTime.add(start_at, 3600, :second)

    Repo.transaction(fn ->
      event_attrs = %{
        title: task.title,
        start_at: start_at,
        end_at: end_at,
        task_id: task.id,
        color: "#c9a227"
      }

      case task.event do
        nil ->
          {:ok, event} = Calendar.create_event(event_attrs)
          update_task(task, %{event_id: event.id})

        existing_event ->
          Calendar.update_event(existing_event, %{start_at: start_at, end_at: end_at})
      end

      get_task!(task_id)
    end)
  end

  @doc """
  Unschedule a task by removing the event link and deleting the event.
  """
  def unschedule_task(task_id) do
    task = get_task!(task_id)

    Repo.transaction(fn ->
      if task.event do
        update_task(task, %{event_id: nil})
        Calendar.delete_event(task.event)
      end

      get_task!(task_id)
    end)
  end

  @doc """
  List unscheduled tasks for a board (tasks without linked events).
  """
  def list_unscheduled_tasks(board_id) do
    from(t in Task,
      join: c in Column,
      on: t.column_id == c.id,
      where: c.board_id == ^board_id and is_nil(t.event_id),
      order_by: [asc: t.position],
      preload: [:labels, :event, :column]
    )
    |> Repo.all()
  end

  @doc """
  List scheduled tasks for a board within a date range.
  """
  def list_scheduled_tasks_for_range(board_id, start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    from(t in Task,
      join: c in Column,
      on: t.column_id == c.id,
      join: e in Event,
      on: t.event_id == e.id,
      where: c.board_id == ^board_id,
      where: e.start_at >= ^start_dt and e.start_at <= ^end_dt,
      order_by: [asc: e.start_at],
      preload: [:labels, :event, :column]
    )
    |> Repo.all()
  end

  @doc """
  Get all tasks for a board with their scheduling info.
  """
  def list_all_tasks_for_board(board_id) do
    from(t in Task,
      join: c in Column,
      on: t.column_id == c.id,
      where: c.board_id == ^board_id,
      order_by: [asc: t.position],
      preload: [:labels, :event, :column]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Labels
  # ============================================================================

  def list_labels do
    Repo.all(Label)
  end

  def get_label!(id) do
    Repo.get!(Label, id)
  end

  def create_label(attrs \\ %{}) do
    %Label{}
    |> Label.changeset(attrs)
    |> Repo.insert()
  end

  def update_label(%Label{} = label, attrs) do
    label
    |> Label.changeset(attrs)
    |> Repo.update()
  end

  def delete_label(%Label{} = label) do
    Repo.delete(label)
  end

  def change_label(%Label{} = label, attrs \\ %{}) do
    Label.changeset(label, attrs)
  end

  # ============================================================================
  # Task-Label Associations
  # ============================================================================

  @doc """
  Sets the labels for a task, replacing any existing labels.
  """
  def set_task_labels(task_id, label_ids) when is_list(label_ids) do
    task = get_task!(task_id)
    labels = Repo.all(from(l in Label, where: l.id in ^label_ids))

    task
    |> Repo.preload(:labels)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:labels, labels)
    |> Repo.update()
  end

  @doc """
  Adds a label to a task.
  """
  def add_label_to_task(task_id, label_id) do
    task = get_task!(task_id)
    _label = get_label!(label_id)  # Verify label exists

    existing_label_ids = Enum.map(task.labels, & &1.id)

    unless label_id in existing_label_ids do
      set_task_labels(task_id, [label_id | existing_label_ids])
    else
      {:ok, task}
    end
  end

  @doc """
  Removes a label from a task.
  """
  def remove_label_from_task(task_id, label_id) do
    task = get_task!(task_id)
    new_label_ids = task.labels |> Enum.map(& &1.id) |> Enum.reject(&(&1 == label_id))
    set_task_labels(task_id, new_label_ids)
  end
end
