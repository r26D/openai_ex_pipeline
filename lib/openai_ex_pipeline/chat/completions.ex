defmodule OpenaiExPipeline.Chat.Completions do
  @moduledoc """
  Single entry point for OpenAI Chat Completions "create" (and streaming create).

  Use this module when calling OpenAI Chat Completions with GPT-4 or GPT-5 so that
  request normalization is applied before calling the API.

  ## Request normalization

  Before calling `OpenaiEx.Chat.Completions.create/2` or `create/3`, the pipeline
  normalizes the chat request:

  - **max_output_tokens** → **max_completion_tokens**: If `max_output_tokens` is
    present, it is set as `max_completion_tokens` and `max_output_tokens` is removed.
    The Chat Completions API uses `max_completion_tokens`.

  - **max_input_tokens** removed: The Chat Completions API does not accept
    `max_input_tokens`; it is stripped from the request.

  - **stop** removed for gpt-5: If `model` is a string that starts with `"gpt-5"`,
    `stop` is removed from the request. Reasoning models do not support the `stop`
    parameter.

  The `chat_request` map must use atom keys (consistent with `OpenaiEx.Chat.Completions`).
  """

  @doc """
  Creates a chat completion with a normalized request.

  Normalizes the request (max_output_tokens → max_completion_tokens, removes
  max_input_tokens, removes stop for gpt-5 models), then calls
  `OpenaiEx.Chat.Completions.create(client, normalized_request)`.

  Returns the result unchanged: `{:ok, response}` or `{:error, reason}`.

  ## Parameters

    - client: OpenAI client (e.g. from `OpenaiExPipeline.OpenaiExWrapper.get_openai_client/1`)
    - chat_request: Map with atom keys (model, messages, and optional API params)

  ## Examples

      iex> request = %{model: "gpt-4o", messages: [%{role: "user", content: "Hi"}], max_output_tokens: 100}
      iex> OpenaiExPipeline.Chat.Completions.create(client, request)
      {:ok, %{"choices" => [...]}}

      iex> OpenaiExPipeline.Chat.Completions.create(client, request)
      {:error, %{"error" => ...}}
  """
  def create(client, chat_request) do
    normalized = normalize_chat_request(chat_request)
    OpenaiEx.Chat.Completions.create(client, normalized)
  end

  @doc """
  Creates a chat completion with options (e.g. streaming).

  Same normalization as `create/2`. Then calls
  `OpenaiEx.Chat.Completions.create(client, normalized_request, opts)`.

  Returns the result unchanged: `{:ok, response}` or `{:error, reason}` (or a stream).

  ## Parameters

    - client: OpenAI client
    - chat_request: Map with atom keys
    - opts: Keyword options (e.g. `stream: true`)

  ## Examples

      iex> OpenaiExPipeline.Chat.Completions.create(client, request, stream: true)
      {:ok, stream_fun}
  """
  def create(client, chat_request, opts) do
    normalized = normalize_chat_request(chat_request)
    OpenaiEx.Chat.Completions.create(client, normalized, opts)
  end

  @doc """
  Normalizes a chat request for the Chat Completions API.

  - If `max_output_tokens` is present: sets `max_completion_tokens` to that value
    and removes `max_output_tokens`.
  - Removes `max_input_tokens` (not accepted by Chat Completions).
  - If `model` is a string starting with `"gpt-5"`: removes `stop` (reasoning models
    do not support stop).

  Expects and returns a map with atom keys. Does not mutate the input; returns a
  new map.
  """
  def normalize_chat_request(chat_request) when is_map(chat_request) do
    chat_request
    |> maybe_set_max_completion_tokens()
    |> drop_max_input_tokens()
    |> maybe_drop_stop_for_gpt5()
  end

  defp maybe_set_max_completion_tokens(map) do
    case Map.fetch(map, :max_output_tokens) do
      {:ok, value} ->
        map
        |> Map.delete(:max_output_tokens)
        |> Map.put(:max_completion_tokens, value)

      :error ->
        map
    end
  end

  defp drop_max_input_tokens(map) do
    Map.delete(map, :max_input_tokens)
  end

  defp maybe_drop_stop_for_gpt5(map) do
    model = Map.get(map, :model)

    if is_binary(model) and String.starts_with?(model, "gpt-5") do
      Map.delete(map, :stop)
    else
      map
    end
  end
end
