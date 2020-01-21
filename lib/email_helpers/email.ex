defmodule Mailibex.EmailHelpers.Email do
  @moduledoc """
  Some premade functions to help with Email parsing
  """

  @doc """
  Expects raw e-mail data as input.
  Returns `%MimeMail.Flat{}`
  """
  def parse(raw_data) do
    raw_data
    |> MimeMail.from_string()
    |> MimeMail.Flat.from_mail()
  end
end
