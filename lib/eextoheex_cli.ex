defmodule EexToHeex.CLI do
  require Logger

  def main(args \\ []) do
    if length(args) < 2 do
      bad_usage()
    end

    cmd = Enum.at(args, 0)

    paths = Enum.drop(args, 1)

    case cmd do
      "check" ->
        check_all_templates(paths)

      "convert" ->
        convert_all_templates(paths)

      "run" ->
        run(paths)

      _ ->
        bad_usage()
    end
  end

  defp bad_usage() do
    IO.puts(
      :stderr,
      "Usage: `eextoheex COMMAND PATHS...` where COMMAND is 'check', 'convert' or 'run'"
    )

    System.halt(1)
  end

  defp run(paths) do
    Enum.map(paths, fn path ->
      case to_heex(path) do
        {:error, output, error} ->
          IO.puts(output)
          raise error

        {:ok, output} ->
          IO.puts(output)
      end
    end)
  end

  defp check_all_templates(roots) do
    templates_helper(roots, _replace_file_on_success = false)
  end

  defp convert_all_templates(roots) do
    templates_helper(roots, _replace_file_on_success = true)
  end

  defp templates_helper(roots, move_file_on_success) do
    eex_templates =
      roots
      |> Enum.flat_map(&ls_recursive(&1))
      |> Enum.filter(&(&1 =~ ~r/\.html\.l?eex$/))

    results =
      Enum.map(eex_templates, fn filename ->
        case to_heex(filename) do
          {:ok, output} ->
            if move_file_on_success do
              new_filename = Regex.replace(~r/\.l?eex$/, filename, ".heex")

              with :ok <- File.rename(filename, new_filename),
                   :ok <- File.write!(new_filename, output) do
                {:ok, filename}
              else
                {:error, err} ->
                  Logger.error("Error moving #{filename} to #{new_filename}", err)
                  {:ok, filename}
              end
            else
              {:ok, filename}
            end

          {:error, _output, err} ->
            {:error, filename, err}
        end
      end)

    grouped = Enum.group_by(results, &elem(&1, 0))
    oks = grouped[:ok] || []
    errors = grouped[:error] || []

    lok = length(oks)
    lerrs = length(errors)

    if lok > 0 do
      IO.puts("html.eex -> heex conversion worked ok for the following #{lok} templates:")
      IO.puts("")

      Enum.each(oks || [], fn {_, filename} ->
        IO.puts("  " <> strip_path(filename))
      end)
    end

    if lerrs > 0 do
      IO.puts("")
      IO.puts("The following #{lerrs} html.eex templates could not be converted:")
      IO.puts("")
    end

    Enum.each(errors || [], fn {_, filename, err} ->
      IO.puts("  " <> strip_path(filename) <> ":")
      IO.puts("    #{inspect(err)}")
    end)
  end

  defp to_heex(path) do
    contents = File.read!(path)
    EexToHeex.eex_to_heex(contents)
  end

  defp ls_recursive(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        File.ls!(path)
        |> Enum.map(&Path.join(path, &1))
        |> Enum.map(&ls_recursive/1)
        |> Enum.concat()

      true ->
        []
    end
  end

  defp strip_path(path) do
    Regex.replace(~r[.*/platform/], path, "")
  end
end
