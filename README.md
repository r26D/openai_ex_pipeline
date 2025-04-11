# OpenaiExPipeline

[![Hex.pm](https://img.shields.io/hexpm/v/openai_ex_pipeline.svg)](https://hex.pm/packages/openai_ex_pipeline)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/openai_ex_pipeline/)
[![License](https://img.shields.io/hexpm/l/openai_ex_pipeline.svg)](https://github.com/r26d/openai_ex_pipeline/blob/main/LICENSE.md)

OpenaiExPipeline is an Elixir library that provides an idiomatic interface on top of the [OpenaiEx](https://github.com/cyberchitta/openai_ex) library. This project is not affiliated with or endorsed by the OpenaiEx project, but follows its package naming conventions for consistency.

## Why OpenaiExPipeline?

While OpenaiEx provides a solid foundation for interacting with OpenAI's API, OpenaiExPipeline adds several Elixir-specific enhancements:

- Pipeline-friendly interface for composing operations
- Simplified error handling and cleanup
- Asynchronous file uploads and vector store operations
- Built-in support for testing with Patch and ExVCR
- Helper modules for integration testing

## Installation

Add `openai_ex_pipeline` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:openai_ex_pipeline, "~> 0.0.1"}
  ]
end
```

## Usage

### Basic Pipeline Example

```elixir
alias OpenaiExPipeline.Pipeline

# Initialize the pipeline with an OpenAI client
client = OpenaiEx.new()

# Create a vector store and upload files
result = 
  Pipeline.init_resources(client)
  |> Pipeline.create_vector_store("my-store")
  |> Pipeline.upload_files([
    %{label: :document, file: "path/to/document.md"},
    %{label: :readme, file: "README.md"}
  ])
  |> Pipeline.create_response(
           fn _r ->
                [
                    %{
                        role: "user",
                        content: """
                        What is the capital of Texas?
                        """}
                ]
           end,
            %{
                frequency_penalty: 0.0,
                instructions: "You are a helpful ai!",
                max_output_tokens: 75_000,
                max_tokens: 180_000,
                model: "4o-mini",
                presence_penalty: 0.0,
                temperature: 0.7,
                top_p: 1.0,
                truncation: "disabled"
                },
           %{with_file_search: true}
         )
          |> Pipeline.cleanup_resources()
         |> Pipeline.get_output()
# Handle the result
case result do
  {:ok, %{vector_store: store, files: files}} -> 
    IO.puts("Successfully created store: #{store["id"]}")
    IO.puts("Uploaded files: #{inspect(files)}")
  {:error, %{error: reason}} -> 
    IO.puts("Error: #{reason}")
end
```

### Asynchronous Operations

The library will upload all the files in individual tasks in parallel. Then it can check on them at the end to make sure they have all processed at the vector store.

```elixir
alias OpenaiExPipeline.Pipeline

# Initialize the pipeline
client = OpenaiEx.new()
resources = Pipeline.init_resources(client)

# Upload files asynchronously
result = 
  resources
  |> Pipeline.create_vector_store("async-store")
  |> Pipeline.upload_files([
    %{label: :doc1, file: "doc1.md"},
    %{label: :doc2, file: "doc2.md"}
  ], %{async_connection: true})
  |> Pipeline.confirm_vector_store_processing()
     |> Pipeline.cleanup_resources()

case result do
  {:ok, %{vector_store: store, files: files}} ->
    IO.puts("Store created: #{store["id"]}")
    IO.puts("Files uploaded: #{inspect(files)}")
  {:error, %{error: reason}} ->
    IO.puts("Error: #{reason}")
end
```

### Error Handling and Cleanup

```elixir
alias OpenaiExPipeline.Pipeline

# Initialize the pipeline
client = OpenaiEx.new()
resources = Pipeline.init_resources(client)

# The pipeline will automatically handle errors and cleanup
result = 
  resources
  |> Pipeline.create_vector_store("error-handling-store")
  |> Pipeline.upload_files([
    %{label: :valid, file: "valid.md"},
    %{label: :invalid, file: "nonexistent.md"}
  ])
  |> Pipeline.confirm_vector_store_processing()

case result do
  {:ok, %{vector_store: store, files: files}} ->
    IO.puts("Success: #{inspect(store)}")
  {:error, %{error: reason}} ->
    IO.puts("Error occurred: #{reason}")
    # Resources are automatically cleaned up
end
```

## Testing

OpenaiExPipeline includes helper modules to make testing easier:

- `OpenAIMatcher`: Helps create test matchers for OpenAI responses
- `ExVCR` adapter: Simplifies recording and replaying API interactions


The library itself uses Patch to handle tests. In your project, it can be nice to have integration tests
that mock out the calls to OpenAI but can be pointed at the real thing if you need to confirm
everything is working as expected. This is especially important with OpenAI since they don't provide any
free testing sandbox to point at.   The best tool for that job is ExVCR.  It needed some addition code to
get it to handle Finch, file uploads, and some get requests that get cached incorrectly. All the code you need
to setup testing is included in this library.

Example test setup:

```elixir
defmodule MyApp.OpenAITest do
  use ExUnit.Case
  import OpenaiExPipeline.ExVCR.OpenaiMatchers
  use ExVCR.Mock, adapter: OpenaiExPipeline.ExVCR.Adapter.Finch, options: [clear_mock: true]
  test "processes files through pipeline" do
    use_cassette "file_processing" do
     use_cassette "processes_files_through_#{test_name}",
        custom_matchers: [
          &match_openai_api_request/3
        ] do
      client = OpenaiEx.new()
      resources = OpenaiExPipeline.Pipeline.init_resources(client)
      
      result = 
        resources
        |> OpenaiExPipeline.Pipeline.create_vector_store("test-store")
        |> OpenaiExPipeline.Pipeline.upload_files([
          %{label: :test_file, file: "test.md"}
        ])
        |> OpenaiExPipeline.Pipeline.confirm_vector_store_processing()

      assert {:ok, %{vector_store: store}} = result
      assert store["id"] != nil
      end
    end
  end
end
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. 

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## Acknowledgments

- Thanks to the [OpenaiEx](https://github.com/cyberchitta/openai_ex) project for providing the foundation. 
- Inspired by the needs of the r26D command-line tool
