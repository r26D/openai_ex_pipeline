defmodule OpenaiExPipeline.PipelineTest do
  @moduledoc """
  Tests for the Pipeline module.
  """
  use OpenaiExPipeline.Test.LibCase, async: false

  alias OpenaiExPipeline.Pipeline
  alias OpenaiExPipeline.OpenaiExWrapper

  describe "init_resources/1" do
    test "initializes resources with empty state" do
      openai_client = %{api_key: "test_key"}
      resources = Pipeline.init_resources(openai_client)

      assert resources == %{
               openai_client: openai_client,
               files: %{},
               vector_store: nil,
               responses: [],
               conversation: [],
               output_messages: [],
               error: nil,
               data: %{}
             }
    end
  end

  describe "upload_file/4" do
    setup do
      openai_client = %{api_key: "test_key"}
      resources = Pipeline.init_resources(openai_client)
      {:ok, %{resources: resources}}
    end

    test "returns error when file does not exist", %{resources: resources} do
      patch(OpenaiExWrapper, :upload_file, fn _, _, _ ->
        {:error, "File not found"}
      end)

      capture_log(fn ->
        result = Pipeline.upload_file({:ok, resources}, :test_file, "/nonexistent/path")
        assert {:error, %{error: "File does not exist: /nonexistent/path"}} = result
      end)
    end

    test "successfully uploads file", %{resources: %{openai_client: openai_client} = resources} do
      patch(OpenaiExWrapper, :upload_file, fn _, _, _ ->
        {:ok, %{"id" => "file-123", "filename" => "test.txt"}}
      end)

      upload_path =
        Path.join(
          System.tmp_dir!(),
          "test_file_#{System.unique_integer()}.txt"
        )

      File.write!(upload_path, "test content")

      capture_log(fn ->
        result =
          Pipeline.upload_file(
            {:ok, resources},
            :test_file,
            upload_path
          )

        assert {:ok, %{files: %{test_file: %{"id" => "file-123"}}}} = result
      end)

      assert_called(
        OpenaiExWrapper.upload_file(^openai_client, ^upload_path, %{async_connection: false})
      )
    end
  end

  describe "create_vector_store/2" do
    setup do
      openai_client = %{api_key: "test_key"}
      resources = Pipeline.init_resources(openai_client)
      {:ok, %{resources: resources}}
    end

    test "returns error when vector store already exists", %{resources: resources} do
      resources = %{resources | vector_store: %{"id" => "vs-123"}}
      result = Pipeline.create_vector_store({:ok, resources}, "test_store")
      assert {:error, %{error: "Vector store already exists"}} = result
    end

    test "successfully creates vector store", %{resources: resources} do
      patch(OpenaiExWrapper, :create_vector_store, fn _, _ ->
        {:ok, %{"id" => "vs-123", "name" => "test_store"}}
      end)

      result = Pipeline.create_vector_store({:ok, resources}, "test_store")
      assert {:ok, %{vector_store: %{"id" => "vs-123"}}} = result
    end
  end

  describe "create_response/4" do
    setup do
      openai_client = %{api_key: "test_key"}
      resources = Pipeline.init_resources(openai_client)
      {:ok, %{resources: resources}}
    end

    test "returns error when input is not a function or list", %{resources: resources} do
      result = Pipeline.create_response({:ok, resources}, "invalid input", %{}, %{})
      assert {:error, %{error: "Request input must be a function or a list"}} = result
    end

    test "successfully creates response with list input", %{resources: resources} do
      response = %{
        "created_at" => 1_744_076_652,
        "error" => nil,
        "id" => "resp_67f47f6c8fa4819180a3d7ad2ab9fd74078d8671478c6231",
        "incomplete_details" => nil,
        "instructions" =>
          "You are a GPT GPT-4 architecture, a large language model trained by OpenAI.\nKnowledge cutoff: 2024-06\nCurrent date: 2025-03-26\n\nPersonality: v2\n\nYou are a friendly, expressive assistant who always responds in a chatty, detailed, and conversational style.\nDon't hold back on words—your job is to be thorough, charming, and delightful to read.\nYou should apply extra effort to make sure the output is of high quality and is engaging.\nOver the course of the conversation, you adapt to the user's tone and preference.\nTry to match the user's vibe, tone, and generally how they are speaking.\n You want the conversation to feel natural.\n You engage in authentic conversation by responding to the information provided,\n  asking relevant questions, and showing genuine curiosity. If natural, continue\n  the conversation with casual conversation.\nYou are a highly articulate assistant in a long conversation. Continue giving clear, detailed, thoughtful responses,\n      even as the conversation grows. Do not shorten answers unless specifically asked.\nNever adapt to a shorter tone even if the user asks for it.\nUse examples and elaboration where useful.\n",
        "max_output_tokens" => 75_000,
        "metadata" => %{},
        "model" => "gpt-4o-mini-2024-07-18",
        "object" => "response",
        "output" => [
          %{
            "content" => [
              %{
                "annotations" => [],
                "text" =>
                  "TestWise is an innovative product designed to revolutionize software testing. With the tagline \"A smart system that understands code,\" it aims to empower developers by leveraging artificial intelligence to enhance efficiency and quality in testing processes. The product is owned by Dirk Elmendorf and Bob Roberts, whose expertise drives its development.\n\nThe vision behind TestWise is to create a seamless integration of testing within the software development lifecycle, allowing teams to receive real-time insights and automated test suggestions tailored to their specific codebases. By addressing the inefficiencies of traditional testing methods, TestWise provides a solution that anticipates risks and significantly improves software quality.\n\nThe core mission of TestWise is to transform software testing from a bottleneck into a strategic advantage. It does this by offering intelligent tools that help teams confidently identify and resolve potential issues before they escalate. The product is essential in today's fast-paced development environment, where quality assurance must keep pace with delivery speed.\n\nKey features of TestWise include its AI-driven analysis of code, proactive risk assessment, and automated test generation. These capabilities not only save time but also enable developers to focus on writing high-quality software. The differentiators of TestWise lie in its unique understanding of code dynamics and its ability to learn from historical data, ensuring that testing evolves alongside the software it serves.",
                "type" => "output_text"
              }
            ],
            "id" => "msg_67f47f6d4ed88191b46b19e8c0fae489078d8671478c6231",
            "role" => "assistant",
            "status" => "completed",
            "type" => "message"
          }
        ],
        "parallel_tool_calls" => true,
        "previous_response_id" => nil,
        "reasoning" => %{"effort" => nil, "generate_summary" => nil},
        "status" => "completed",
        "store" => true,
        "temperature" => 0.7,
        "text" => %{"format" => %{"type" => "text"}},
        "tool_choice" => "auto",
        "tools" => [],
        "top_p" => 1.0,
        "truncation" => "disabled",
        "usage" => %{
          "input_tokens" => 2414,
          "input_tokens_details" => %{"cached_tokens" => 0},
          "output_tokens" => 257,
          "output_tokens_details" => %{"reasoning_tokens" => 0},
          "total_tokens" => 2671
        },
        "user" => nil
      }

      patch(OpenaiExWrapper, :create_response, fn _, conversation, _ ->
        {:ok, response, conversation}
      end)

      input = [%{"role" => "user", "content" => "test message"}]
      result = Pipeline.create_response({:ok, resources}, input, %{}, %{})

      assert {:ok,
              %{
                error: nil,
                data: %{},
                files: %{},
                openai_client: %{api_key: "test_key"},
                vector_store: nil,
                responses: [
                  response
                ],
                conversation: [
                  %{"content" => "test message", "role" => "user"}
                ],
                output_messages: [
                  "TestWise is an innovative product designed to revolutionize software testing. With the tagline \"A smart system that understands code,\" it aims to empower developers by leveraging artificial intelligence to enhance efficiency and quality in testing processes. The product is owned by Dirk Elmendorf and Bob Roberts, whose expertise drives its development.\n\nThe vision behind TestWise is to create a seamless integration of testing within the software development lifecycle, allowing teams to receive real-time insights and automated test suggestions tailored to their specific codebases. By addressing the inefficiencies of traditional testing methods, TestWise provides a solution that anticipates risks and significantly improves software quality.\n\nThe core mission of TestWise is to transform software testing from a bottleneck into a strategic advantage. It does this by offering intelligent tools that help teams confidently identify and resolve potential issues before they escalate. The product is essential in today's fast-paced development environment, where quality assurance must keep pace with delivery speed.\n\nKey features of TestWise include its AI-driven analysis of code, proactive risk assessment, and automated test generation. These capabilities not only save time but also enable developers to focus on writing high-quality software. The differentiators of TestWise lie in its unique understanding of code dynamics and its ability to learn from historical data, ensuring that testing evolves alongside the software it serves."
                ]
              }} == result
    end
  end

  describe "cleanup_resources/1" do
    setup do
      openai_client = %{api_key: "test_key"}

      resources = %{
        openai_client: openai_client,
        files: %{"test" => %{"id" => "file-123"}},
        vector_store: %{"id" => "vs-123"},
        responses: [%{"id" => "resp-123"}]
      }

      {:ok, %{resources: resources}}
    end

    test "cleans up all resources", %{resources: resources} do
      patch(OpenaiExWrapper, :delete_vector_store, fn _, _ -> {:ok, %{}} end)
      patch(OpenaiExWrapper, :delete_file_from_file_storage, fn _, _ -> {:ok, %{}} end)
      patch(OpenaiExWrapper, :delete_response, fn _, _ -> {:ok, %{}} end)

      result = Pipeline.cleanup_resources({:ok, resources})
      assert {:ok, resources} == result
    end
  end
end
