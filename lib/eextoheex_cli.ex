defmodule EexToHeex.CLI do
  require Logger

  @eex_extensions [".html.eex", ".html.leex"]
  @ex_extensions [".ex"]

  def main(args \\ []) do
    if length(args) < 2 do
      bad_usage()
    end

    cmd = Enum.at(args, 0)

    paths = Enum.drop(args, 1)

    case cmd do
      "check" ->
        check_all_templates(paths, @eex_extensions, nil, &EexToHeex.eex_to_heex/1)

      "check_inline" ->
        check_all_templates(paths, @ex_extensions, nil, &EexToHeex.ex_to_heex/1)

      "convert" ->
        convert_all_templates(paths, @eex_extensions, ".heex", &EexToHeex.eex_to_heex/1)

      "convert_inline" ->
        convert_all_templates(paths, @ex_extensions, ".ex", &EexToHeex.ex_to_heex/1)

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

  defp to_heex(path) do
    contents = File.read!(path)

    if has_extension?(path, @ex_extensions) do
      EexToHeex.ex_to_heex(contents)
    else
      EexToHeex.eex_to_heex(contents)
    end
  end

  defp check_all_templates(roots, allowed_extensions, new_extension, conversion_func) do
    templates_helper(roots, allowed_extensions, new_extension, conversion_func)
  end

  defp convert_all_templates(roots, allowed_extensions, new_extension, conversion_func) do
    templates_helper(roots, allowed_extensions, new_extension, conversion_func)
  end

  defp templates_helper(roots, allowed_extensions, new_extension, conversion_func) do
    eex_templates =
      roots
      |> Enum.flat_map(&ls_recursive(&1))
      |> Enum.filter(&has_extension?(&1, allowed_extensions))

    results =
      eex_templates
      |> Enum.map(fn filename ->
        input = File.read!(filename)

        case conversion_func.(File.read!(filename)) do
          {:ok, output} ->
            cond do
              output == input and
                  (new_extension == nil or new_extension == Path.extname(filename)) ->
                # Nothing at all has changed, so don't mention this file in the output.
                nil

              new_extension ->
                new_filename = Path.rootname(filename) <> new_extension

                with :ok <- File.rename(filename, new_filename),
                     :ok <- File.write!(new_filename, output) do
                  {:ok, filename}
                else
                  {:error, err} ->
                    Logger.error("Error moving #{filename} to #{new_filename}", err)
                    {:ok, filename}
                end

              true ->
                {:ok, filename}
            end

          {:error, _output, err} ->
            {:error, filename, err}
        end
      end)
      |> Enum.filter(&(&1 != nil))

    grouped = Enum.group_by(results, &elem(&1, 0))
    oks = grouped[:ok] || []
    errors = grouped[:error] || []

    lok = length(oks)
    lerrs = length(errors)

    if lok > 0 do
      IO.puts("conversion worked ok for the following #{lok} templates:")
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

  defp has_extension?(path, extensions) do
    extensions
    |> Enum.map(&String.ends_with?(path, &1))
    |> Enum.any?()
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
