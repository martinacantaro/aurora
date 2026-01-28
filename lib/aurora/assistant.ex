defmodule Aurora.Assistant do
  @moduledoc """
  The Assistant context for managing AI conversations, messages, and tool calls.
  """

  import Ecto.Query, warn: false
  alias Aurora.Repo
  alias Aurora.Assistant.{Conversation, Message, ToolCall}

  # =============
  # Conversations
  # =============

  @doc """
  Returns all conversations, most recent first.
  """
  def list_conversations do
    Conversation
    |> where([c], c.archived == false)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single conversation with messages preloaded.
  """
  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(messages: from(m in Message, order_by: [asc: m.inserted_at]))
  end

  @doc """
  Gets a conversation or returns nil.
  """
  def get_conversation(id) do
    case Repo.get(Conversation, id) do
      nil -> nil
      conv -> Repo.preload(conv, messages: from(m in Message, order_by: [asc: m.inserted_at]))
    end
  end

  @doc """
  Creates a new conversation.
  """
  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conversation.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a conversation.
  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  @doc """
  Archives a conversation.
  """
  def archive_conversation(%Conversation{} = conversation) do
    update_conversation(conversation, %{archived: true})
  end

  @doc """
  Gets or creates a default conversation.
  """
  def get_or_create_default_conversation do
    case list_conversations() |> List.first() do
      nil -> create_conversation(%{title: "New Conversation"})
      conv -> {:ok, conv}
    end
  end

  # =============
  # Messages
  # =============

  @doc """
  Lists all messages for a conversation.
  """
  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Repo.preload(:tool_calls)
  end

  @doc """
  Gets a single message.
  """
  def get_message!(id) do
    Message
    |> Repo.get!(id)
    |> Repo.preload(:tool_calls)
  end

  @doc """
  Creates a message.
  """
  def create_message(attrs \\ %{}) do
    result =
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()

    # Touch the conversation's updated_at
    case result do
      {:ok, message} ->
        from(c in Conversation, where: c.id == ^message.conversation_id)
        |> Repo.update_all(set: [updated_at: NaiveDateTime.utc_now()])

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Updates a message.
  """
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message.
  """
  def delete_message(%Message{} = message) do
    Repo.delete(message)
  end

  @doc """
  Creates a user message in a conversation.
  """
  def add_user_message(conversation_id, content) do
    create_message(%{
      conversation_id: conversation_id,
      role: "user",
      content: content
    })
  end

  @doc """
  Creates an assistant message in a conversation.
  """
  def add_assistant_message(conversation_id, content, opts \\ []) do
    create_message(%{
      conversation_id: conversation_id,
      role: "assistant",
      content: content,
      completed: Keyword.get(opts, :completed, true),
      input_tokens: Keyword.get(opts, :input_tokens),
      output_tokens: Keyword.get(opts, :output_tokens)
    })
  end

  @doc """
  Gets the last N messages from a conversation for context.
  """
  def get_recent_messages(conversation_id, limit \\ 20) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Formats messages for the Claude API.
  """
  def format_messages_for_api(messages) do
    messages
    |> Enum.filter(fn m -> m.role in ["user", "assistant"] end)
    |> Enum.map(fn m ->
      %{
        "role" => m.role,
        "content" => m.content
      }
    end)
  end

  # =============
  # Tool Calls
  # =============

  @doc """
  Creates a tool call record.
  """
  def create_tool_call(attrs \\ %{}) do
    %ToolCall{}
    |> ToolCall.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tool call.
  """
  def update_tool_call(%ToolCall{} = tool_call, attrs) do
    tool_call
    |> ToolCall.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a tool call by ID.
  """
  def get_tool_call!(id) do
    Repo.get!(ToolCall, id)
  end

  @doc """
  Gets a tool call by tool_use_id.
  """
  def get_tool_call_by_use_id(tool_use_id) do
    Repo.get_by(ToolCall, tool_use_id: tool_use_id)
  end

  @doc """
  Marks a tool call as successful with output.
  """
  def complete_tool_call(%ToolCall{} = tool_call, output) do
    update_tool_call(tool_call, %{
      status: "success",
      tool_output: output
    })
  end

  @doc """
  Marks a tool call as failed with error message.
  """
  def fail_tool_call(%ToolCall{} = tool_call, error_message) do
    update_tool_call(tool_call, %{
      status: "error",
      error_message: error_message
    })
  end

  @doc """
  Confirms a tool call that requires confirmation.
  """
  def confirm_tool_call(%ToolCall{} = tool_call) do
    update_tool_call(tool_call, %{
      confirmed_at: DateTime.utc_now()
    })
  end

  @doc """
  Cancels a tool call.
  """
  def cancel_tool_call(%ToolCall{} = tool_call) do
    update_tool_call(tool_call, %{
      status: "cancelled"
    })
  end

  @doc """
  Gets pending tool calls for a message.
  """
  def get_pending_tool_calls(message_id) do
    ToolCall
    |> where([t], t.message_id == ^message_id and t.status == "pending")
    |> Repo.all()
  end

  @doc """
  Logs a tool execution for audit purposes.
  """
  def log_tool_execution(message_id, tool_name, input, result) do
    status = case result do
      {:ok, _} -> "success"
      {:error, _} -> "error"
    end

    output = case result do
      {:ok, output} -> output
      {:error, error} -> nil
    end

    error_msg = case result do
      {:ok, _} -> nil
      {:error, error} -> to_string(error)
    end

    create_tool_call(%{
      message_id: message_id,
      tool_name: tool_name,
      tool_input: input,
      tool_output: output,
      status: status,
      error_message: error_msg
    })
  end
end
