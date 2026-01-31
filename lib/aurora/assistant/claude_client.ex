defmodule Aurora.Assistant.ClaudeClient do
  @moduledoc """
  HTTP client for Claude API using Req with streaming support.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @default_model "claude-sonnet-4-20250514"
  @fast_model "claude-haiku-4-20250514"
  @default_max_tokens 4096
  @anthropic_version "2023-06-01"

  @doc """
  Analyzes a user message to determine if it requires tools/actions.
  Uses a fast model (Haiku) to minimize latency and cost.
  Returns {:ok, :needs_tools} or {:ok, :conversation_only}
  """
  def analyze_intent(user_message) do
    system_prompt = """
    You are an intent classifier. Analyze the user's message and determine if they are:
    1. Requesting an ACTION (create, update, delete, view specific data, track something, log something)
    2. Just having a CONVERSATION (greeting, question about you, general chat, testing, unclear intent)

    Respond with ONLY one word: "ACTION" or "CONVERSATION"

    Examples:
    - "hello" -> CONVERSATION
    - "testing" -> CONVERSATION
    - "what can you do?" -> CONVERSATION
    - "how are you?" -> CONVERSATION
    - "create a task" -> ACTION
    - "show my habits" -> ACTION
    - "what are my goals?" -> ACTION
    - "log an expense of $50" -> ACTION
    - "mark habit as done" -> ACTION
    - "hi, add a task for groceries" -> ACTION
    """

    messages = [%{"role" => "user", "content" => user_message}]

    body = %{
      model: @fast_model,
      max_tokens: 10,
      messages: messages,
      system: system_prompt
    }

    case Req.post(@api_url, json: body, headers: build_headers(), receive_timeout: 30_000) do
      {:ok, %{status: 200, body: response}} ->
        text = get_response_text(response)
        if String.contains?(String.upcase(text), "ACTION") do
          {:ok, :needs_tools}
        else
          {:ok, :conversation_only}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Intent analysis failed: #{status}")
        # Default to needing tools if analysis fails
        {:ok, :needs_tools}

      {:error, error} ->
        Logger.warning("Intent analysis error: #{inspect(error)}")
        {:ok, :needs_tools}
    end
  end

  defp get_response_text(%{"content" => [%{"type" => "text", "text" => text} | _]}), do: text
  defp get_response_text(_), do: ""

  @doc """
  Sends a message to Claude API and returns the response.

  Options:
  - `:system_prompt` - System prompt for the conversation
  - `:tools` - List of tool definitions
  - `:stream_to` - PID to stream responses to (enables streaming mode)
  - `:model` - Model to use (default: claude-sonnet-4-20250514)
  - `:max_tokens` - Maximum tokens in response (default: 4096)
  """
  def create_message(messages, opts \\ []) do
    system_prompt = Keyword.get(opts, :system_prompt)
    tools = Keyword.get(opts, :tools, [])
    stream_to = Keyword.get(opts, :stream_to)
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    body =
      %{
        model: model,
        max_tokens: max_tokens,
        messages: format_messages(messages)
      }
      |> maybe_add_system(system_prompt)
      |> maybe_add_tools(tools)
      |> maybe_add_stream(stream_to)

    headers = build_headers()

    if stream_to do
      stream_request(body, headers, stream_to)
    else
      sync_request(body, headers)
    end
  end

  @doc """
  Continues a conversation with tool results.
  """
  def continue_with_tool_results(messages, tool_results, opts \\ []) do
    # Add tool results as a message
    tool_result_content =
      Enum.map(tool_results, fn {tool_use_id, result} ->
        %{
          "type" => "tool_result",
          "tool_use_id" => tool_use_id,
          "content" => format_tool_result(result)
        }
      end)

    updated_messages = messages ++ [%{"role" => "user", "content" => tool_result_content}]
    create_message(updated_messages, opts)
  end

  # Private functions

  defp sync_request(body, headers) do
    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, parse_response(response)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Claude API error: status=#{status} body=#{inspect(body)}")
        {:error, "API error #{status}: #{get_error_message(body)}"}

      {:error, error} ->
        Logger.error("Claude API request failed: #{inspect(error)}")
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp stream_request(body, headers, stream_to) do
    parent = self()

    Task.start(fn ->
      result =
        Req.post(@api_url,
          json: body,
          headers: headers,
          receive_timeout: 120_000,
          into: fn {:data, data}, acc ->
            handle_stream_chunk(data, stream_to)
            {:cont, acc}
          end
        )

      case result do
        {:ok, %{status: 200}} ->
          send(stream_to, {:assistant_stream_end, :ok})

        {:ok, %{status: status, body: body}} ->
          send(stream_to, {:assistant_stream_error, "API error #{status}"})

        {:error, error} ->
          send(stream_to, {:assistant_stream_error, inspect(error)})
      end
    end)

    :ok
  end

  defp handle_stream_chunk(data, stream_to) do
    data
    |> String.split("\n")
    |> Enum.each(fn line ->
      case parse_sse_line(line) do
        {:event, event} -> send(stream_to, {:assistant_event, event})
        :skip -> :ok
      end
    end)
  end

  defp parse_sse_line("data: " <> json) do
    case Jason.decode(json) do
      {:ok, %{"type" => "content_block_delta"} = event} ->
        {:event, event}

      {:ok, %{"type" => "content_block_start"} = event} ->
        {:event, event}

      {:ok, %{"type" => "message_start"} = event} ->
        {:event, event}

      {:ok, %{"type" => "message_delta"} = event} ->
        {:event, event}

      {:ok, %{"type" => "message_stop"}} ->
        {:event, %{"type" => "message_stop"}}

      {:ok, %{"type" => "content_block_stop"}} ->
        :skip

      {:ok, _other} ->
        :skip

      {:error, _} ->
        :skip
    end
  end

  defp parse_sse_line("event: " <> _), do: :skip
  defp parse_sse_line(""), do: :skip
  defp parse_sse_line(_), do: :skip

  defp parse_response(response) do
    %{
      id: response["id"],
      content: parse_content_blocks(response["content"]),
      stop_reason: response["stop_reason"],
      usage: response["usage"],
      model: response["model"]
    }
  end

  defp parse_content_blocks(nil), do: []

  defp parse_content_blocks(content) when is_list(content) do
    Enum.map(content, fn block ->
      case block["type"] do
        "text" ->
          %{type: :text, text: block["text"]}

        "tool_use" ->
          %{
            type: :tool_use,
            id: block["id"],
            name: block["name"],
            input: block["input"]
          }

        _ ->
          %{type: :unknown, raw: block}
      end
    end)
  end

  defp format_messages(messages) when is_list(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} ->
        %{"role" => to_string(role), "content" => content}

      %{"role" => _, "content" => _} = msg ->
        msg

      msg when is_map(msg) ->
        %{
          "role" => to_string(msg[:role] || msg["role"]),
          "content" => msg[:content] || msg["content"]
        }
    end)
  end

  defp maybe_add_system(body, nil), do: body
  defp maybe_add_system(body, ""), do: body
  defp maybe_add_system(body, system), do: Map.put(body, :system, system)

  defp maybe_add_tools(body, []), do: body
  defp maybe_add_tools(body, tools), do: Map.put(body, :tools, tools)

  defp maybe_add_stream(body, nil), do: body
  defp maybe_add_stream(body, _pid), do: Map.put(body, :stream, true)

  defp build_headers do
    [
      {"x-api-key", api_key()},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]
  end

  defp api_key do
    Application.get_env(:aurora, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY") ||
      raise """
      ANTHROPIC_API_KEY not configured.
      Set it via:
        - Environment variable: ANTHROPIC_API_KEY=sk-ant-...
        - Config: config :aurora, :anthropic_api_key, "sk-ant-..."
      """
  end

  defp get_error_message(%{"error" => %{"message" => message}}), do: message
  defp get_error_message(body), do: inspect(body)

  defp format_tool_result({:ok, result}) when is_map(result) do
    Jason.encode!(result)
  end

  defp format_tool_result({:ok, result}) do
    to_string(result)
  end

  defp format_tool_result({:error, error}) do
    "Error: #{error}"
  end

  defp format_tool_result(result) when is_map(result) do
    Jason.encode!(result)
  end

  defp format_tool_result(result) do
    to_string(result)
  end
end
