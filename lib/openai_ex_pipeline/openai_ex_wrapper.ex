defmodule OpenaiExPipeline.OpenaiExWrapper do
  @moduledoc """
  OpenaiExWrapper functions for API operations.
  """
  require Logger
  alias OpenaiEx.Beta

  @openai_client_timeout 90_000

  # Change back to 90
  @polling_timeout_in_seconds 10
  @doc """
  Checks if a string is blank (nil or empty after trimming).
  Returns `true` if the string is nil or empty after trimming, `false` otherwise.
  """
  def blank?(nil), do: true
  def blank?(str), do: String.trim(str) == ""

  @doc """
  Removes OpenAI citations from the content.
  Returns `{:ok, filtered_content}` or `{:error, reason}`
  """
  def filter_content(content) do
    filtered = Regex.replace(~r/【.*?】/, content, "")
    {:ok, filtered}
  end

  @doc """
  Lists all files from OpenAI's file storage.

  ## Parameters
    - client: OpenAI client

  ## Returns
    - `{:ok, files}` - List of files on success
    - `{:error, reason}` - Error message on failure
  """
  def list_files(client) do
    case OpenaiEx.Files.list(client) do
      {:ok, %{"data" => files}} ->
        # Logger.debug("Files: #{inspect(files)}")
        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all vector stores from OpenAI.

  ## Parameters
    - client: OpenAI client

  ## Returns
    - `{:ok, vector_stores}` - List of vector stores on success
    - `{:error, reason}` - Error message on failure
  """
  def list_vector_stores(client) do
    case Beta.VectorStores.list(client) do
      {:ok, %{"data" => vector_stores}} ->
        {:ok, vector_stores}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Uploads a file to OpenAI's file storage and optionally connects it to a vector store.

  ## Parameters
    - openai_client: OpenAI client
    - file_path: Path to the file to upload
    - options: Optional map of parameters
      - :vector_store_id - If provided, will attempt to connect the uploaded file
        to the specified vector store after upload
      - :aysnc_connection - if true, will not wait for the vector store connection to complete, defaults to false
  ## Returns
    - `{:ok, upload_response}` on successful upload (and connection if vector_store_id provided)
    - `{:error, reason}` if upload or vector store connection fails
  """

  def upload_file(openai_client, file_path, options \\ %{async_connection: false}) do
    upload_req = build_local_file_upload_request(file_path)

    try do
      case OpenaiEx.Files.create(openai_client, upload_req) do
        {:ok, upload_res} ->
          handle_async_connection(
            get_in(options[:async_connection]),
            get_in(options[:vector_store_id]),
            openai_client,
            upload_res
          )

        {:error, reason} ->
          {:error, "OpenAI API call failed: #{inspect(reason)} on file #{file_path}"}
      end
    rescue
      e in File.Error ->
        {:error, "File error: #{Exception.message(e)}"}
    end
  end

  defp handle_async_connection(_, nil, _, upload_res), do: {:ok, upload_res}

  defp handle_async_connection(false, vector_store_id, openai_client, upload_res) do
    Logger.info(
      IO.ANSI.light_black() <>
        "\t\tWaiting for file to be processed at Vector Store" <> IO.ANSI.reset()
    )

    connect_file_and_wait_for_processing(
      openai_client,
      upload_res,
      vector_store_id
    )
  end

  defp handle_async_connection(true, vector_store_id, openai_client, upload_res) do
    case connect_file_to_vector_store(
           openai_client,
           upload_res,
           vector_store_id
         ) do
      {:ok, _} ->
        {:ok, upload_res}

      {:error, reason} ->
        {:error, "OpenAI API call failed: #{inspect(reason)} on file #{upload_res["filename"]}"}
    end
  end

  defp connect_file_and_wait_for_processing(_openai_client, upload_res, nil),
    do: {:ok, upload_res}

  defp connect_file_and_wait_for_processing(openai_client, upload_res, vector_store_id)
       when is_binary(vector_store_id) do
    case connect_file_to_vector_store(openai_client, upload_res, vector_store_id) do
      {:ok, _} ->
        wait_for_vector_store_file_connection(
          openai_client,
          upload_res,
          vector_store_id
        )

        {:ok, upload_res}

      {:error, reason} ->
        {:error,
         "OpenAI API call failed: Unable to connect file to vector store #{inspect(reason)} on file #{upload_res["filename"]}"}
    end
  end

  @doc """
  Uploads a file to OpenAI if a valid file path is provided.

  ## Parameters
    - openai_client: The OpenAI client instance
    - file_path: The path to the file to upload
    - options: Additional options for the upload (default: %{})

  ## Returns
    - `{:ok, nil}` - If file_path is empty, nil, or blank
    - `{:ok, upload_response}` - If file upload is successful
    - `{:error, reason}` - If file does not exist or upload fails

  ## Examples
      iex> OpenaiExWrapper.upload_optional_file(client, "")
      {:ok, nil}

      iex> OpenaiExWrapper.upload_optional_file(client, nil)
      {:ok, nil}

      iex> OpenaiExWrapper.upload_optional_file(client, "path/to/file.md")
      {:ok, %{"id" => "file-abc123", ...}}
  """

  def upload_optional_file(openai_client, file_path, options \\ %{})
  def upload_optional_file(_openai_client, "", _options), do: {:ok, nil}
  def upload_optional_file(_openai_client, nil, _options), do: {:ok, nil}

  def upload_optional_file(openai_client, file_path, options) do
    case blank?(file_path) do
      true -> {:ok, nil}
      false -> upload_file(openai_client, file_path, options)
    end
  end

  @doc """
  Uploads multiple optional files to OpenAI.

  Takes a list of file paths and uploads each one. If any upload fails, all previously
  uploaded files will be automatically deleted to prevent orphaned files.

  Returns:
  - `{:ok, [uploads]}` - List of successful file uploads
  - `{:error, reason}` - Error message if any upload fails. Previously uploaded files will be deleted.
  """
  def upload_optional_files(openai_client, file_path, options \\ %{})
  def upload_optional_files(_openai_client, "", _options), do: {:ok, []}
  def upload_optional_files(_openai_client, nil, _options), do: {:ok, []}

  def upload_optional_files(openai_client, file_paths, options) when is_list(file_paths) do
    case file_paths do
      [] ->
        {:ok, []}

      paths ->
        paths
        |> Enum.reject(&blank?/1)
        |> Enum.reduce_while(
          {:ok, []},
          fn file_path, {:ok, acc} ->
            # Logger.info("Uploading file: #{file_path}")
            do_upload_optional_files(openai_client, file_path, options, {:ok, acc})
          end
        )
    end
  end

  defp do_upload_optional_files(openai_client, paths, options, {:ok, acc}) do
    case upload_file(openai_client, paths, options) do
      {:ok, upload} ->
        {:cont, {:ok, [upload | acc]}}

      {:error, reason} ->
        # Clean up any files already uploaded
        Enum.each(acc, fn file -> delete_file_from_file_storage(openai_client, file) end)
        {:halt, {:error, reason}}
    end
  end

  defp build_local_file_upload_request(file_path) do
    fine_tune_file = OpenaiEx.new_file(path: file_path)
    OpenaiEx.Files.new_upload(file: fine_tune_file, purpose: "assistants")
  end

  @doc """
  Creates a new OpenAI client with optional configuration.

  ## Parameters
    - config: Map containing OpenAI configuration
      - :api_key - OpenAI API key (required)
      - :organization_key - OpenAI organization key (optional)
      - :project_key - OpenAI project key (optional)
    - openai_client_timeout: Timeout in milliseconds for API requests (defaults to 90,000)

  ## Returns
    - OpenAI client configured with the provided settings

  ## Examples
      iex> config = %{api_key: "sk-123", organization_key: "org-123"}
      iex> client = OpenaiExWrapper.get_openai_client(config)
      iex> client.receive_timeout
      90000
  """

  def get_openai_client(config, openai_client_timeout \\ @openai_client_timeout) do
    api_key = config[:api_key] || raise "Missing OpenAI API key in config"
    org_key = config[:organization_key]
    project_key = config[:project_key]

    OpenaiEx.new(api_key, org_key, project_key)
    |> OpenaiEx.with_receive_timeout(openai_client_timeout)
  end

  def clean_up_files(openai_client, files) when is_list(files) do
    Enum.each(files, fn file ->
      cond do
        is_list(file) ->
          clean_up_files(openai_client, file)

        is_nil(file) ->
          {:ok}

        true ->
          Logger.info("Deleting file: #{inspect(file["filename"])}")

          delete_file_from_file_storage(openai_client, file)
      end
    end)
  end

  def clean_up_files(openai_client, files) when is_map(files) do
    clean_up_files(openai_client, Map.values(files))
  end

  @doc """
  Deletes a file from OpenAI's file storage.

  ## Parameters
    - client: OpenAI client
    - file: File map containing the file ID to delete

  ## Returns
    - `{:ok, response}` on success
    - `{:error, reason}` on failure
  """

  def delete_file_from_file_storage(openai_client, %{"id" => file_id}),
    do: delete_file_from_file_storage(openai_client, file_id)

  def delete_file_from_file_storage(openai_client, file_id) do
    case OpenaiEx.Files.delete(openai_client, file_id) do
      {:ok, response} ->
        Logger.info(
          IO.ANSI.red() <>
            "\tFile deleted - #{file_id}" <> IO.ANSI.reset()
        )

        {:ok, response}

      {:error, reason} ->
        {:error, "OpenAI API call failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Creates a new vector store with the given name.

  ## Parameters
    - openai_client: OpenAI client
    - vector_store_name: Name of the vector store to create

  ## Returns
    - `{:ok, vector_store_res}` - Vector store response on success
    - `{:error, reason}` - Error message on failure
  """
  def create_vector_store(openai_client, vector_store_name) do
    case Beta.VectorStores.create(
           openai_client,
           Beta.VectorStores.new(name: vector_store_name)
         ) do
      {:ok, vector_store_res} ->
        {:ok, vector_store_res}

      {:error, reason} ->
        {:error,
         "OpenAI API call failed: #{inspect(reason)} on vector store #{vector_store_name}"}
    end
  end

  @doc """
  Deletes a vector store by ID.

  ## Parameters
    - openai_client: OpenAI client
    - vector_store_id: ID of the vector store to delete (can be a map with "id" key or the ID string)

  ## Returns
    - `{:ok, "Vector store deleted"}` - Success message on successful deletion
    - `{:error, reason}` - Error message on failure
  """
  def delete_vector_store(openai_client, %{"id" => vector_store_id}) do
    delete_vector_store(openai_client, vector_store_id)
  end

  def delete_vector_store(openai_client, vector_store_id) do
    case Beta.VectorStores.delete(openai_client, vector_store_id) do
      {:ok, _} ->
        Logger.warning(
          IO.ANSI.red() <>
            "\tVector store deleted - #{vector_store_id}" <> IO.ANSI.reset()
        )

        {:ok, "Vector store deleted"}

      {:error, reason} ->
        {:error, "OpenAI API call failed: #{inspect(reason)} on vector store #{vector_store_id}"}
    end
  end

  @doc """
  Connects a file to a vector store.

  ## Parameters
    - openai_client: OpenAI client
    - file_id: ID of the file to connect (can be a map with "id" key or the ID string)
    - vector_store_id: ID of the vector store (can be a map with "id" key or the ID string)

  ## Returns
    - `{:ok, response}` - Response on successful connection
    - `{:error, reason}` - Error message on failure
  """
  def connect_file_to_vector_store(openai_client, %{"id" => file_id}, %{"id" => vector_store_id}) do
    connect_file_to_vector_store(openai_client, file_id, vector_store_id)
  end

  def connect_file_to_vector_store(openai_client, file_id, %{"id" => vector_store_id}) do
    connect_file_to_vector_store(openai_client, file_id, vector_store_id)
  end

  def connect_file_to_vector_store(openai_client, %{"id" => file_id}, vector_store_id) do
    connect_file_to_vector_store(openai_client, file_id, vector_store_id)
  end

  def connect_file_to_vector_store(openai_client, file_id, vector_store_id) do
    case Beta.VectorStores.Files.create(openai_client, vector_store_id, file_id) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error,
         "OpenAI API call failed: #{inspect(reason)} on file #{file_id} to vector store #{vector_store_id}"}
    end
  end

  @doc """
  Waits for a file to be processed in a vector store.

  ## Parameters
    - client: OpenAI client
    - file_id: ID of the file (can be a map with "id" key or the ID string)
    - vector_store_id: ID of the vector store (can be a map with "id" key or the ID string)

  ## Returns
    - `{:ok, vs_file}` - Vector store file on successful processing
    - `{:error, reason}` - Error message on failure
  """
  def wait_for_vector_store_file_connection(client, %{"id" => file_id}, %{"id" => vector_store_id}) do
    wait_for_vector_store_file_connection(client, file_id, vector_store_id)
  end

  def wait_for_vector_store_file_connection(client, file_id, %{"id" => vector_store_id}) do
    wait_for_vector_store_file_connection(client, file_id, vector_store_id)
  end

  def wait_for_vector_store_file_connection(client, %{"id" => file_id}, vector_store_id) do
    wait_for_vector_store_file_connection(client, file_id, vector_store_id)
  end

  def wait_for_vector_store_file_connection(client, file_id, vector_store_id) do
    case vector_store_poll_run_status(client, file_id, vector_store_id) do
      {:ok, "completed"} ->
        # Logger.debug("File processed at vector store")
        get_file_from_vector_store(client, file_id, vector_store_id)

      {:ok, "failed"} ->
        {:error, "Vector store file connection failed"}

      {:ok, "cancelled"} ->
        {:error, "Vector store file connection was cancelled"}

      {:ok, "expired"} ->
        {:error, "Vector store file connection expired"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_sleep_fn(ms), do: Process.sleep(ms)

  def vector_store_poll_run_status(
        client,
        file_id,
        vector_store_id,
        attempts \\ 0,
        sleep_fn \\ &default_sleep_fn/1
      ) do
    case check_status_on_vector_store_file_with_cache_buster(
           client,
           file_id,
           vector_store_id,
           attempts
         ) do
      {:ok, %{"status" => "completed"} = _run} ->
        {:ok, "completed"}

      {:ok, %{"status" => "failed"} = _run} ->
        {:ok, "failed"}

      {:ok, %{"status" => "cancelled"} = _run} ->
        {:ok, "cancelled"}

      {:ok, %{"status" => "expired"} = _run} ->
        {:ok, "expired"}

      {:ok, %{"status" => "queued"} = _run} ->
        sleep_fn.(1000)
        vector_store_poll_run_status(client, file_id, vector_store_id, 0, sleep_fn)

      {:ok, %{"status" => "in_progress"} = _run} ->
        if attempts < @polling_timeout_in_seconds do
          Logger.info(
            IO.ANSI.light_black() <>
              "\t\tWaiting for vector store file connection to complete Attempt #{attempts}" <>
              IO.ANSI.reset()
          )

          sleep_fn.(1000)

          vector_store_poll_run_status(client, file_id, vector_store_id, attempts + 1, sleep_fn)
        else
          # raise "Timeout waiting for vector store file connection"
          {:error, "Timeout waiting for vector store file connection"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds a cache buster parameter to vector store file status requests to prevent caching issues.

  This function is used to work around caching problems when recording and replaying
  requests with ExVCR. By adding a unique cache buster parameter to each request,
  we ensure that each request is treated as unique and not cached.

  ## Parameters
    - client: The OpenAI client
    - file_id: The ID of the file in the vector store
    - vector_store_id: The ID of the vector store

  ## Returns
    - `{:ok, response}` on success
    - `{:error, reason}` on failure
  """

  def check_status_on_vector_store_file_with_cache_buster(
        client,
        file_id,
        vector_store_id,
        attempts
      ) do
    cache_buster = "#{file_id}-#{attempts}"
    # Logger.debug("#{file_id} - Cache buster: #{cache_buster}")
    base_url = "/vector_stores/#{vector_store_id}/files/#{file_id}"

    # Logger.debug("Url will be  #{OpenaiEx.Http.build_url(base_url, %{cache_buster: cache_buster})}")

    client
    |> OpenaiEx.with_assistants_beta()
    |> OpenaiEx.Http.get(base_url, %{
      cache_buster: cache_buster
    })
  end

  @doc """
  Retrieves a file from a vector store.

  ## Parameters
    - client: OpenAI client
    - file_id: ID of the file (can be a map with "id" key or the ID string)
    - vector_store_id: ID of the vector store (can be a map with "id" key or the ID string)

  ## Returns
    - `{:ok, vs_file}` - Vector store file on success
    - `{:error, reason}` - Error message on failure
  """
  def get_file_from_vector_store(client, %{"id" => file_id}, %{"id" => vector_store_id}) do
    get_file_from_vector_store(client, file_id, vector_store_id)
  end

  def get_file_from_vector_store(client, file_id, %{"id" => vector_store_id}) do
    get_file_from_vector_store(client, file_id, vector_store_id)
  end

  def get_file_from_vector_store(client, %{"id" => file_id}, vector_store_id) do
    get_file_from_vector_store(client, file_id, vector_store_id)
  end

  def get_file_from_vector_store(client, file_id, vector_store_id) do
    case Beta.VectorStores.Files.retrieve(client, vector_store_id, file_id) do
      {:ok, vs_file} ->
        {:ok, vs_file}

      {:error, reason} ->
        {:error,
         "OpenAI API call failed: #{inspect(reason)} on file #{file_id} from vector store #{vector_store_id}"}
    end
  end

  @doc """
  Extracts the message content from an OpenAI response.

  ## Parameters
    - response: OpenAI API response

  ## Returns
    - String containing the message content
  """
  def get_message_from_response(response) do
    response
    |> get_output_message_from_response()
    |> Map.get("content")
    |> Enum.find(&Map.has_key?(&1, "text"))
    |> Map.get("text")
  end

  @doc """
  Creates a response using the OpenAI API.

  ## Parameters
    - openai_client: OpenAI client
    - input: Input for the response
    - params: Additional parameters (default: %{})

  ## Returns
    - `{:ok, response, conversation}` - Response and conversation on success
    - `{:error, reason}` - Error message on failure
  """
  def create_response(openai_client, input, params \\ %{}) do
    pretty_log_input(input)

    case OpenaiEx.Responses.create(openai_client, Map.merge(params, %{input: input})) do
      {:ok, response} ->
        # Logger.debug("ConversationResponse: #{inspect(response)}")
        {:ok, response, build_conversation(response, input)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_conversation(reponse, input) do
    input
    |> Enum.concat(List.wrap(get_output_message_from_response(reponse)))
    |> Enum.reject(&is_nil(&1))
  end

  defp get_output_message_from_response(%{"output" => output}) do
    Enum.find(output, &Map.has_key?(&1, "content"))
  end

  @doc """
  Deletes a response from OpenAI.

  ## Parameters
    - openai_client: OpenAI client
    - response_id: ID of the response to delete (can be a map with "id" key or the ID string)

  ## Returns
    - `{:ok, "Response deleted"}` - Success message on successful deletion
    - `{:error, reason}` - Error message on failure
  """
  def delete_response(openai_client, %{"id" => response_id}) do
    delete_response(openai_client, response_id)
  end

  def delete_response(openai_client, response_id) do
    case OpenaiEx.Responses.delete(openai_client, response_id: response_id) do
      {:ok, _} ->
        Logger.warning(
          IO.ANSI.red() <>
            "\tResponse deleted - #{response_id}" <> IO.ANSI.reset()
        )

        {:ok, "Response deleted"}

      {:error, reason} ->
        {:error, "OpenAI API call failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Logs input messages in a formatted way.

  ## Parameters
    - input: List of input messages to log
  """
  def pretty_log_input(input) do
    Enum.each(input, fn item ->
      # Print role in green if it exists
      if Map.has_key?(item, :role) do
        Logger.info(IO.ANSI.green() <> "\tRole: #{item[:role]}" <> IO.ANSI.reset())
      end

      # Print content with newlines if it exists
      if Map.has_key?(item, :content) do
        Logger.info("\tContent:")

        item[:content]
        |> String.split("\n")
        |> Enum.each(fn line ->
          line
          |> String.graphemes()
          |> Enum.chunk_every(80)
          |> Enum.map(&Enum.join/1)
          |> tab_space_slices()
        end)
      end
    end)
  end

  defp tab_space_slices(slices) do
    slices
    |> Enum.with_index()
    |> Enum.each(fn {slice, index} ->
      tab_space_slice(slice, index)
    end)
  end

  defp tab_space_slice(slice, index) do
    prefix = if index == 0, do: "\t", else: "\t\t"
    Logger.info("#{prefix}#{slice}")
  end
end
