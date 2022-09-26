defmodule Notesclub.Workers.ContentSyncWorker do
  use Oban.Worker,
    queue: :default,
    unique: [period: 300, states: [:available, :scheduled, :executing]]

  alias Notesclub.Notebooks
  alias Notesclub.Notebooks.Notebook

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notebook_id" => notebook_id}}) do
    notebook = Notebooks.get_notebook(notebook_id, preload: [:user, :repo])

    notebook
    |> raw_url()
    |> make_request()
    |> save_content(notebook)
  end

  # Notebook doesn't exists, skipping
  def raw_url(nil), do: nil

  def raw_url(%Notebook{} = notebook) do
    raw_url(%{
      url: notebook.url,
      username: notebook.user.username,
      repo_name: notebook.repo.name
    })
  end

  def raw_url(%{url: url, username: username, repo_name: repo_name}) do
    url
    |> String.replace(
      ~r/^https:\/\/github\.com\/#{username}\/#{repo_name}\/blob/,
      "https://raw.githubusercontent.com/#{username}/#{repo_name}"
    )
  end

  defp make_request(nil), do: nil
  defp make_request(url) do
    case __MODULE__.requests_enabled?() do
      true ->
        Req.get!(url)
      _ ->
        %Req.Response{
          status: 200,
          body: "whatever txt"
        }
    end
  end

  # Notebook doesn't exists, skipping
  defp save_content(nil, _), do: :ok

  defp save_content(response, %Notebook{} = notebook) do
    Notebooks.update_notebook(notebook, %{content: response.body})
  end

  # Public function so it can be mocked
  def requests_enabled?() do
    case Mix.env() do
      :test -> false
      _ -> true
    end
  end
end