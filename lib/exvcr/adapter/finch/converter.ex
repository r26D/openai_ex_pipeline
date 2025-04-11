# Used from the ExVCR project version 0.17.0
# Copyright (c) 2013-2015 parroty

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# TODO consider merging these changes into the ExVCR library
if Code.ensure_loaded?(Finch) do
  defmodule OpenaiExPipeline.ExVCR.Adapter.Finch.Converter do
    @moduledoc """
    Provides helpers to mock Finch methods.

    # This module is a fork of ExVCR.Adapter.Finch.Converter to handle file uploads
    # The main changes are:
    # 1. Added handling for streamed request bodies in request_to_string/3
    # 2. Modified parse_request_body/1 to handle streamed bodies
    # 3. Added convert_stream_request/2 to properly process streamed file uploads
    # 4. Updated error handling for stream processing
    #
    # These changes were necessary because the original ExVCR converter did not properly
    # handle multipart form data file uploads that use streaming. The OpenAI API requires
    # streaming file uploads for large files to avoid memory issues.
    """

    use ExVCR.Converter

    alias ExVCR.Util

    defp string_to_response(string) do
      response = Enum.map(string, fn {x, y} -> {String.to_atom(x), y} end)
      response = struct(ExVCR.Response, response)

      response =
        if response.type == "error" do
          body = string_to_error_reason(response.body)
          %{response | body: body}
        else
          response
        end

      response =
        if is_map(response.headers) do
          headers =
            response.headers
            |> Map.to_list()
            |> Enum.map(fn {k, v} -> {k, v} end)

          %{response | headers: headers}
        else
          response
        end

      response
    end

    defp string_to_error_reason(reason) do
      {reason_struct, _} = Code.eval_string(reason)
      reason_struct
    end

    defp request_to_string([request, finch_module]) do
      request_to_string([request, finch_module, []])
    end

    defp request_to_string([request, _finch_module, opts]) do
      url =
        Util.build_url(request.scheme, request.host, request.path, request.port, request.query)

      body_content = request.body |> handle_stream_body() |> parse_request_body()

      %ExVCR.Request{
        url: parse_url(url),
        headers: parse_headers(request.headers),
        method: String.downcase(request.method),
        body: body_content,
        options: parse_options(sanitize_options(opts))
      }
    end

    def handle_stream_body({:stream, stream_func}), do: Enum.to_list(stream_func)
    def handle_stream_body(body), do: body

    # If option value is tuple, make it as list, for encoding as json.
    defp sanitize_options(options) do
      Enum.map(options, fn {key, value} ->
        if is_tuple(value) do
          {key, Tuple.to_list(value)}
        else
          {key, value}
        end
      end)
    end

    defp response_to_string({:ok, %Finch.Response{} = response}), do: response_to_string(response)

    defp response_to_string(%Finch.Response{} = response) do
      %ExVCR.Response{
        type: "ok",
        status_code: response.status,
        headers: parse_headers(response.headers),
        body: to_string(response.body)
      }
    end

    defp response_to_string({:error, reason}) do
      %ExVCR.Response{
        type: "error",
        body: error_reason_to_string(reason)
      }
    end

    defp error_reason_to_string(reason), do: Macro.to_string(reason)
  end
end
