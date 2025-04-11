defmodule OpenaiExPipeline.ExVCR.OpenaiMatchers do
  @moduledoc """
  Custom matchers for EXVcr and OpenAI API test cases.
  """
  #TODO consider merging these changes into the ExVCR library

  @doc """
  Matches OpenAI API requests by comparing the response with stored keys in the cassette.

  For file upload requests, it loads and compares the actual file contents to ensure
  the uploaded data matches exactly. For application/json requests, it decodes
  the JSON bodies and compares them as structured data to handle cases where the keys
  may be serialized in different orders.

  ## Parameters
    - response: The current API response being examined
    - keys: The stored keys from the cassette to compare against
    - recorder_options: Additional options passed to the recorder

  ## Returns
    - boolean: true if the request matches the stored keys, false otherwise

  ## Examples
      iex> match_openai_api_request(response, keys, recorder_options)
      true
  """

  def match_openai_api_request(response, keys, _recorder_options) do
    request_method = get_request_method(response)
    key_method = get_key_method(keys)
    request_url = get_request_url(response)
    key_url = get_key_url(keys)
    request_content_type = get_request_content_type(response)
    key_content_type = get_key_content_type(keys)

    if request_url == key_url and
         request_method == key_method and
         match_any_content_type?(request_content_type, key_content_type) do
      handle_match(
        request_method,
        request_content_type,
        get_request_body(response),
        key_content_type,
        get_key_body(keys)
      )
    else
      false
    end
  end

  defp handle_match("post", request_content_type, request_body, key_content_type, key_body) do
    cond do
      request_content_type =~ "application/json" ->
        decode_json(request_body) == decode_json(key_body)

      request_content_type =~ "multipart/form-data" ->
        request_multipart = extract_multipart(request_content_type, request_body)
        key_multipart = extract_multipart(key_content_type, key_body)

        request_multipart == key_multipart

      true ->
        decode_json(request_body) == decode_json(key_body)
    end
  end

  defp handle_match(_, _request_content_type, request_body, _key_content_type, key_body) do
    decode_json(request_body) == decode_json(key_body)
  end

  defp match_any_content_type?(request_content_type, key_content_type) do
    request_parts = String.split(request_content_type, ";")
    key_parts = String.split(key_content_type, ";")

    Enum.reduce_while(request_parts, false, fn request_part, _acc ->
      if Enum.any?(key_parts, &String.contains?(&1, request_part)) do
        {:halt, true}
      else
        {:cont, false}
      end
    end)
  end

  defp extract_multipart(content_type, body) do
    [_, boundary] = Regex.run(~r/boundary="?([^"]+)"?/, content_type)

    body
    |> String.split("--#{boundary}")
    |> Enum.reject(&(&1 == "--\r\n" or &1 == ""))
  end

  defp get_request_content_type(response) do
    case response[:request].headers
         |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end) do
      {_, content_type} ->
        content_type

      _ ->
        ""
    end
  end

  defp get_request_body(response) do
    response[:request].body |> to_string() |> String.trim()
  end

  defp get_request_url(response) do
    response[:request].url
  end

  defp get_request_method(response) do
    response[:request].method
  end

  defp get_key_content_type(keys) do
    case keys[:headers] |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end) do
      {_, content_type} ->
        content_type

      _ ->
        ""
    end
  end

  defp get_key_url(keys) do
    # This automatically includes the query params
    keys[:url]
    |> to_string()
    |> ExVCR.Filter.filter_sensitive_data()
  end

  defp get_key_method(keys) do
    keys[:method]
  end

  defp get_key_body(keys) do
    keys[:request_body] |> to_string() |> String.trim()
  end

  defp decode_json(data) do
    try do
      data
      |> to_string()
      |> JSON.decode!()
    rescue
      _ ->
        data
    end
  end

  # defp print_diff(a, b) do
  #   String.myers_difference(a, b)
  #   |> Enum.map_join(fn
  #     {:eq, text} -> text
  #     {:del, text} -> IO.ANSI.red() <> text <> IO.ANSI.reset()
  #     {:ins, text} -> IO.ANSI.green() <> text <> IO.ANSI.reset()
  #   end)
  #   |> IO.puts()
  # end
end
