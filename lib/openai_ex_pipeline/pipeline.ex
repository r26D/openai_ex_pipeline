defmodule OpenaiExPipeline.Pipeline do
  @moduledoc """
  Pipeline functions for API operations.
  """
  require Logger
  alias OpenaiExPipeline.OpenaiExWrapper

  @doc """
  Initializes the resources map with default values.

  ## Parameters
    - openai_client: The OpenAI client instance

  ## Returns
    A map containing initialized resources
  """
  def init_resources(openai_client) do
    %{
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

  @doc """
  Removes an output message at the specified index.

  ## Parameters
    - token: The pipeline token containing resources
    - index: The index of the output message to remove

  ## Returns
    - `{:error, token}` if the token is an error
    - `{:ok, updated_resources}` with the output message removed
  """
  def remove_output_messages({:error, _} = token, _index), do: token

  def remove_output_messages({:ok, %{output_messages: output_messages} = resources}, index) do
    {:ok, %{resources | output_messages: List.delete_at(output_messages, index)}}
  end

  @doc """
  Removes conversation entries at the specified index or range.

  ## Parameters
    - token: The pipeline token containing resources
    - range_val: Either an index or a Range of indices to remove

  ## Returns
    - `{:error, token}` if the token is an error
    - `{:ok, updated_resources}` with the conversation entries removed
  """
  def remove_conversation({:error, _} = token, _index), do: token

  def remove_conversation({:ok, %{conversation: conversation} = resources}, range_val)
      when is_struct(range_val, Range) do
    updated_converation =
      conversation
      |> Enum.with_index()
      |> Enum.reject(fn {_val, idx} -> idx in range_val end)
      |> Enum.map(fn {val, _idx} -> val end)

    {:ok, %{resources | conversation: updated_converation}}
  end

  def remove_conversation({:ok, %{conversation: conversation} = resources}, index) do
    {:ok, %{resources | conversation: List.delete_at(conversation, index)}}
  end

  @doc """
  Creates a vector store with the given name.

  ## Parameters
    - token: The pipeline token containing resources
    - vector_store_name: The name for the new vector store

  ## Returns
    - `{:error, error}` if the token is an error or vector store already exists
    - `{:ok, updated_resources}` with the new vector store
  """
  @spec create_vector_store(
          {:error, any()}
          | {:ok, %{:openai_client => any(), :vector_store => any(), optional(any()) => any()}},
          any()
        ) ::
          {:error, any()}
          | {:ok, %{:openai_client => any(), :vector_store => any(), optional(any()) => any()}}
  def create_vector_store({:error, _} = error, _), do: error

  def create_vector_store(
        {:ok, %{vector_store: vector_store, openai_client: openai_client} = resources},
        vector_store_name
      ) do
    if vector_store do
      {:error, %{resources | error: "Vector store already exists"}}
    else
      case OpenaiExWrapper.create_vector_store(openai_client, vector_store_name) do
        {:ok, vector_store} ->
          {:ok, %{resources | vector_store: vector_store}}

        {:error, reason} ->
          {:error, %{resources | error: reason}}
      end
    end
  end

  @doc """
  Uploads multiple files to the vector store in parallel.

  ## Parameters
    - token: The pipeline token containing resources
    - file_list: List of maps where each map has :label and :file keys
      Example: [%{label: :my_label, file: "path/to/file.md", optional: false}]
    - options: Map of options (defaults to %{async_connection: false})

  ## Returns
    - `{:ok, updated_resources}` on success
    - `{:error, error_resources}` on failure
  """
  def upload_files(token, file_list, options \\ %{async_connection: false})
  def upload_files({:error} = token, _file_list, _options), do: token

  def upload_files({:ok, resources}, file_list, options) do
    upload_tasks =
      Enum.map(file_list, fn file_info ->
        Task.async(fn ->
          case Map.get(file_info, :optional) do
            true ->
              upload_optional_file(
                {:ok, resources},
                file_info.label,
                Map.get(file_info, :file),
                options
              )

            _ ->
              upload_file({:ok, resources}, file_info.label, file_info.file, options)
          end
        end)
      end)

    # Wait for all uploads to complete
    results = Task.await_many(upload_tasks, :infinity)

    updated_resources =
      Enum.reduce(results, resources, fn {_, %{files: new_files}}, acc ->
        %{acc | files: Map.merge(acc[:files], new_files)}
      end)

    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil ->
        Logger.info(
          IO.ANSI.green() <>
            "\tAll files uploaded successfully" <> IO.ANSI.reset()
        )

        {:ok, updated_resources}

      {:error, %{error: reason}} ->
        {:error, %{updated_resources | error: reason}}
    end
  end

  @doc """
  Uploads a file to the vector store.

  ## Parameters
    - token: The pipeline token containing resources
    - file_label: The label for the file
    - file_name: The path to the file
    - options: Map of options (defaults to %{async_connection: false})

  ## Returns
    - `{:error, error}` if the token is an error or file doesn't exist
    - `{:ok, updated_resources}` with the uploaded file
  """
  def upload_file(
        token,
        file_label,
        file_name,
        options \\ %{async_connection: false}
      )

  def upload_file({:error, _} = error, _, _, _), do: error

  def upload_file(
        {:ok,
         %{files: files, vector_store: vector_store, openai_client: openai_client} = resources},
        file_label,
        file_name,
        options
      ) do
    case Map.get(files, file_label) do
      nil ->
        file_options =
          case is_nil(vector_store) do
            true -> %{}
            false -> %{vector_store_id: vector_store["id"]}
          end
          |> Map.put(:async_connection, get_in(options, [:async_connection]))

        if File.exists?(file_name) do
          Logger.info(
            IO.ANSI.green() <>
              "\tUploading file: #{file_label}" <> IO.ANSI.reset()
          )

          case OpenaiExWrapper.upload_file(openai_client, Path.expand(file_name), file_options) do
            {:ok, uploaded_file} ->
              {:ok, %{resources | files: Map.put(files, file_label, uploaded_file)}}

            {:error, reason} ->
              {:error, %{resources | error: reason}}
          end
        else
          Logger.warning("File does not exist: #{file_name}")
          {:error, %{resources | error: "File does not exist: #{file_name}"}}
        end

      _ ->
        {:ok, resources}
    end
  end

  @doc """
  Uploads an optional file to the vector store.

  ## Parameters
    - token: The pipeline token containing resources
    - file_label: The label for the file
    - file_name: The path to the file
    - options: Map of options (defaults to %{async_connection: false})

  ## Returns
    - `{:error, error}` if the token is an error
    - `{:ok, resources}` if the file is blank
    - `{:ok, updated_resources}` with the uploaded file
  """
  def upload_optional_file(
        token,
        file_label,
        file_name,
        options \\ %{async_connection: false}
      )

  def upload_optional_file({:error, _} = error, _, _, _), do: error

  def upload_optional_file(
        {:ok, resources},
        file_label,
        file_name,
        options
      ) do
    case OpenaiExWrapper.blank?(file_name) do
      true ->
        Logger.info(
          IO.ANSI.yellow() <>
            "\tOptional file #{file_label} not provided" <> IO.ANSI.reset()
        )

        {:ok, resources}

      false ->
        upload_file({:ok, resources}, file_label, file_name, options)
    end
  end

  @doc """
  Uploads multiple optional files to the vector store.

  ## Parameters
    - token: The pipeline token containing resources
    - incoming_files: List of file paths to upload
    - options: Map of options (defaults to %{async_connection: false})

  ## Returns
    - `{:error, error}` if the token is an error
    - `{:ok, updated_resources}` with the uploaded files
  """
  def upload_optional_files(
        token,
        incoming_files,
        options \\ %{async_connection: false}
      )

  def upload_optional_files({:error, _} = error, _, _), do: error

  def upload_optional_files(
        token,
        incoming_files,
        options
      ) do
    incoming_files
    |> Enum.filter(fn file_path ->
      case OpenaiExWrapper.blank?(file_path) do
        true -> false
        false -> File.exists?(file_path)
      end
    end)
    |> Enum.map(fn file_path ->
      %{label: Path.basename(file_path), file: file_path}
    end)
    |> then(fn remaining_files ->
      upload_files(token, remaining_files, options)
    end)
  end

  @doc """
  Confirms that all files have been processed by the vector store.

  ## Parameters
    - token: The pipeline token containing resources

  ## Returns
    - `{:error, error}` if the token is an error
    - `{:ok, resources}` if there are no files or no vector store
    - `{:ok, updated_resources}` with processed files
  """
  def confirm_vector_store_processing({:error, _} = error), do: error

  def confirm_vector_store_processing({:ok, %{vector_store: nil} = resources}),
    do: {:ok, resources}

  def confirm_vector_store_processing({:ok, %{files: []} = resources}), do: {:ok, resources}

  def confirm_vector_store_processing(
        {:ok,
         %{openai_client: openai_client, vector_store: vector_store, files: files} = resources}
      ) do
    files
    |> Enum.reduce_while(
      {:ok, resources},
      fn {file_label, file}, {:ok, %{files: current_files}} ->
        case OpenaiExWrapper.wait_for_vector_store_file_connection(
               openai_client,
               get_in(file, ["id"]),
               get_in(vector_store, ["id"])
             ) do
          {:ok, vector_store_file} ->
            Logger.info(
              IO.ANSI.green() <>
                "\t#{file_label} processed at Vector Store" <> IO.ANSI.reset()
            )

            updated_file = Map.put(file, "vector_store_file", vector_store_file)
            updated_files = Map.put(current_files, file_label, updated_file)
            {:cont, {:ok, %{resources | files: updated_files}}}

          {:error, reason} ->
            {:halt, {:error, %{resources | error: reason}}}
        end
      end
    )
    |> tap(fn {_status, %{files: files}} ->
      Logger.info(
        IO.ANSI.green() <>
          "\t****************\n\t #{Enum.count(files)} files uploaded to Vector Store" <>
          IO.ANSI.reset()
      )
    end)
  end

  @doc """
  Creates a response using the OpenAI API.

  ## Parameters
    - token: The pipeline token containing resources
    - input: The input for the API call (function or list)
    - api_options: Options for the API call
    - options: Additional options (defaults to %{})

  ## Returns
    - `{:error, error}` if the token is an error or input is invalid
    - `{:ok, updated_resources}` with the API response
  """
  def create_response(_token, _input, _api_options, options \\ %{})
  def create_response({:error, _} = error, _, _, _), do: error

  def create_response(
        {:ok, resources},
        input,
        _api_options,
        _options
      )
      when not (is_function(input, 1) or is_list(input)) do
    {:error, %{resources | error: "Request input must be a function or a list"}}
  end

  def create_response(
        {:ok, %{openai_client: openai_client, conversation: previous_conversation} = resources},
        input,
        api_options,
        options
      ) do
    current_conversation = build_conversation(previous_conversation, input, resources)

    case is_list(current_conversation) do
      false ->
        {:error,
         %{resources | error: "Conversation must be a list #{inspect(current_conversation)}"}}

      true ->
        full_api_options = build_api_options(api_options, options, resources)
        # Logger.debug("Full API Options: #{inspect(full_api_options)}")

        case OpenaiExWrapper.create_response(
               openai_client,
               current_conversation,
               full_api_options
             ) do
          {:ok, response, conversation} ->
            output_message = OpenaiExWrapper.get_message_from_response(response)

            {:ok,
             %{
               resources
               | responses: resources.responses ++ [response],
                 output_messages: resources.output_messages ++ [output_message],
                 conversation: conversation
             }}

          {:error, reason} ->
            {:error, %{resources | error: reason}}
        end
    end
  end

  defp build_conversation(_conversation, input, resources) when is_function(input, 1) do
    input.(resources)
  end

  defp build_conversation(conversation, input, _) do
    conversation ++ input
  end

  defp build_api_options(api_options, %{with_file_search: true}, %{vector_store: vector_store})
       when not is_nil(vector_store) do
    api_options
    |> Map.put(:tools, [%{type: "file_search", vector_store_ids: [vector_store["id"]]}])
  end

  defp build_api_options(api_options, _, _), do: api_options

  @doc """
  Cleans up resources by deleting vector stores, files, and responses.

  ## Parameters
    - token: The pipeline token containing resources to clean up
      The token should contain:
      - openai_client: The OpenAI client instance
      - responses: List of responses to delete
      - files: Map of files to delete
      - vector_store: Vector store to delete

  ## Returns
    - The original token after cleanup operations
    - Note: This function performs cleanup operations but does not modify the token's structure

  ## Examples
      iex> token = {:ok, %{openai_client: client, responses: [response], files: %{file1: file}, vector_store: store}}
      iex> Pipeline.cleanup_resources(token)
      {:ok, %{...}}
  """
  def cleanup_resources(
        {_,
         %{
           openai_client: openai_client,
           responses: responses,
           files: files,
           vector_store: vector_store
         }} = token
      ) do
    delete_vector_store(openai_client, vector_store)
    OpenaiExWrapper.delete_vector_store(openai_client, vector_store)

    Enum.each(files, fn {_, file} ->
      OpenaiExWrapper.delete_file_from_file_storage(openai_client, file)
    end)

    Enum.each(responses, fn response ->
      OpenaiExWrapper.delete_response(openai_client, response)
    end)

    token
  end

  defp delete_vector_store(_, nil), do: {:ok, ""}

  defp delete_vector_store(openai_client, vector_store) do
    case OpenaiExWrapper.delete_vector_store(openai_client, vector_store) do
      {:ok, _} ->
        {:ok, "Vector store deleted"}

      {:error, reason} ->
        {:error, "OpenAI API call failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Retrieves the output messages from the pipeline token.

  ## Parameters
    - token: The pipeline token containing resources

  ## Returns
    - `{:error, error}` if the token contains an error
    - `{:ok, output_messages}` with the list of output messages on success

  ## Examples
      iex> token = {:ok, %{output_messages: ["message1", "message2"]}}
      iex> Pipeline.get_output(token)
      {:ok, ["message1", "message2"]}

      iex> token = {:error, %{error: "Something went wrong"}}
      iex> Pipeline.get_output(token)
      {:error, "Something went wrong"}
  """

  def get_output({:error, %{error: error}}) do
    {:error, error}
  end

  def get_output({:ok, %{output_messages: output_messages}}) do
    {:ok, output_messages}
  end

  @doc """
  Joins a list of names using Oxford comma style.

  ## Parameters
    - names: List of names to join

  ## Returns
    A string with the names joined using Oxford comma style
  """
  def oxford_join(names) do
    names
    |> Enum.reject(&(&1 in [nil, ""]))
    |> do_oxford_join()
  end

  defp do_oxford_join([]), do: ""
  defp do_oxford_join([name]), do: name
  defp do_oxford_join([name1, name2]), do: "#{name1} and #{name2}"

  defp do_oxford_join(names) do
    {init, last} = Enum.split(names, -1)
    Enum.join(init, ", ") <> ", and " <> "#{List.first(last)}"
  end

  @doc """
  Updates the data field in the pipeline resources.

  ## Parameters
    - token: The pipeline token containing resources
    - data_to_update: Map of data to merge into the existing data field

  ## Returns
    - `{:error, error}` if the token contains an error
    - `{:ok, updated_resources}` with the merged data on success

  ## Examples
      iex> token = {:ok, %{data: %{key1: "value1"}}}
      iex> Pipeline.update_data(token, %{key2: "value2"})
      {:ok, %{data: %{key1: "value1", key2: "value2"}}}

      iex> token = {:error, %{error: "Something went wrong"}}
      iex> Pipeline.update_data(token, %{key: "value"})
      {:error, %{error: "Something went wrong"}}
  """

  def update_data({:error, _} = error, _), do: error

  def update_data({:ok, %{data: data} = token}, data_to_update) do
    {:ok, %{token | data: Map.merge(data, data_to_update)}}
  end

  @doc """
  Uploads an output message as a file to OpenAI's file storage.

  Takes an output message from the pipeline's output_messages list and creates a temporary file
  with that content, then uploads it to OpenAI.

  WARNING: The file_key parameter will be used as both the temporary filename and the filename
  for the OpenAI upload. It must have a file extension that OpenAI accepts (e.g. .txt, .md, .json).

  ## Parameters
    - token: The pipeline token containing resources
    - file_key: The filename to use for the temporary and uploaded file (e.g. "epics.md")
    - output_message_index: Index of the output message to upload
    - options: Optional map of parameters
      - :async_connection - If true, will not wait for vector store processing (default: false)
      - :remove_from_conversation - expects an index or a range of indexes to remove from the conversation (default: nil)
      - :remove_from_output_messages? - If true, removes message from output_messages after upload (default: false)

  ## Returns
    - `{:ok, updated_resources}` on successful upload
    - `{:error, reason}` if upload fails or output_message_index is invalid
  """
  def upload_output_message_as_file(
        token,
        file_key,
        output_message_index,
        options \\ %{
          async_connection: false,
          remove_from_conversation: nil,
          remove_from_output_messages?: false
        }
      )

  def upload_output_message_as_file({:error, _} = error, _, _, _options), do: error

  def upload_output_message_as_file(
        {:ok,
         %{
           output_messages: output_messages
         } = resources},
        file_key,
        output_message_index,
        options
      ) do
    case Enum.at(output_messages, output_message_index) do
      nil ->
        {:error, %{resources | error: "Invalid output message index: #{output_message_index}"}}

      output_message ->
        # Create a temporary file with the output message content
        temp_file_path = Path.join(System.tmp_dir!(), file_key)
        File.write!(temp_file_path, output_message)

        # Upload the temporary file
        case upload_file({:ok, resources}, file_key, temp_file_path, options) do
          {:ok, updated_resources} ->
            # Clean up the temporary file
            File.rm!(temp_file_path)

            {:ok, updated_resources}
            |> prune_conversation(options[:remove_from_conversation])
            |> prune_output_messages(options[:remove_from_output_messages?], output_message_index)

          error ->
            # Clean up the temporary file even if upload fails
            File.rm!(temp_file_path)
            error
        end
    end
  end

  # defp prune_conversation({:error, _} = error, _), do: error
  defp prune_conversation(token, nil),
    do: token

  defp prune_conversation(token, conversation_index),
    do: remove_conversation(token, conversation_index)

  # defp prune_output_messages({:error, _} = error, _, _output_message_index), do: error

  defp prune_output_messages(token, true, output_message_index),
    do: remove_output_messages(token, output_message_index)

  defp prune_output_messages(token, _, _output_message_index),
    do: token

  @doc """
  Merges two resource maps together, combining lists and preserving other values.

  ## Parameters
    - resources: The base resources map
    - new_resources: The new resources map to merge with

  ## Returns
    A merged resources map where:
    - :conversation lists are concatenated
    - :output_messages lists are concatenated
    - :responses lists are concatenated
    - All other values are taken from the base resources map

  ## Examples
      iex> base = %{conversation: [1, 2], output_messages: ["a"], responses: [%{}], files: %{}}
      iex> new = %{conversation: [3, 4], output_messages: ["b"], responses: [%{}], files: %{}}
      iex> Pipeline.merge_resources(base, new)
      %{conversation: [1, 2, 3, 4], output_messages: ["a", "b"], responses: [%{}, %{}], files: %{}}
  """

  def merge_resources(resources, new_resources) do
    Map.merge(resources, new_resources, fn
      :conversation, conv1, conv2 -> conv1 ++ conv2
      :output_messages, msg1, msg2 -> msg1 ++ msg2
      :responses, r1, r2 -> r1 ++ r2
      _k, v1, _v2 -> v1
    end)
  end
end
