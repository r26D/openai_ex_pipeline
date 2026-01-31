defmodule OpenaiExPipeline do
  @moduledoc """
  OpenaiExPipeline provides an idiomatic Elixir interface on top of the OpenaiEx library.

  This module wraps OpenaiEx's functionality in a more Elixir-friendly way, providing:
  - Streamlined API interactions
  - Better error handling
  - More intuitive function signatures
  - Consistent response formats

  It maintains all the core functionality of OpenaiEx while making it more natural to use
  in an Elixir application.

  ## Chat Completions (GPT-4 / GPT-5)

  Use `OpenaiExPipeline.Chat.Completions` as the single entry point for OpenAI Chat
  Completions "create" (and streaming create). It normalizes requests for GPT-5 (e.g.
  max_output_tokens → max_completion_tokens, no max_input_tokens, no stop for gpt-5).
  """


end
