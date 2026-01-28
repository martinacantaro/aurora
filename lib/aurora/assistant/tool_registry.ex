defmodule Aurora.Assistant.ToolRegistry do
  @moduledoc """
  Central registry of all tools available to the AI assistant.
  Tools are defined using Claude's tool format.
  """

  alias Aurora.Assistant.Tools.{
    BoardsTools,
    GoalsTools,
    HabitsTools,
    JournalTools,
    FinanceTools,
    CalendarTools,
    AnalyticsTools
  }

  @doc """
  Returns all tool definitions for the Claude API.
  """
  def all_tools do
    [
      BoardsTools.definitions(),
      GoalsTools.definitions(),
      HabitsTools.definitions(),
      JournalTools.definitions(),
      FinanceTools.definitions(),
      CalendarTools.definitions(),
      AnalyticsTools.definitions()
    ]
    |> List.flatten()
  end

  @doc """
  Returns tools that require user confirmation before execution.
  """
  def destructive_tools do
    MapSet.new([
      "delete_board",
      "delete_column",
      "delete_task",
      "delete_goal",
      "delete_habit",
      "delete_journal_entry",
      "delete_transaction",
      "delete_calendar_event"
    ])
  end

  @doc """
  Checks if a tool requires confirmation.
  """
  def requires_confirmation?(tool_name) do
    MapSet.member?(destructive_tools(), tool_name)
  end

  @doc """
  Executes a tool by name with given arguments.
  """
  def execute(tool_name, args) do
    case tool_module(tool_name) do
      nil ->
        {:error, "Unknown tool: #{tool_name}"}

      module ->
        try do
          module.execute(tool_name, args)
        rescue
          e ->
            {:error, "Tool execution failed: #{Exception.message(e)}"}
        end
    end
  end

  @doc """
  Gets a description of what a tool does.
  """
  def get_tool_description(tool_name) do
    all_tools()
    |> Enum.find(fn tool -> tool.name == tool_name end)
    |> case do
      nil -> nil
      tool -> tool.description
    end
  end

  defp tool_module(tool_name) do
    cond do
      String.starts_with?(tool_name, "list_boards") or
        String.starts_with?(tool_name, "get_board") or
        String.starts_with?(tool_name, "create_board") or
        String.starts_with?(tool_name, "update_board") or
        String.starts_with?(tool_name, "delete_board") or
        String.starts_with?(tool_name, "list_columns") or
        String.starts_with?(tool_name, "create_column") or
        String.starts_with?(tool_name, "delete_column") or
        String.starts_with?(tool_name, "list_tasks") or
        String.starts_with?(tool_name, "get_task") or
        String.starts_with?(tool_name, "create_task") or
        String.starts_with?(tool_name, "update_task") or
        String.starts_with?(tool_name, "move_task") or
          String.starts_with?(tool_name, "delete_task") ->
        BoardsTools

      String.starts_with?(tool_name, "list_goals") or
        String.starts_with?(tool_name, "get_goal") or
        String.starts_with?(tool_name, "create_goal") or
        String.starts_with?(tool_name, "update_goal") or
          String.starts_with?(tool_name, "delete_goal") ->
        GoalsTools

      String.starts_with?(tool_name, "list_habits") or
        String.starts_with?(tool_name, "get_habit") or
        String.starts_with?(tool_name, "create_habit") or
        String.starts_with?(tool_name, "update_habit") or
        String.starts_with?(tool_name, "delete_habit") or
          String.starts_with?(tool_name, "toggle_habit") ->
        HabitsTools

      String.starts_with?(tool_name, "list_journal") or
        String.starts_with?(tool_name, "get_journal") or
        String.starts_with?(tool_name, "create_journal") or
        String.starts_with?(tool_name, "update_journal") or
          String.starts_with?(tool_name, "delete_journal") ->
        JournalTools

      String.starts_with?(tool_name, "list_transactions") or
        String.starts_with?(tool_name, "get_transaction") or
        String.starts_with?(tool_name, "create_transaction") or
        String.starts_with?(tool_name, "update_transaction") or
        String.starts_with?(tool_name, "delete_transaction") or
          String.starts_with?(tool_name, "get_finance") ->
        FinanceTools

      String.starts_with?(tool_name, "list_calendar") or
        String.starts_with?(tool_name, "get_calendar") or
        String.starts_with?(tool_name, "create_calendar") or
        String.starts_with?(tool_name, "update_calendar") or
        String.starts_with?(tool_name, "delete_calendar") or
          String.starts_with?(tool_name, "list_upcoming") ->
        CalendarTools

      String.starts_with?(tool_name, "analyze") or
        String.starts_with?(tool_name, "get_daily") or
          String.starts_with?(tool_name, "get_weekly") ->
        AnalyticsTools

      true ->
        nil
    end
  end
end
