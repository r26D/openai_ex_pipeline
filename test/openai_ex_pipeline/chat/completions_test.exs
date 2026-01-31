defmodule OpenaiExPipeline.Chat.CompletionsTest do
  @moduledoc false
  use OpenaiExPipeline.Test.LibCase, async: false
  alias OpenaiExPipeline.Chat.Completions
  alias OpenaiExPipeline.OpenaiExWrapper

  setup do
    client =
      OpenaiExWrapper.get_openai_client(%{
        api_key: "sk-fake_api_key",
        organization_key: "org-fake-organization-key",
        project_key: "proj_fake-project-key"
      })

    {:ok, %{client: client}}
  end

  describe "normalize_chat_request/1" do
    test "sets max_completion_tokens from max_output_tokens and removes max_output_tokens" do
      request = %{
        model: "gpt-4o",
        messages: [%{role: "user", content: "Hi"}],
        max_output_tokens: 500
      }

      normalized = Completions.normalize_chat_request(request)

      assert normalized[:max_completion_tokens] == 500
      refute Map.has_key?(normalized, :max_output_tokens)
      assert normalized[:model] == "gpt-4o"
      assert normalized[:messages] == request[:messages]
    end

    test "removes max_input_tokens from the request" do
      request = %{
        model: "gpt-4o",
        messages: [%{role: "user", content: "Hi"}],
        max_input_tokens: 1000
      }

      normalized = Completions.normalize_chat_request(request)

      refute Map.has_key?(normalized, :max_input_tokens)
      assert normalized[:model] == "gpt-4o"
    end

    test "removes stop when model starts with gpt-5" do
      request = %{
        model: "gpt-5-mini",
        messages: [%{role: "user", content: "Hi"}],
        stop: ["\n\n"]
      }

      normalized = Completions.normalize_chat_request(request)

      refute Map.has_key?(normalized, :stop)
      assert normalized[:model] == "gpt-5-mini"
    end

    test "keeps stop when model does not start with gpt-5" do
      request = %{
        model: "gpt-4o",
        messages: [%{role: "user", content: "Hi"}],
        stop: ["\n\n"]
      }

      normalized = Completions.normalize_chat_request(request)

      assert normalized[:stop] == ["\n\n"]
      assert normalized[:model] == "gpt-4o"
    end

    test "applies all normalizations together" do
      request = %{
        model: "gpt-5",
        messages: [%{role: "user", content: "Hi"}],
        max_output_tokens: 200,
        max_input_tokens: 4000,
        stop: ["END"]
      }

      normalized = Completions.normalize_chat_request(request)

      assert normalized[:max_completion_tokens] == 200
      refute Map.has_key?(normalized, :max_output_tokens)
      refute Map.has_key?(normalized, :max_input_tokens)
      refute Map.has_key?(normalized, :stop)
      assert normalized[:model] == "gpt-5"
    end
  end

  describe "create/2" do
    test "calls OpenaiEx.Chat.Completions.create with normalized request and returns result", %{
      client: client
    } do
      request = %{
        model: "gpt-4o",
        messages: [%{role: "user", content: "Hi"}],
        max_output_tokens: 100
      }

      expected_normalized = Completions.normalize_chat_request(request)
      expected_response = %{
        "choices" => [%{"message" => %{"content" => "Hello", "role" => "assistant"}}],
        "id" => "chatcmpl-123"
      }

      patch(OpenaiEx.Chat.Completions, :create, fn ^client, normalized ->
        assert normalized[:max_completion_tokens] == 100
        refute Map.has_key?(normalized, :max_output_tokens)
        {:ok, expected_response}
      end)

      assert {:ok, ^expected_response} = Completions.create(client, request)

      assert_called(OpenaiEx.Chat.Completions.create(client, expected_normalized))
    end

    test "returns error unchanged", %{client: client} do
      request = %{model: "gpt-4o", messages: [%{role: "user", content: "Hi"}]}
      expected_normalized = Completions.normalize_chat_request(request)

      patch(OpenaiEx.Chat.Completions, :create, fn _, _ ->
        {:error, %{"error" => %{"message" => "Rate limit"}}}
      end)

      assert {:error, %{"error" => _}} = Completions.create(client, request)

      assert_called(OpenaiEx.Chat.Completions.create(client, expected_normalized))
    end
  end

  describe "create/3" do
    test "calls OpenaiEx.Chat.Completions.create with normalized request and stream: true", %{
      client: client
    } do
      request = %{
        model: "gpt-5-mini",
        messages: [%{role: "user", content: "Hi"}],
        stop: ["\n"]
      }

      expected_normalized = Completions.normalize_chat_request(request)

      patch(OpenaiEx.Chat.Completions, :create, fn ^client, normalized, opts ->
        refute Map.has_key?(normalized, :stop)
        assert opts == [stream: true]
        {:ok, fn -> [] end}
      end)

      assert {:ok, _stream} = Completions.create(client, request, stream: true)

      assert_called(OpenaiEx.Chat.Completions.create(client, expected_normalized, [stream: true]))
    end
  end
end
