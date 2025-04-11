defmodule OpenaiExPipeline.Test.LibCase do
  @moduledoc """
  Test case template for API-related tests.
  """
  use ExUnit.CaseTemplate, async: false

  using do
    quote do
      use Patch
      import ExUnit.CaptureIO
      import ExUnit.CaptureLog
      import OpenaiExPipeline.ExVCR.OpenaiMatchers

      def get_real_openai_client(openai_client_timeout \\ 120_000) do
        config = Application.fetch_env!(:openai_ex_pipeline, :openai)
        api_key = config[:real_api_key] || raise "Missing real OpenAI API key in config"
        org_key = config[:organization_key]
        project_key = config[:project_key]

        OpenaiEx.new(api_key, org_key, project_key)
        |> OpenaiEx.with_receive_timeout(openai_client_timeout)
      end

      defp no_capture_log(fun), do: fun.()
    end
  end
end
