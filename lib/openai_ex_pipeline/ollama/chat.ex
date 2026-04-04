defmodule OpenaiExPipeline.Ollama.Chat do
  @moduledoc """
  Native Ollama `/api/chat` client that properly supports thinking control.

  Ollama's OpenAI-compatible `/v1/chat/completions` endpoint does not honor
  the `think` parameter. This module uses the native `/api/chat` endpoint
  and maps the response to the OpenAI format so callers don't need to change.

  ## Usage

      # Instead of:
      OpenaiExPipeline.Chat.Completions.create(client, request)

      # Use:
      OpenaiExPipeline.Ollama.Chat.create(base_url, request, opts)

  Where `base_url` is the Ollama base URL (e.g. "http://localhost:11434")
  WITHOUT the `/v1` suffix.

  The request map uses the same atom keys as `OpenaiEx.Chat.Completions`:
  `:model`, `:messages`, `:tools`, `:think`, `:options`, `:stream`, `:max_tokens`.

  The response is mapped to the OpenAI `choices` format.
  """

  @doc """
  Create a chat completion via Ollama's native API.

  ## Parameters

    - base_url: Ollama server URL (e.g. "http://localhost:11434") — no /v1 suffix
    - request: Map with atom keys (:model, :messages, and optional params)
    - opts: keyword list with optional :receive_timeout (default 60_000)

  ## Returns

    - `{:ok, openai_formatted_response}` on success
    - `{:error, reason}` on failure

  The response is mapped to OpenAI format:

      %{
        "choices" => [%{
          "message" => %{"role" => "assistant", "content" => "...", "tool_calls" => [...]},
          "finish_reason" => "stop"
        }],
        "model" => "qwen3.5:9b",
        "usage" => %{"prompt_tokens" => N, "completion_tokens" => N}
      }

  When thinking is enabled, the `"reasoning"` field is included in the message.
  """
  def create(base_url, request, opts \\ []) do
    receive_timeout = Keyword.get(opts, :receive_timeout, 60_000)
    url = "#{base_url}/api/chat"

    # Build the native Ollama request body
    body = build_native_request(request)

    case Req.post(url, json: body, receive_timeout: receive_timeout) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, to_openai_format(response, request)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_native_request(request) do
    body = %{
      "model" => Map.get(request, :model),
      "messages" => Map.get(request, :messages, []),
      "stream" => Map.get(request, :stream, false)
    }

    # Think parameter — properly supported on native endpoint
    body = case Map.fetch(request, :think) do
      {:ok, val} -> Map.put(body, "think", val)
      :error -> body
    end

    # Ollama options (num_ctx, etc.)
    body = case Map.fetch(request, :options) do
      {:ok, opts} when is_map(opts) and opts != %{} -> Map.put(body, "options", opts)
      _ -> body
    end

    # Tools
    body = case Map.fetch(request, :tools) do
      {:ok, tools} when is_list(tools) and tools != [] -> Map.put(body, "tools", tools)
      _ -> body
    end

    # max_tokens → num_predict for native API
    body = case Map.get(request, :max_tokens) || Map.get(request, :max_completion_tokens) do
      nil -> body
      n -> Map.update(body, "options", %{"num_predict" => n}, &Map.put(&1, "num_predict", n))
    end

    body
  end

  defp to_openai_format(response, _request) do
    message = Map.get(response, "message", %{})
    content = Map.get(message, "content", "")
    thinking = Map.get(message, "thinking", "")
    tool_calls = Map.get(message, "tool_calls") || []
    done_reason = Map.get(response, "done_reason", "stop")

    # Build OpenAI-shaped message
    openai_message = %{
      "role" => "assistant",
      "content" => content
    }

    # Include thinking as "reasoning" field (matches Ollama /v1 behavior)
    openai_message = if thinking != "" do
      Map.put(openai_message, "reasoning", thinking)
    else
      openai_message
    end

    # Map native tool_calls to OpenAI format
    openai_message = if tool_calls != [] do
      mapped_calls = Enum.with_index(tool_calls, fn tc, idx ->
        func = Map.get(tc, "function", %{})
        %{
          "id" => "call_#{idx}",
          "type" => "function",
          "function" => %{
            "name" => Map.get(func, "name"),
            "arguments" => encode_args(Map.get(func, "arguments", %{}))
          }
        }
      end)
      Map.put(openai_message, "tool_calls", mapped_calls)
    else
      openai_message
    end

    # Map finish reason
    finish_reason = case done_reason do
      "stop" -> "stop"
      "length" -> "length"
      _ -> done_reason
    end

    # Build usage from Ollama's native metrics
    usage = %{
      "prompt_tokens" => Map.get(response, "prompt_eval_count", 0),
      "completion_tokens" => Map.get(response, "eval_count", 0)
    }

    %{
      "choices" => [
        %{
          "message" => openai_message,
          "finish_reason" => finish_reason,
          "index" => 0
        }
      ],
      "model" => Map.get(response, "model"),
      "usage" => usage
    }
  end

  defp encode_args(args) when is_binary(args), do: args
  defp encode_args(args) when is_map(args), do: Jason.encode!(args)
  defp encode_args(_), do: "{}"
end
