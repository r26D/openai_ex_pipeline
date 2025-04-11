defmodule OpenaiExPipeline.OpenaiExWrapperTest do
  @moduledoc """
  Tests for the OpenaiExWrapper module.
  """
  use OpenaiExPipeline.Test.LibCase, async: false
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

  describe "pretty_log_input/1" do
    test "prints input with role and content" do
      input = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there"}
      ]

      output =
        capture_log(fn ->
          OpenaiExWrapper.pretty_log_input(input)
        end)

      assert output =~ "user"
      assert output =~ "assistant"
      assert output =~ "Hello"
      assert output =~ "Hi there"
    end
  end

  describe "filter_content/1" do
    test "removes OpenAI citations from content" do
      content = "This is some content 【citation】with citations【another citation】"

      assert {:ok, "This is some content with citations"} ==
               OpenaiExWrapper.filter_content(content)
    end

    test "returns unchanged content when no citations present" do
      content = "This is some content without citations"
      assert {:ok, content} == OpenaiExWrapper.filter_content(content)
    end
  end

  describe "list_files/1" do
    test "successfully lists files", %{client: client} do
      patch(OpenaiEx.Files, :list, fn _ ->
        {:ok,
         %{
           "data" => [
             %{
               "id" => "file-abc123",
               "object" => "file",
               "bytes" => 175,
               "created_at" => 1_613_677_385,
               "filename" => "salesOverview.pdf",
               "purpose" => "assistants"
             },
             %{
               "id" => "file-abc123",
               "object" => "file",
               "bytes" => 140,
               "created_at" => 1_613_779_121,
               "filename" => "puppy.jsonl",
               "purpose" => "fine-tune"
             }
           ],
           "object" => "list"
         }}
      end)

      assert {:ok, files} = OpenaiExWrapper.list_files(client)
      assert Enum.count(files) == 2
    end

    test "returns error when client is invalid", %{client: client} do
      patch(OpenaiEx.Files, :list, fn _ -> {:error, "Invalid API key"} end)

      assert {:error, "Invalid API key"} = OpenaiExWrapper.list_files(client)
    end
  end

  describe "list_vector_stores/1" do
    test "returns error when API call fails", %{client: client} do
      patch(OpenaiEx.Beta.VectorStores, :list, fn _ ->
        {:error, "API request failed"}
      end)

      assert {:error, "API request failed"} = OpenaiExWrapper.list_vector_stores(client)
    end

    test "successfully lists vector stores", %{client: client} do
      patch(OpenaiEx.Beta.VectorStores, :list, fn _ ->
        {:ok,
         %{
           "object" => "list",
           "data" => [
             %{
               "id" => "vs_abc123",
               "object" => "vector_store",
               "created_at" => 1_699_061_776,
               "name" => "Support FAQ",
               "bytes" => 139_920,
               "file_counts" => %{
                 "in_progress" => 0,
                 "completed" => 3,
                 "failed" => 0,
                 "cancelled" => 0,
                 "total" => 3
               }
             },
             %{
               "id" => "vs_abc456",
               "object" => "vector_store",
               "created_at" => 1_699_061_776,
               "name" => "Support FAQ v2",
               "bytes" => 139_920,
               "file_counts" => %{
                 "in_progress" => 0,
                 "completed" => 3,
                 "failed" => 0,
                 "cancelled" => 0,
                 "total" => 3
               }
             }
           ],
           "first_id" => "vs_abc123",
           "last_id" => "vs_abc456",
           "has_more" => false
         }}
      end)

      assert {:ok, vector_stores} = OpenaiExWrapper.list_vector_stores(client)
      assert Enum.count(vector_stores) == 2
    end
  end

  describe "upload_file/3" do
    test "successfully uploads file - no options set", %{client: client} do
      patch(OpenaiEx.Files, :create, fn _, _ ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "file",
           "bytes" => 120_000,
           "created_at" => 1_677_610_602,
           "filename" => "mydata.jsonl",
           "purpose" => "fine-tune"
         }}
      end)

      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_upload.md")
      File.write!(file_path, "Test upload content")

      capture_log(fn ->
        assert {:ok, response} = OpenaiExWrapper.upload_file(client, file_path)
        assert response["id"] == "file-abc123"
      end)

      File.rm!(file_path)
    end

    test "successfully uploads file - async_connection false vector_store_id nil", %{
      client: client
    } do
      patch(OpenaiEx.Files, :create, fn _, _ ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "file",
           "bytes" => 120_000,
           "created_at" => 1_677_610_602,
           "filename" => "mydata.jsonl",
           "purpose" => "fine-tune"
         }}
      end)

      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_upload.md")
      File.write!(file_path, "Test upload content")

      capture_log(fn ->
        assert {:ok, response} =
                 OpenaiExWrapper.upload_file(client, file_path, %{async_connection: false})

        assert response["id"] == "file-abc123"
      end)

      File.rm!(file_path)
    end

    test "successfully uploads file - async_connection false vector_store_id vs_abc123", %{
      client: client
    } do
      created_file = %{
        "id" => "file-abc123",
        "object" => "file",
        "bytes" => 120_000,
        "created_at" => 1_677_610_602,
        "filename" => "mydata.jsonl",
        "purpose" => "fine-tune"
      }

      patch(OpenaiExWrapper, :connect_file_to_vector_store, fn _, _, _ ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "vector_store.file",
           "created_at" => 1_699_061_776,
           "usage_bytes" => 1234,
           "vector_store_id" => "vs_abc123",
           "status" => "queued",
           "last_error" => nil
         }}
      end)

      patch(OpenaiExWrapper, :check_status_on_vector_store_file_with_cache_buster, fn _,
                                                                                      _,
                                                                                      _,
                                                                                      attempts ->
        case attempts do
          0 ->
            {:ok,
             %{
               "status" => "in_progress",
               "id" => "file-abc123",
               "object" => "file",
               "bytes" => 120_000,
               "created_at" => 1_677_610_602,
               "filename" => "mydata.jsonl",
               "purpose" => "fine-tune"
             }}

          1 ->
            {:ok,
             %{
               "status" => "completed",
               "id" => "file-abc123",
               "object" => "file",
               "bytes" => 120_000,
               "created_at" => 1_677_610_602,
               "filename" => "mydata.jsonl",
               "purpose" => "fine-tune"
             }}
        end
      end)

      patch(OpenaiEx.Files, :create, fn _, _ ->
        {:ok, created_file}
      end)

      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_upload.md")
      File.write!(file_path, "Test upload content")

      capture_log(fn ->
        assert {:ok, response} =
                 OpenaiExWrapper.upload_file(client, file_path, %{
                   async_connection: false,
                   vector_store_id: "vs_abc123"
                 })

        assert response["id"] == "file-abc123"
      end)

      File.rm!(file_path)

      assert_called(
        OpenaiExWrapper.connect_file_to_vector_store(
          client,
          created_file,
          "vs_abc123"
        )
      )

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "file-abc123",
          "vs_abc123",
          0
        )
      )

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "file-abc123",
          "vs_abc123",
          1
        )
      )
    end

    test "successfully uploads file - async_connection true vector_store_id vs_abc123", %{
      client: client
    } do
      created_file = %{
        "id" => "file-abc123",
        "object" => "file",
        "bytes" => 120_000,
        "created_at" => 1_677_610_602,
        "filename" => "mydata.jsonl",
        "purpose" => "fine-tune"
      }

      patch(OpenaiExWrapper, :connect_file_to_vector_store, fn _, _, _ ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "vector_store.file",
           "created_at" => 1_699_061_776,
           "usage_bytes" => 1234,
           "vector_store_id" => "vs_abc123",
           "status" => "queued",
           "last_error" => nil
         }}
      end)

      patch(OpenaiEx.Files, :create, fn _, _ ->
        {:ok, created_file}
      end)

      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_upload.md")
      File.write!(file_path, "Test upload content")

      capture_log(fn ->
        assert {:ok, response} =
                 OpenaiExWrapper.upload_file(client, file_path, %{
                   async_connection: true,
                   vector_store_id: "vs_abc123"
                 })

        assert response["id"] == "file-abc123"
      end)

      File.rm!(file_path)

      assert_called(
        OpenaiExWrapper.connect_file_to_vector_store(
          client,
          created_file,
          "vs_abc123"
        )
      )

      # Verify we did NOT wait for processing
      refute_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "file-abc123",
          "vs_abc123",
          :_
        )
      )
    end

    test "successfully uploads file - async_connection true vector_store_id nil", %{
      client: client
    } do
      patch(OpenaiEx.Files, :create, fn _, _ ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "file",
           "bytes" => 120_000,
           "created_at" => 1_677_610_602,
           "filename" => "mydata.jsonl",
           "purpose" => "fine-tune"
         }}
      end)

      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_upload.md")
      File.write!(file_path, "Test upload content")

      capture_log(fn ->
        assert {:ok, response} =
                 OpenaiExWrapper.upload_file(client, file_path, %{async_connection: true})

        assert response["id"] == "file-abc123"
      end)

      File.rm!(file_path)
    end

    test "returns error for non-existent file", %{client: client} do
      assert {:error, _} = OpenaiExWrapper.upload_file(client, "/tmp/nonexistent_file.md")
    end
  end

  describe "upload_optional_file/3" do
    test "returns {:ok, nil} for empty string", %{client: client} do
      assert {:ok, nil} = OpenaiExWrapper.upload_optional_file(client, "")
    end

    test "returns {:ok, nil} for nil value", %{client: client} do
      assert {:ok, nil} = OpenaiExWrapper.upload_optional_file(client, nil)
    end

    test "returns {:ok, nil} for blank string", %{client: client} do
      assert {:ok, nil} = OpenaiExWrapper.upload_optional_file(client, "   ")
    end

    test "returns error for non-existent file", %{client: client} do
      assert {:error, _} =
               OpenaiExWrapper.upload_optional_file(client, "/tmp/nonexistent_file.md")
    end

    test "successfully uploads file when path is provided", %{client: client} do
      patch(OpenaiExWrapper, :upload_file, fn _, _file_path, _ ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "file",
           "bytes" => 120_000,
           "created_at" => 1_677_610_602,
           "filename" => "mydata.jsonl",
           "purpose" => "fine-tune"
         }}
      end)

      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_upload.md")
      File.write!(file_path, "Test upload content")

      assert {:ok, response} = OpenaiExWrapper.upload_optional_file(client, file_path)
      assert response["id"] == "file-abc123"

      assert_called(OpenaiExWrapper.upload_file(client, file_path, %{}))
      File.rm!(file_path)
    end

    test "successfully uploads file with options", %{client: client} do
      expected_options = %{
        vector_store_id: "vs_abc123",
        async_connection: true
      }

      patch(OpenaiExWrapper, :upload_file, fn _, _file_path, _options ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "file",
           "bytes" => 120_000,
           "created_at" => 1_677_610_602,
           "filename" => "mydata.jsonl",
           "purpose" => "fine-tune"
         }}
      end)

      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_upload.md")
      File.write!(file_path, "Test upload content")

      assert {:ok, response} =
               OpenaiExWrapper.upload_optional_file(client, file_path, expected_options)

      assert response["id"] == "file-abc123"

      assert_called(OpenaiExWrapper.upload_file(client, file_path, expected_options))
      File.rm!(file_path)
    end
  end

  describe "upload_optional_files/3" do
    test "handles nil file_paths", %{client: client} do
      assert {:ok, []} = OpenaiExWrapper.upload_optional_files(client, nil)
    end

    test "handles empty string file_paths", %{client: client} do
      assert {:ok, []} = OpenaiExWrapper.upload_optional_files(client, "")
    end

    test "returns empty list when file_paths is empty", %{client: client} do
      assert {:ok, []} = OpenaiExWrapper.upload_optional_files(client, [])
    end

    test "successfully uploads multiple files", %{client: client} do
      expected_options = %{
        vector_store_id: "vs_abc123",
        async_connection: true
      }

      patch(OpenaiExWrapper, :upload_file, fn _, file_path, _ ->
        {:ok,
         %{
           "id" => "file-#{Path.basename(file_path, ".md")}",
           "object" => "file",
           "bytes" => 120_000,
           "created_at" => 1_677_610_602,
           "filename" => "#{Path.basename(file_path, ".md")}.md",
           "purpose" => "fine-tune"
         }}
      end)

      temp_dir = System.tmp_dir!()

      file_paths = [
        Path.join(temp_dir, "test1.md"),
        Path.join(temp_dir, "test2.md")
      ]

      Enum.each(file_paths, &File.write!(&1, "Test upload content"))

      assert {:ok, responses} =
               OpenaiExWrapper.upload_optional_files(client, file_paths, expected_options)

      assert length(responses) == 2

      uploaded_files =
        responses
        |> Enum.map(& &1["filename"])
        |> Enum.sort()

      assert uploaded_files == ["test1.md", "test2.md"]

      Enum.each(file_paths, &File.rm!(&1))
      file_path1 = Enum.at(file_paths, 0)
      file_path2 = Enum.at(file_paths, 1)
      assert_called(OpenaiExWrapper.upload_file(client, ^file_path1, expected_options))
      assert_called(OpenaiExWrapper.upload_file(client, ^file_path2, expected_options))
    end

    test "successfully uploads mix of nil and valid file paths", %{client: client} do
      expected_options = %{
        vector_store_id: "vs_abc123",
        async_connection: true
      }

      patch(OpenaiExWrapper, :upload_file, fn _, file_path, _ ->
        {:ok,
         %{
           "id" => "file-#{Path.basename(file_path, ".md")}",
           "object" => "file",
           "bytes" => 120_000,
           "created_at" => 1_677_610_602,
           "filename" => "#{Path.basename(file_path, ".md")}.md",
           "purpose" => "fine-tune"
         }}
      end)

      temp_dir = System.tmp_dir!()
      file_path1 = Path.join(temp_dir, "test1.md")
      File.write!(file_path1, "Test upload content")

      file_paths = [
        "",
        "  ",
        nil,
        file_path1
      ]

      assert {:ok, responses} =
               OpenaiExWrapper.upload_optional_files(client, file_paths, expected_options)

      assert length(responses) == 1

      assert responses == [
               %{
                 "bytes" => 120_000,
                 "created_at" => 1_677_610_602,
                 "filename" => "test1.md",
                 "id" => "file-test1",
                 "object" => "file",
                 "purpose" => "fine-tune"
               }
             ]

      File.rm!(file_path1)

      assert_called(OpenaiExWrapper.upload_file(client, ^file_path1, expected_options))
    end

    test "cleans up files when upload fails", %{client: client} do
      patch(OpenaiExWrapper, :upload_file, fn _, file_path, _ ->
        if String.ends_with?(file_path, "test1.md") do
          {:ok,
           %{
             "id" => "file-123",
             "object" => "file",
             "bytes" => 120_000,
             "created_at" => 1_677_610_602,
             "filename" => "test1.md",
             "purpose" => "fine-tune"
           }}
        else
          {:error, "Upload failed"}
        end
      end)

      patch(OpenaiExWrapper, :delete_file_from_file_storage, fn _, file ->
        {:ok, file}
      end)

      temp_dir = System.tmp_dir!()

      file_paths = [
        Path.join(temp_dir, "test1.md"),
        Path.join(temp_dir, "test2.md")
      ]

      Enum.each(file_paths, &File.write!(&1, "Test upload content"))

      assert {:error, "Upload failed"} = OpenaiExWrapper.upload_optional_files(client, file_paths)

      Enum.each(file_paths, &File.rm!(&1))

      assert_called(
        OpenaiExWrapper.delete_file_from_file_storage(client, %{
          "id" => "file-123",
          "object" => "file",
          "bytes" => 120_000,
          "created_at" => 1_677_610_602,
          "filename" => "test1.md",
          "purpose" => "fine-tune"
        })
      )
    end
  end

  describe "get_openai_client/2" do
    test "creates client with default timeout when no timeout specified" do
      config = %{api_key: "sk-test123"}
      client = OpenaiExWrapper.get_openai_client(config)
      assert client.receive_timeout == 90_000
    end

    test "creates client with custom timeout when specified" do
      config = %{api_key: "sk-test123"}
      client = OpenaiExWrapper.get_openai_client(config, 120_000)
      assert client.receive_timeout == 120_000
    end

    test "creates client with organization key when provided" do
      config = %{api_key: "sk-test123", organization_key: "org-test123"}
      client = OpenaiExWrapper.get_openai_client(config)
      assert client.organization == "org-test123"
    end

    test "creates client with project key when provided" do
      config = %{api_key: "sk-test123", project_key: "proj-test123"}
      client = OpenaiExWrapper.get_openai_client(config)
      assert client.project == "proj-test123"
    end

    test "raises error when api key is missing" do
      config = %{organization_key: "org-test123"}

      assert_raise RuntimeError, "Missing OpenAI API key in config", fn ->
        OpenaiExWrapper.get_openai_client(config)
      end
    end
  end

  describe "clean_up_files/2" do
    test "handles nil files in list", %{client: client} do
      # Create test files
      temp_dir = System.tmp_dir!()
      file1_path = Path.join(temp_dir, "test1.txt")
      File.write!(file1_path, "Test content 1")

      # Mock file responses
      file1 = %{"id" => "file-1", "filename" => "test1.txt"}
      nil_file = nil

      # Mock file deletion responses
      patch(OpenaiEx.Files, :delete, fn _, id ->
        if id == "file-1", do: {:ok, %{"deleted" => true}}, else: {:error, "File not found"}
      end)

      # Clean up files
      capture_log(fn ->
        OpenaiExWrapper.clean_up_files(client, [file1, nil_file])
      end)

      # Verify only valid file is deleted
      assert_called(OpenaiEx.Files.delete(client, "file-1"))

      # Clean up local file
      File.rm!(file1_path)
    end

    test "handles file deletion errors", %{client: client} do
      # Create test files
      temp_dir = System.tmp_dir!()
      file1_path = Path.join(temp_dir, "test1.txt")
      file2_path = Path.join(temp_dir, "test2.txt")
      File.write!(file1_path, "Test content 1")
      File.write!(file2_path, "Test content 2")

      # Mock file responses
      file1 = %{"id" => "file-1", "filename" => "test1.txt"}
      file2 = %{"id" => "file-2", "filename" => "test2.txt"}

      # Mock file deletion responses with error for file2
      patch(OpenaiEx.Files, :delete, fn _, id ->
        case id do
          "file-1" -> {:ok, %{"deleted" => true}}
          "file-2" -> {:error, "Deletion failed"}
        end
      end)

      # Clean up files
      capture_log(fn ->
        OpenaiExWrapper.clean_up_files(client, [file1, file2])
      end)

      # Verify both files attempted deletion
      assert_called(OpenaiEx.Files.delete(client, "file-1"))
      assert_called(OpenaiEx.Files.delete(client, "file-2"))

      # Clean up local files
      File.rm!(file1_path)
      File.rm!(file2_path)
    end

    test "cleans up list of files", %{client: client} do
      # Create test files
      temp_dir = System.tmp_dir!()
      file1_path = Path.join(temp_dir, "test1.txt")
      file2_path = Path.join(temp_dir, "test2.txt")
      File.write!(file1_path, "Test content 1")
      File.write!(file2_path, "Test content 2")

      # Mock file responses
      file1 = %{"id" => "file-1", "filename" => "test1.txt"}
      file2 = %{"id" => "file-2", "filename" => "test2.txt"}

      # Mock file deletion responses
      patch(OpenaiEx.Files, :delete, fn _, id ->
        if id in ["file-1", "file-2"],
          do: {:ok, %{"deleted" => true}},
          else: {:error, "File not found"}
      end)

      # Clean up files
      capture_log(fn ->
        OpenaiExWrapper.clean_up_files(client, [file1, file2])
      end)

      # Verify files are deleted
      assert_called(OpenaiEx.Files.delete(client, "file-1"))
      assert_called(OpenaiEx.Files.delete(client, "file-2"))

      # Clean up local files
      File.rm!(file1_path)
      File.rm!(file2_path)
    end

    test "cleans up map of files", %{client: client} do
      # Create test files
      temp_dir = System.tmp_dir!()
      file1_path = Path.join(temp_dir, "test1.txt")
      file2_path = Path.join(temp_dir, "test2.txt")
      File.write!(file1_path, "Test content 1")
      File.write!(file2_path, "Test content 2")

      # Mock file responses
      file1 = %{"id" => "file-1", "filename" => "test1.txt"}
      file2 = %{"id" => "file-2", "filename" => "test2.txt"}

      # Mock file deletion responses
      patch(OpenaiEx.Files, :delete, fn _, id ->
        if id in ["file-1", "file-2"],
          do: {:ok, %{"deleted" => true}},
          else: {:error, "File not found"}
      end)

      # Clean up files
      capture_log(fn ->
        OpenaiExWrapper.clean_up_files(client, %{file1: file1, file2: file2})
      end)

      # Verify files are deleted
      assert_called(OpenaiEx.Files.delete(client, "file-1"))
      assert_called(OpenaiEx.Files.delete(client, "file-2"))

      # Clean up local files
      File.rm!(file1_path)
      File.rm!(file2_path)
    end
  end

  describe "delete_file_from_file_storage/2" do
    test "returns error when file deletion fails", %{client: client} do
      # Create test file
      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test.txt")
      File.write!(file_path, "Test content")

      # Mock file response
      file = %{"id" => "file-123", "filename" => "test.txt"}

      # Mock file deletion response to return error
      patch(OpenaiEx.Files, :delete, fn _, id ->
        if id == "file-123", do: {:error, "API Error"}, else: {:error, "File not found"}
      end)

      # Delete file
      capture_log(fn ->
        assert {:error, "OpenAI API call failed: \"API Error\""} =
                 OpenaiExWrapper.delete_file_from_file_storage(client, file)
      end)

      # Verify file deletion was attempted
      assert_called(OpenaiEx.Files.delete(client, "file-123"))

      # Clean up local file
      File.rm!(file_path)
    end

    test "deletes file by file map", %{client: client} do
      # Create test file
      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test.txt")
      File.write!(file_path, "Test content")

      # Mock file response
      file = %{"id" => "file-123", "filename" => "test.txt"}

      # Mock file deletion response
      patch(OpenaiEx.Files, :delete, fn _, id ->
        if id == "file-123", do: {:ok, %{"deleted" => true}}, else: {:error, "File not found"}
      end)

      # Mock file retrieval response
      patch(OpenaiEx.Files, :retrieve, fn _, id ->
        if id == "file-123", do: {:error, "File not found"}, else: {:ok, %{}}
      end)

      # Delete file
      capture_log(fn ->
        assert {:ok, _} = OpenaiExWrapper.delete_file_from_file_storage(client, file)
      end)

      # Verify file is deleted
      assert_called(OpenaiEx.Files.delete(client, "file-123"))

      # Clean up local file
      File.rm!(file_path)
    end

    test "deletes file by file ID", %{client: client} do
      # Create test file
      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test.txt")
      File.write!(file_path, "Test content")

      # Mock file response
      file_id = "file-123"

      # Mock file deletion response
      patch(OpenaiEx.Files, :delete, fn _, id ->
        if id == "file-123", do: {:ok, %{"deleted" => true}}, else: {:error, "File not found"}
      end)

      # Mock file retrieval response
      patch(OpenaiEx.Files, :retrieve, fn _, id ->
        if id == "file-123", do: {:error, "File not found"}, else: {:ok, %{}}
      end)

      # Delete file
      capture_log(fn ->
        assert {:ok, _} = OpenaiExWrapper.delete_file_from_file_storage(client, file_id)
      end)

      # Verify file is deleted
      assert_called(OpenaiEx.Files.delete(client, "file-123"))

      # Clean up local file
      File.rm!(file_path)
    end
  end

  describe "create_vector_store/2" do
    test "handles vector store creation error", %{client: client} do
      patch(OpenaiEx.Beta.VectorStores, :create, fn _, _ ->
        {:error, "Failed to create vector store"}
      end)

      assert {:error,
              "OpenAI API call failed: \"Failed to create vector store\" on vector store test_vector_store"} ==
               OpenaiExWrapper.create_vector_store(client, "test_vector_store")
    end

    test "successfully creates vector store", %{client: client} do
      patch(OpenaiEx.Beta.VectorStores, :create, fn _, _ ->
        {:ok, %{"id" => "test_vector_store_id", "status" => "completed"}}
      end)

      assert {:ok, %{"id" => "test_vector_store_id", "status" => "completed"}} ==
               OpenaiExWrapper.create_vector_store(client, "test_vector_store")
    end
  end

  describe "delete_vector_store/2" do
    test "successfully deletes vector store", %{client: client} do
      # Mock vector store response
      vector_store = %{"id" => "vs-123", "name" => "test_store"}

      # Mock vector store deletion response
      patch(OpenaiEx.Beta.VectorStores, :delete, fn _, id ->
        if id == "vs-123",
          do: {:ok, %{"deleted" => true}},
          else: {:error, "Vector store not found"}
      end)

      # Delete vector store
      capture_log(fn ->
        assert {:ok, _} = OpenaiExWrapper.delete_vector_store(client, vector_store)
      end)

      # Verify vector store is deleted
      assert_called(OpenaiEx.Beta.VectorStores.delete(client, "vs-123"))
    end

    test "returns error when vector store deletion fails", %{client: client} do
      # Mock vector store deletion response to return error
      patch(OpenaiEx.Beta.VectorStores, :delete, fn _, id ->
        if id == "vs-123", do: {:error, "API Error"}, else: {:error, "Vector store not found"}
      end)

      # Delete vector store
      assert {:error, "OpenAI API call failed: \"Vector store not found\" on vector store vs-xxx"} =
               OpenaiExWrapper.delete_vector_store(client, %{"id" => "vs-xxx"})

      # Verify vector store deletion was attempted
      assert_called(OpenaiEx.Beta.VectorStores.delete(client, "vs-xxx"))
    end

    test "deletes vector store by ID", %{client: client} do
      # Mock vector store ID
      vector_store_id = "vs-123"

      # Mock vector store deletion response
      patch(OpenaiEx.Beta.VectorStores, :delete, fn _, id ->
        if id == "vs-123",
          do: {:ok, %{"deleted" => true}},
          else: {:error, "Vector store not found"}
      end)

      # Delete vector store
      capture_log(fn ->
        assert {:ok, _} = OpenaiExWrapper.delete_vector_store(client, vector_store_id)
      end)

      # Verify vector store is deleted
      assert_called(OpenaiEx.Beta.VectorStores.delete(client, "vs-123"))
    end
  end

  describe "connect_file_to_vector_store/3" do
    test "successfully connects file to vector store with file id and vector store id", %{
      client: client
    } do
      response = %{"id" => "test_file_id", "status" => "completed"}

      patch(OpenaiEx.Beta.VectorStores.Files, :create, fn _, _, _ ->
        {:ok, response}
      end)

      capture_log(fn ->
        assert {:ok, response} ==
                 OpenaiExWrapper.connect_file_to_vector_store(
                   client,
                   "test_file_id",
                   "test_vector_store_id"
                 )
      end)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.create(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "successfully connects file to vector store with file map and vector store id", %{
      client: client
    } do
      file_map = %{"id" => "test_file_id"}

      patch(OpenaiEx.Beta.VectorStores.Files, :create, fn _, _, _ ->
        {:ok, %{"id" => "test_file_id", "status" => "completed"}}
      end)

      capture_log(fn ->
        assert {:ok, %{"id" => "test_file_id", "status" => "completed"}} =
                 OpenaiExWrapper.connect_file_to_vector_store(
                   client,
                   file_map,
                   "test_vector_store_id"
                 )
      end)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.create(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "successfully connects file to vector store with file id and vector store map", %{
      client: client
    } do
      vector_store_map = %{"id" => "test_vector_store_id"}

      patch(OpenaiEx.Beta.VectorStores.Files, :create, fn _, _, _ ->
        {:ok, %{"id" => "test_file_id", "status" => "completed"}}
      end)

      capture_log(fn ->
        assert {:ok, %{"id" => "test_file_id", "status" => "completed"}} =
                 OpenaiExWrapper.connect_file_to_vector_store(
                   client,
                   "test_file_id",
                   vector_store_map
                 )
      end)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.create(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "successfully connects file to vector store with file map and vector store map", %{
      client: client
    } do
      file_map = %{"id" => "test_file_id"}
      vector_store_map = %{"id" => "test_vector_store_id"}

      patch(OpenaiEx.Beta.VectorStores.Files, :create, fn _, _, _ ->
        {:ok, %{"id" => "test_file_id", "status" => "completed"}}
      end)

      assert {:ok, %{"id" => "test_file_id", "status" => "completed"}} =
               OpenaiExWrapper.connect_file_to_vector_store(
                 client,
                 file_map,
                 vector_store_map
               )

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.create(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "handles connection error", %{client: client} do
      patch(OpenaiEx.Beta.VectorStores.Files, :create, fn _, _, _ ->
        {:error, "Connection failed"}
      end)

      assert {:error,
              "OpenAI API call failed: \"Connection failed\" on file test_file_id to vector store test_vector_store_id"} =
               OpenaiExWrapper.connect_file_to_vector_store(
                 client,
                 "test_file_id",
                 "test_vector_store_id"
               )

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.create(client, "test_vector_store_id", "test_file_id")
      )
    end
  end

  describe "wait_for_vector_store_file_connection/3" do
    test "successfully waits for file connection with file id and vector store id", %{
      client: client
    } do
      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:ok, "completed"}
      end)

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok,
         %{
           "id" => "test_file_id",
           "vector_store_id" => "test_vector_store_id",
           "status" => "completed"
         }}
      end)

      capture_log(fn ->
        assert {:ok,
                %{
                  "id" => "test_file_id",
                  "vector_store_id" => "test_vector_store_id",
                  "status" => "completed"
                }} ==
                 OpenaiExWrapper.wait_for_vector_store_file_connection(
                   client,
                   "test_file_id",
                   "test_vector_store_id"
                 )
      end)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "successfully waits for file connection with file map and vector store id", %{
      client: client
    } do
      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:ok, "completed"}
      end)

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok, %{"id" => "test_file_id", "status" => "completed"}}
      end)

      file_map = %{"id" => "test_file_id"}

      capture_log(fn ->
        assert {:ok, _response} =
                 OpenaiExWrapper.wait_for_vector_store_file_connection(
                   client,
                   file_map,
                   "test_vector_store_id"
                 )
      end)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "successfully waits for file connection with file id and vector store map", %{
      client: client
    } do
      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:ok, "completed"}
      end)

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok, %{"id" => "test_file_id", "status" => "completed"}}
      end)

      vector_store_map = %{"id" => "test_vector_store_id"}

      capture_log(fn ->
        assert {:ok, _response} =
                 OpenaiExWrapper.wait_for_vector_store_file_connection(
                   client,
                   "test_file_id",
                   vector_store_map
                 )
      end)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "successfully waits for file connection with file map and vector store map", %{
      client: client
    } do
      file_map = %{"id" => "test_file_id", "status" => "completed"}

      vs_file_map = %{
        "id" => "file-abc123",
        "object" => "vector_store.file",
        "created_at" => 1_699_061_776,
        "vector_store_id" => "vs_abcd",
        "status" => "completed",
        "last_error" => nil
      }

      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:ok, "completed"}
      end)

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok,
         %{
           "id" => "file-abc123",
           "object" => "vector_store.file",
           "created_at" => 1_699_061_776,
           "vector_store_id" => "vs_abcd",
           "status" => "completed",
           "last_error" => nil
         }}
      end)

      vector_store_map = %{"id" => "test_vector_store_id"}

      capture_log(fn ->
        assert {:ok, vs_file_map} ==
                 OpenaiExWrapper.wait_for_vector_store_file_connection(
                   client,
                   file_map,
                   vector_store_map
                 )
      end)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(client, "test_vector_store_id", "test_file_id")
      )
    end

    test "handles failed status", %{client: client} do
      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:ok, "failed"}
      end)

      capture_log(fn ->
        assert {:error, "Vector store file connection failed"} =
                 OpenaiExWrapper.wait_for_vector_store_file_connection(
                   client,
                   "test_file_id",
                   "test_vector_store_id"
                 )
      end)
    end

    test "handles cancelled status", %{client: client} do
      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:ok, "cancelled"}
      end)

      capture_log(fn ->
        assert {:error, "Vector store file connection was cancelled"} =
                 OpenaiExWrapper.wait_for_vector_store_file_connection(
                   client,
                   "test_file_id",
                   "test_vector_store_id"
                 )
      end)
    end

    test "handles expired status", %{client: client} do
      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:ok, "expired"}
      end)

      assert {:error, "Vector store file connection expired"} =
               OpenaiExWrapper.wait_for_vector_store_file_connection(
                 client,
                 "test_file_id",
                 "test_vector_store_id"
               )
    end

    test "handles connection timeout", %{client: client} do
      patch(OpenaiExWrapper, :vector_store_poll_run_status, fn _, _, _, _, _ ->
        {:error, "Timeout waiting for vector store file connection"}
      end)

      assert {:error, "Timeout waiting for vector store file connection"} =
               OpenaiExWrapper.wait_for_vector_store_file_connection(
                 client,
                 "test_file_id",
                 "test_vector_store_id"
               )
    end
  end

  describe "vector_store_poll_run_status/4" do
    test "returns completed status", %{client: client} do
      patch(OpenaiExWrapper, :check_status_on_vector_store_file_with_cache_buster, fn _,
                                                                                      _,
                                                                                      _,
                                                                                      _ ->
        {:ok, %{"status" => "completed"}}
      end)

      assert {:ok, "completed"} =
               OpenaiExWrapper.vector_store_poll_run_status(
                 client,
                 "test_file_id",
                 "test_vector_store_id"
               )

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_file_id",
          "test_vector_store_id",
          0
        )
      )
    end

    test "returns error on timeout", %{client: client} do
      patch(OpenaiExWrapper, :check_status_on_vector_store_file_with_cache_buster, fn _,
                                                                                      _,
                                                                                      _,
                                                                                      _ ->
        # ALways in progress
        {:ok, %{"status" => "in_progress"}}
      end)

      fast_sleep_fn = fn _ -> {:ok} end

      capture_log(fn ->
        assert {:error, "Timeout waiting for vector store file connection"} =
                 OpenaiExWrapper.vector_store_poll_run_status(
                   client,
                   "test_file_id",
                   "test_vector_store_id",
                   0,
                   fast_sleep_fn
                 )
      end)

      0..9
      |> Enum.to_list()
      |> Enum.map(fn index ->
        assert_called(
          OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
            client,
            "test_file_id",
            "test_vector_store_id",
            ^index
          )
        )
      end)
    end

    test "handles in_progress status", %{client: client} do
      patch(OpenaiExWrapper, :check_status_on_vector_store_file_with_cache_buster, fn _,
                                                                                      _,
                                                                                      _,
                                                                                      attempts ->
        case attempts do
          0 -> {:ok, %{"status" => "in_progress"}}
          1 -> {:ok, %{"status" => "in_progress"}}
          2 -> {:ok, %{"status" => "in_progress"}}
          3 -> {:ok, %{"status" => "completed"}}
        end
      end)

      fast_sleep_fn = fn _ -> {:ok} end

      capture_log(fn ->
        assert {:ok, "completed"} =
                 OpenaiExWrapper.vector_store_poll_run_status(
                   client,
                   "test_id",
                   "vs_test",
                   1,
                   fast_sleep_fn
                 )
      end)

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_id",
          "vs_test",
          1
        )
      )

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_id",
          "vs_test",
          2
        )
      )

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_id",
          "vs_test",
          3
        )
      )
    end

    test "handles in_progress status exceeding max attempts", %{client: client} do
      patch(OpenaiExWrapper, :check_status_on_vector_store_file_with_cache_buster, fn _,
                                                                                      _,
                                                                                      _,
                                                                                      attempts ->
        if attempts >= 10 do
          {:error, "Timeout waiting for vector store file connection"}
        else
          {:ok, %{"status" => "in_progress"}}
        end
      end)

      fast_sleep_fn = fn _ -> {:ok} end

      capture_log(fn ->
        assert {:error, "Timeout waiting for vector store file connection"} =
                 OpenaiExWrapper.vector_store_poll_run_status(
                   client,
                   "test_id",
                   "vs_test",
                   0,
                   fast_sleep_fn
                 )
      end)

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_id",
          "vs_test",
          10
        )
      )
    end

    test "handles queued status transitioning to completed", %{client: client} do
      patch(
        OpenaiExWrapper,
        :check_status_on_vector_store_file_with_cache_buster,
        sequence([
          {:ok, %{"status" => "queued"}},
          {:ok, %{"status" => "queued"}},
          {:ok, %{"status" => "completed"}}
        ])
      )

      fast_sleep_fn = fn _ -> {:ok} end

      capture_log(fn ->
        assert {:ok, "completed"} =
                 OpenaiExWrapper.vector_store_poll_run_status(
                   client,
                   "test_id",
                   "vs_test",
                   0,
                   fast_sleep_fn
                 )
      end)

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_id",
          "vs_test",
          0
        )
      )
    end

    test "handles failed status", %{client: client} do
      patch(OpenaiExWrapper, :check_status_on_vector_store_file_with_cache_buster, fn _,
                                                                                      _,
                                                                                      _,
                                                                                      _ ->
        {:ok, %{"status" => "failed"}}
      end)

      capture_log(fn ->
        assert {:ok, "failed"} =
                 OpenaiExWrapper.vector_store_poll_run_status(client, "test_id", "vs_test", 1)
      end)

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_id",
          "vs_test",
          1
        )
      )
    end

    test "handles cancelled status", %{client: client} do
      patch(OpenaiExWrapper, :check_status_on_vector_store_file_with_cache_buster, fn _,
                                                                                      _,
                                                                                      _,
                                                                                      _ ->
        {:ok, %{"status" => "cancelled"}}
      end)

      assert {:ok, "cancelled"} =
               OpenaiExWrapper.vector_store_poll_run_status(client, "test_id", "vs_test", 1)

      assert_called(
        OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
          client,
          "test_id",
          "vs_test",
          1
        )
      )
    end
  end

  describe "check_status_on_vector_store_file_with_cache_buster/4" do
    test "respects cache buster argument", %{client: client} do
      patch(OpenaiEx.Http, :get, fn _, _, params ->
        assert params[:cache_buster] == "test_file_id-5"
        {:ok, %{"status" => "completed"}}
      end)

      assert {:ok, %{"status" => "completed"}} =
               OpenaiExWrapper.check_status_on_vector_store_file_with_cache_buster(
                 client,
                 "test_file_id",
                 "test_vector_store_id",
                 5
               )

      assert_called(
        OpenaiEx.Http.get(client, "/vector_stores/test_vector_store_id/files/test_file_id", %{
          cache_buster: "test_file_id-5"
        })
      )
    end
  end

  describe "get_file_from_vector_store/3" do
    test "handles file_map and vector_store_map", %{client: client} do
      file_map = %{"id" => "test_file_id"}
      vector_store_map = %{"id" => "test_vector_store_id"}
      expected_response = %{"status" => "completed"}

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok, expected_response}
      end)

      assert {:ok, ^expected_response} =
               OpenaiExWrapper.get_file_from_vector_store(client, file_map, vector_store_map)

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(
          client,
          "test_vector_store_id",
          "test_file_id"
        )
      )
    end

    test "handles file_id and vector_store_map", %{client: client} do
      vector_store_map = %{"id" => "test_vector_store_id"}
      expected_response = %{"status" => "completed"}

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok, expected_response}
      end)

      assert {:ok, ^expected_response} =
               OpenaiExWrapper.get_file_from_vector_store(
                 client,
                 "test_file_id",
                 vector_store_map
               )

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(
          client,
          "test_vector_store_id",
          "test_file_id"
        )
      )
    end

    test "handles file_map and vector_store_id", %{client: client} do
      file_map = %{"id" => "test_file_id"}
      expected_response = %{"status" => "completed"}

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok, expected_response}
      end)

      assert {:ok, ^expected_response} =
               OpenaiExWrapper.get_file_from_vector_store(
                 client,
                 file_map,
                 "test_vector_store_id"
               )

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(
          client,
          "test_vector_store_id",
          "test_file_id"
        )
      )
    end

    test "successfully retrieves file from vector store", %{client: client} do
      expected_response = %{
        "id" => "test_file_id",
        "object" => "vector_store.file",
        "created_at" => 1_699_061_776,
        "usage_bytes" => 1234,
        "vector_store_id" => "test_vector_store_id",
        "status" => "completed",
        "last_error" => nil
      }

      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:ok, expected_response}
      end)

      assert {:ok, retrieved_file} =
               OpenaiExWrapper.get_file_from_vector_store(
                 client,
                 "test_file_id",
                 "test_vector_store_id"
               )

      assert retrieved_file == expected_response

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(
          client,
          "test_vector_store_id",
          "test_file_id"
        )
      )
    end

    test "handles retrieval error", %{client: client} do
      patch(OpenaiEx.Beta.VectorStores.Files, :retrieve, fn _, _, _ ->
        {:error, "Retrieval failed"}
      end)

      assert {:error,
              "OpenAI API call failed: \"Retrieval failed\" on file test_file_id from vector store test_vector_store_id"} =
               OpenaiExWrapper.get_file_from_vector_store(
                 client,
                 "test_file_id",
                 "test_vector_store_id"
               )

      assert_called(
        OpenaiEx.Beta.VectorStores.Files.retrieve(
          client,
          "test_vector_store_id",
          "test_file_id"
        )
      )
    end
  end

  describe "get_message_from_response/1" do
    test "extracts first message from response" do
      response = %{
        "output" => [
          %{
            "content" => [
              %{
                "id" => "fs_67f8420b4cc48192a848c780787582c003bf89c0d15417fc",
                "queries" => ["epic 10", "MailBoxer features", "TOTM_Report", "MJFOP_Report"],
                "results" => nil,
                "status" => "completed",
                "type" => "file_search_call"
              },
              %{"text" => "First message"},
              %{"text" => "Last message"}
            ]
          }
        ]
      }

      assert "First message" == OpenaiExWrapper.get_message_from_response(response)
    end
  end

  describe "create_response/3" do
    test "successfully creates response", %{client: client} do
      full_response = %{
        "created_at" => 1_744_323_134,
        "error" => nil,
        "id" => "resp_67f8423e55a88192adf41d2cafd55f870491664035f89670",
        "incomplete_details" => nil,
        "instructions" => "  You are an expert product owner and agile facilitator.",
        "max_output_tokens" => 75_000,
        "metadata" => %{},
        "model" => "gpt-4o-mini-2024-07-18",
        "object" => "response",
        "output" => [
          %{
            "id" => "fs_67f8423fdd70819294c4a19fe0dd69fe0491664035f89670",
            "queries" => [
              "What are the missing stories in TOTM_Report.md?",
              "What are the missing stories in MJFOP_Report.md?"
            ],
            "results" => nil,
            "status" => "completed",
            "type" => "file_search_call"
          },
          %{
            "content" => [
              %{
                "annotations" => [],
                "text" => "Test Story",
                "type" => "output_text"
              }
            ],
            "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89670",
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
        "tools" => [
          %{
            "filters" => nil,
            "max_num_results" => 20,
            "ranking_options" => %{"ranker" => "auto", "score_threshold" => 0.0},
            "type" => "file_search",
            "vector_store_ids" => ["vs_67f841f62b1c8191ab295b276a3fdea9"]
          }
        ],
        "top_p" => 1.0,
        "truncation" => "disabled",
        "usage" => %{
          "input_tokens" => 45_525,
          "input_tokens_details" => %{"cached_tokens" => 16_512},
          "output_tokens" => 348,
          "output_tokens_details" => %{"reasoning_tokens" => 0},
          "total_tokens" => 45_873
        },
        "user" => nil
      }

      patch(OpenaiEx.Responses, :create, fn _, _ ->
        {:ok, full_response}
      end)

      input = [%{role: "user", content: "Test message"}]

      capture_log(fn ->
        assert {:ok, response, conversation} = OpenaiExWrapper.create_response(client, input)

        assert response == full_response

        assert(
          conversation == [
            %{role: "user", content: "Test message"},
            %{
              "content" => [
                %{"annotations" => [], "text" => "Test Story", "type" => "output_text"}
              ],
              "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89670",
              "role" => "assistant",
              "status" => "completed",
              "type" => "message"
            }
          ]
        )
      end)

      assert_called(OpenaiEx.Responses.create(client, input))
    end

    test "handles error when creating response", %{client: client} do
      patch(OpenaiEx.Responses, :create, fn _, _ -> {:error, "API request failed"} end)

      input = [%{role: "user", content: "Test message"}]

      capture_log(fn ->
        assert {:error, "API request failed"} = OpenaiExWrapper.create_response(client, input)
      end)

      assert_called(OpenaiEx.Responses.create(client, input))
    end

    test "maintains conversation context across multiple responses", %{client: client} do
      patch(
        OpenaiEx.Responses,
        :create,
        sequence([
          {:ok,
           %{
             "id" => "resp_67f8423e55a88192adf41d2cafd55f870491664035f89670",
             "output" => [
               %{
                 "id" => "fs_67f8423fdd70819294c4a19fe0dd69fe0491664035f89670",
                 "queries" => [
                   "What are the missing stories in TOTM_Report.md?",
                   "What are the missing stories in MJFOP_Report.md?"
                 ],
                 "results" => nil,
                 "status" => "completed",
                 "type" => "file_search_call"
               },
               %{
                 "content" => [
                   %{
                     "annotations" => [],
                     "text" => "Test Story",
                     "type" => "output_text"
                   }
                 ],
                 "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89670",
                 "role" => "assistant",
                 "status" => "completed",
                 "type" => "message"
               }
             ]
           }},
          {:ok,
           %{
             "id" => "resp_67f8423e55a88192adf41d2cafd55f870491664035f89675",
             "output" => [
               %{
                 "content" => [
                   %{
                     "annotations" => [],
                     "text" => "Followup Story",
                     "type" => "output_text"
                   }
                 ],
                 "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89675",
                 "role" => "assistant",
                 "status" => "completed",
                 "type" => "message"
               }
             ]
           }}
        ])
      )

      initial_input = [%{role: "user", content: "What is 2+2?"}]

      capture_log(fn ->
        assert {:ok, response1, conversation1} =
                 OpenaiExWrapper.create_response(client, initial_input)

        assert response1 == %{
                 "id" => "resp_67f8423e55a88192adf41d2cafd55f870491664035f89670",
                 "output" => [
                   %{
                     "id" => "fs_67f8423fdd70819294c4a19fe0dd69fe0491664035f89670",
                     "queries" => [
                       "What are the missing stories in TOTM_Report.md?",
                       "What are the missing stories in MJFOP_Report.md?"
                     ],
                     "results" => nil,
                     "status" => "completed",
                     "type" => "file_search_call"
                   },
                   %{
                     "content" => [
                       %{"annotations" => [], "text" => "Test Story", "type" => "output_text"}
                     ],
                     "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89670",
                     "role" => "assistant",
                     "status" => "completed",
                     "type" => "message"
                   }
                 ]
               }

        assert conversation1 == [
                 %{content: "What is 2+2?", role: "user"},
                 %{
                   "content" => [
                     %{"annotations" => [], "text" => "Test Story", "type" => "output_text"}
                   ],
                   "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89670",
                   "role" => "assistant",
                   "status" => "completed",
                   "type" => "message"
                 }
               ]

        follow_up = conversation1 ++ [%{role: "user", content: "What about 3+3?"}]

        assert {:ok, response2, conversation2} =
                 OpenaiExWrapper.create_response(client, follow_up)

        assert response2 == %{
                 "id" => "resp_67f8423e55a88192adf41d2cafd55f870491664035f89675",
                 "output" => [
                   %{
                     "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89675",
                     "status" => "completed",
                     "type" => "message",
                     "content" => [
                       %{"annotations" => [], "text" => "Followup Story", "type" => "output_text"}
                     ],
                     "role" => "assistant"
                   }
                 ]
               }

        assert conversation2 == [
                 %{content: "What is 2+2?", role: "user"},
                 %{
                   "content" => [
                     %{"annotations" => [], "text" => "Test Story", "type" => "output_text"}
                   ],
                   "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89670",
                   "role" => "assistant",
                   "status" => "completed",
                   "type" => "message"
                 },
                 %{content: "What about 3+3?", role: "user"},
                 %{
                   "content" => [
                     %{"annotations" => [], "text" => "Followup Story", "type" => "output_text"}
                   ],
                   "id" => "msg_67f8424368748192b797cdcfd98951060491664035f89675",
                   "role" => "assistant",
                   "status" => "completed",
                   "type" => "message"
                 }
               ]

        assert length(conversation2) > length(conversation1)
        assert response1 != response2
      end)

      assert_called(OpenaiEx.Responses.create(client, initial_input))
      assert_called(OpenaiEx.Responses.create(client, follow_up))
    end
  end

  describe "delete_response/2" do
    test "successfully deletes response", %{client: client} do
      patch(OpenaiEx.Responses, :delete, fn _, _ ->
        {:ok, %{"id" => "test_response_id", "deleted" => true}}
      end)

      capture_log(fn ->
        assert {:ok, "Response deleted"} =
                 OpenaiExWrapper.delete_response(client, "test_response_id")
      end)

      assert_called(OpenaiEx.Responses.delete(client, response_id: "test_response_id"))
    end

    test "successfully deletes response with response map", %{client: client} do
      patch(OpenaiEx.Responses, :delete, fn _, _ ->
        {:ok, %{"id" => "test_response_id", "deleted" => true}}
      end)

      capture_log(fn ->
        assert {:ok, "Response deleted"} =
                 OpenaiExWrapper.delete_response(client, %{"id" => "test_response_id"})
      end)

      assert_called(OpenaiEx.Responses.delete(client, response_id: "test_response_id"))
    end

    test "returns error when response does not exist", %{client: client} do
      patch(OpenaiEx.Responses, :delete, fn _, _ ->
        {:error, "Response not found"}
      end)

      assert {:error, "OpenAI API call failed: \"Response not found\""} =
               OpenaiExWrapper.delete_response(client, "nonexistent_id")

      assert_called(OpenaiEx.Responses.delete(client, response_id: "nonexistent_id"))
    end
  end
end
