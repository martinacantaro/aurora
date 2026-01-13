defmodule Aurora.Boards do
  @moduledoc """
  The Boards context for managing Kanban boards, columns, and tasks.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Boards.{Board, Column, Task, Label}

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
    |> Repo.preload(:labels)
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
