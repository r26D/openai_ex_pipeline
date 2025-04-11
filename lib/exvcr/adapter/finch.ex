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
if Code.ensure_loaded?(Finch) and Code.ensure_loaded?(ExVCR) do
  defmodule OpenaiExPipeline.ExVCR.Adapter.Finch do
    @moduledoc """
    Provides adapter methods to mock Finch methods.
    """

    use ExVCR.Adapter

    alias ExVCR.Util

    defmacro __using__(_opts) do
      # do nothing
    end

    defdelegate convert_from_string(string), to: OpenaiExPipeline.ExVCR.Adapter.Finch.Converter

    defdelegate convert_to_string(request, response),
      to: OpenaiExPipeline.ExVCR.Adapter.Finch.Converter

    defdelegate parse_request_body(request_body),
      to: OpenaiExPipeline.ExVCR.Adapter.Finch.Converter

    @doc """
    Returns the name of the mock target module.
    """
    def module_name do
      Finch
    end

    @doc """
    Returns list of the mock target methods with function name and callback.
    Implementation for global mock.
    """
    def target_methods() do
      [
        {:request, &ExVCR.Recorder.request([&1, &2])},
        {:request, &ExVCR.Recorder.request([&1, &2, &3])},
        {:request!, &(ExVCR.Recorder.request([&1, &2]) |> handle_response_for_request!())},
        {:request!, &(ExVCR.Recorder.request([&1, &2, &3]) |> handle_response_for_request!())}
      ]
    end

    @doc """
    Returns list of the mock target methods with function name and callback.
    """
    def target_methods(recorder) do
      [
        {:request, &ExVCR.Recorder.request(recorder, [&1, &2])},
        {:request, &ExVCR.Recorder.request(recorder, [&1, &2, &3])},
        {:request!,
         &(ExVCR.Recorder.request(recorder, [&1, &2]) |> handle_response_for_request!())},
        {:request!,
         &(ExVCR.Recorder.request(recorder, [&1, &2, &3]) |> handle_response_for_request!())}
      ]
    end

    @doc """
    Generate key for searching response.
    """
    def generate_keys_for_request(request) do
      req = Enum.fetch!(request, 0)
      url = Util.build_url(req.scheme, req.host, req.path, req.port, req.query)

      # The body can be a stream at this point
      body =
        req.body
        |> OpenaiExPipeline.ExVCR.Adapter.Finch.Converter.handle_stream_body()
        |> OpenaiExPipeline.ExVCR.Adapter.Finch.Converter.parse_request_body()

      [
        url: url,
        method: String.downcase(req.method),
        request_body: body,
        headers: req.headers
      ]
    end

    @doc """
    Callback from ExVCR.Handler when response is retrieved from the HTTP server.
    """
    def hook_response_from_server(response) do
      apply_filters(response)
    end

    @doc """
    Callback from ExVCR.Handler to get the response content tuple from the ExVCR.Response record.
    """
    def get_response_value_from_cache(response) do
      if response.type == "error" do
        {:error, response.body}
      else
        finch_response = %Finch.Response{
          status: response.status_code,
          headers: response.headers,
          body: response.body
        }

        {:ok, finch_response}
      end
    end

    defp apply_filters({:ok, %Finch.Response{} = response}) do
      filtered_response = apply_filters(response)
      {:ok, filtered_response}
    end

    defp apply_filters(%Finch.Response{} = response) do
      replaced_body = to_string(response.body) |> ExVCR.Filter.filter_sensitive_data()
      filtered_headers = ExVCR.Filter.remove_blacklisted_headers(response.headers)

      response
      |> Map.put(:body, replaced_body)
      |> Map.put(:headers, filtered_headers)
    end

    defp apply_filters({:error, reason}), do: {:error, reason}

    defp handle_response_for_request!({:ok, resp}), do: resp
    defp handle_response_for_request!({:error, error}), do: raise(error)
    defp handle_response_for_request!(resp), do: resp

    @doc """
    Default definitions for stub.
    """
    def default_stub_params(:headers), do: %{"content-type" => "text/html"}
    def default_stub_params(:status_code), do: 200
  end
else
  defmodule OpenaiExPipeline.ExVCR.Adapter.Finch do
    @moduledoc """
    Fallback module when Finch dependency is not available.
    """
    def module_name, do: raise("Missing dependency: Finch")
    def target_methods, do: raise("Missing dependency: Finch")
  end
end
