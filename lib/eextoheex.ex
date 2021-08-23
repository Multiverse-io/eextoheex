defmodule EexToHeex do
  @moduledoc """
  EexToHeex performs best effort conversion of html.eex templates to heex.

  The output is not guaranteed to be correct. However, conversion works
  correctly for a sufficiently wide range of input templates
  that the amount of manual conversion work can be significantly reduced.

  See
  https://github.com/phoenixframework/phoenix_live_view/blob/master/CHANGELOG.md#new-html-engine
  for information on the differences between eex and heex templates.
  """

  alias Phoenix.LiveView.HTMLEngine

  @doc """
  Performs best effort conversion of an html.eex template to a heex template.
  Returns `{:ok, output_string}` if successful, or `{:error, output_string, error}`
  on error. In the latter case, `output_string` may be `nil` if the error occurred
  before any output was generated.

  On success, the output is guaranteed to be a valid heex template
  (since it has passed successfully through `HTMLEngine.compile`).
  However, there is no general guarantee that the output template will
  have exactly the same behavior as the input template.
  """
  @spec eex_to_heex(String.t()) :: {:ok, String.t()} | {:error, String.t() | nil, any()}
  def eex_to_heex(str) do
    with {:ok, toks} <-
           EEx.Tokenizer.tokenize(str, _start_line = 1, _start_col = 0, %{
             trim: false,
             indentation: 0
           }) do
      toks = fudge_tokens(toks)

      attrs = find_attrs(false, false, [], toks)

      attr_reps =
        Enum.flat_map(attrs, fn {quoted, subs} -> attr_replacements(str, quoted, subs) end)

      forms = find_form_tags([], toks)
      form_reps = form_replacements(str, forms)

      output = multireplace(str, attr_reps ++ form_reps)
      check_output(output)
    else
      {:error, err} ->
        {:error, nil, err}
    end
  end

  defp check_output(output) do
    with {:ok, tmp_path} <- Briefly.create(),
         :ok <- File.write(tmp_path, output) do
      try do
        # Phoenix.LiveView.HTMLEngine ignores its second param
        HTMLEngine.compile(tmp_path, "foo.html.heex")
        {:ok, output}
      rescue
        err ->
          {:error, output, err}
      end
    else
      {:error, err} ->
        {:error, output, err}
    end
  end

  # Column information for some tokens is systematically off by a few chars.
  defp fudge_tokens(tokens) do
    Enum.map(tokens, fn tok ->
      case tok do
        {:text, l, c, t} ->
          {:text, l,
           if l == 1 do
             c
           else
             c - 1
           end, t}

        {:expr, l, c, eq, expr} ->
          {:expr, l,
           if l == 1 do
             c + 3
           else
             c + 2
           end, eq, expr}

        _ ->
          tok
      end
    end)
  end

  defp find_form_tags(accum, [t = {:expr, _, _, '=', txt} | rest]) do
    txt = to_string(txt)

    if txt =~ ~r/^\s*[[:alnum:]_]+\s*=\s*form_for[\s|(]/ and not (txt =~ ~r/\s->\s*$/) do
      find_form_tags([{:open, true, t} | accum], rest)
    else
      find_form_tags(accum, rest)
    end
  end

  defp find_form_tags(accum, [t = {:text, _, _, txt} | rest]) do
    txt = to_string(txt)
    forms = Regex.scan(~r{</?form[>\s]}i, txt, return: :index)

    accums =
      Enum.map(
        forms,
        fn [{i, l}] ->
          if String.starts_with?(String.downcase(String.slice(txt, i, l)), "<form") do
            {:open, false, t}
          else
            {:close, i, t}
          end
        end
      )

    find_form_tags(Enum.reverse(accums) ++ accum, rest)
  end

  defp find_form_tags(accum, [_ | rest]) do
    find_form_tags(accum, rest)
  end

  defp find_form_tags(accum, []) do
    Enum.reverse(accum)
  end

  defp pair_open_close_forms(accum, _currently_open, []) do
    Enum.reverse(accum)
  end

  defp pair_open_close_forms(accum, currently_open, [f = {:open, _is_live, _tok} | rest]) do
    pair_open_close_forms(accum, [f | currently_open], rest)
  end

  defp pair_open_close_forms(accum, [], [{:close, _i, _tok} | rest]) do
    # Ignore unmatched closers
    pair_open_close_forms(accum, [], rest)
  end

  defp pair_open_close_forms(accum, [o | os], [c = {:close, _i, _tok} | rest]) do
    pair_open_close_forms([{o, c} | accum], os, rest)
  end

  defp form_replacements(str, forms) do
    open_close_pairs = pair_open_close_forms([], [], forms)

    open_close_pairs
    |> Enum.flat_map(fn {{:open, is_live, otok}, {:close, ci, ctok}} ->
      if is_live do
        # <%= f = form_for ... %> -> <.form ...>
        {:expr, tl, tc, '=', expr} = otok
        expr = to_string(expr)
        dot_form = mung_form_for(Code.string_to_quoted!(expr))
        ff_start = get_index(str, tl, tc)

        {:text, l, c, _} = ctok
        close_start = get_index(str, l, c) + ci

        ff_repl = {
          scan_to_char(str, "<", -1, ff_start),
          scan_to_char(str, ">", 1, ff_start + String.length(expr)) + 1,
          dot_form
        }

        close_repl = {close_start, close_start + String.length("</form>"), "</.form>"}

        [close_repl, ff_repl]
      else
        []
      end
    end)
  end

  defp mung_form_for(
         {:=, _,
          [
            f = {_, _, _},
            {:form_for, _,
             [
               changeset,
               url,
               more_args
             ]}
          ]}
       ) do
    extras =
      Enum.reduce(
        more_args,
        "",
        fn {k, v}, s ->
          s <> " #{String.replace(Atom.to_string(k), "_", "-")}=#{brace_wrap(Macro.to_string(v))}"
        end
      )

    "<.form let={#{Macro.to_string(f)}} for=#{brace_wrap(Macro.to_string(changeset))} url=#{
      brace_wrap(Macro.to_string(url))
    }#{extras}>"
  end

  defp brace_wrap(s = "\"" <> _) do
    s
  end

  defp brace_wrap(val) do
    "{#{val}}"
  end

  defp find_attrs(
         inside_tag?,
         just_subbed?,
         accum,
         [{:text, _, _, txt}, e = {:expr, _, _, '=', _contents} | rest]
       ) do
    txt = to_string(txt)

    # Strip the trailing part of the last attr of this tag if there was one and it was quoted.
    txt =
      case {just_subbed?, List.first(accum)} do
        {true, {_quoted = true, _}} ->
          String.replace(txt, ~r/^[^"]+/, "")

        _ ->
          txt
      end

    {inside_tag?, _offset} = update_inside_tag(inside_tag?, txt)

    if inside_tag? do
      case Regex.run(
             ~r/\s*[[:alnum:]-]+=\s*(?:(?:\s*)|(?:"([^"]*)))$/,
             String.slice(txt, 0..-1)
           ) do
        [_, prefix] ->
          {subs, rest} = find_subs([{e, prefix, ""}], rest)
          find_attrs(inside_tag?, _just_subbed? = true, [{_quoted = true, subs} | accum], rest)

        [_] ->
          find_attrs(
            inside_tag?,
            _just_subbed? = true,
            [{_quoted = false, [{e, "", ""}]} | accum],
            rest
          )

        _ ->
          find_attrs(inside_tag?, _just_subbed? = false, accum, rest)
      end
    else
      find_attrs(inside_tag?, _just_subbed? = false, accum, rest)
    end
  end

  defp find_attrs(inside_tag?, _just_subbed?, accum, [{:text, _, _, txt} | rest]) do
    txt = to_string(txt)
    {inside_tag?, _} = update_inside_tag(inside_tag?, txt)
    find_attrs(inside_tag?, _just_subbed? = false, accum, rest)
  end

  defp find_attrs(inside_tag?, _just_subbed?, accum, [_ | rest]) do
    find_attrs(inside_tag?, _just_subbed? = false, accum, rest)
  end

  defp find_attrs(_inside_tag?, _just_subbed?, accum, []) do
    Enum.reverse(accum)
  end

  defp update_inside_tag(inside_tag?, txt) do
    case Regex.run(~r/<[[:alnum:]_]+[\s>][^>]*$/, txt, return: :index) do
      [{offset, _}] ->
        {true, offset}

      nil ->
        {inside_tag? and not String.contains?(txt, ">"), 0}
    end
  end

  defp find_subs(accum = [{e, prefix, _suffix} | arest], toks = [{:text, _, _, txt} | trest]) do
    txt = to_string(txt)

    case Regex.run(~r/^([^"]*)(.?)/, txt) do
      [_, suffix, en] ->
        accum = [{e, prefix, suffix} | arest]

        if en == "\"" do
          {Enum.reverse(accum), toks}
        else
          find_subs(accum, trest)
        end

      nil ->
        find_subs(accum, trest)
    end
  end

  defp find_subs(accum, [e = {:expr, _, _, '=', _contents} | rest]) do
    find_subs([{e, "", ""} | accum], rest)
  end

  defp find_subs(accum, toks) do
    {Enum.reverse(accum), toks}
  end

  defp attr_replacements(str, quoted, [{{:expr, l, c, _, expr}, "", ""}]) do
    expr = to_string(expr)
    expr_start = get_index(str, l, c)
    expr_end = expr_start + String.length(expr)

    open =
      scan_to_char(
        str,
        if quoted do
          "\""
        else
          "<"
        end,
        -1,
        expr_start
      )

    close =
      scan_to_char(
        str,
        if quoted do
          "\""
        else
          ">"
        end,
        1,
        expr_end
      )

    [{open, expr_start, "{\"\#{"}, {expr_start, expr_end, expr}, {expr_end, close + 1, "}\"}"}]
  end

  defp attr_replacements(str, _quoted = true, subs = [_ | _]) do
    subs_len = length(subs)

    subs
    |> Enum.with_index()
    |> Enum.flat_map(fn {{{:expr, l, c, _, expr}, prefix, suffix}, i} ->
      expr = to_string(expr)
      expr_start = get_index(str, l, c)
      expr_end = expr_start + String.length(expr)

      opener =
        if i == 0 do
          open = scan_to_char(str, "\"", -1, expr_start)
          {open, expr_start, "{\""}
        else
          open = scan_to_char(str, "<", -1, expr_start)
          {open, expr_start, ""}
        end

      closer =
        if i == subs_len - 1 do
          close = scan_to_char(str, "\"", 1, expr_end)
          {expr_end, close + 1, "\"}"}
        else
          close = scan_to_char(str, ">", 1, expr_end)
          {expr_end, close + 1 + String.length(suffix), ""}
        end

      [opener] ++
        [{expr_start, expr_end, "#{estring(prefix)}\#{#{expr}}#{estring(suffix)}"}] ++
        [closer]
    end)
  end

  defp estring("" <> str) do
    decoded = HtmlEntities.decode(str)
    s = inspect(decoded)
    String.slice(s, 1, String.length(s) - 2)
  end

  defp scan_to_char(str, c, inc, i) do
    cond do
      i < 0 || i >= String.length(str) ->
        -1

      String.at(str, i) == c ->
        i

      true ->
        scan_to_char(str, c, inc, i + inc)
    end
  end

  defp multireplace(str, replacements) do
    {_, new_s} =
      replacements
      |> Enum.sort_by(fn {i, _, _} -> i end)
      |> Enum.reduce(
        {0, str},
        fn {i, j, rep}, {offset, new_s} ->
          {
            offset + String.length(rep) - (j - i),
            String.slice(new_s, 0, i + offset) <>
              rep <> String.slice(new_s, j + offset, String.length(new_s))
          }
        end
      )

    new_s
  end

  defp get_index(s, line, col) do
    get_index_helper(s, line, col, 1, 0, 0)
  end

  defp get_index_helper(_, line, col, line, col, index) do
    index
  end

  defp get_index_helper("", _line, _col, _current_line, _current_col, _index) do
    -1
  end

  defp get_index_helper("\n" <> rest, line, col, current_line, _current_col, index) do
    get_index_helper(rest, line, col, current_line + 1, _current_col = 0, index + 1)
  end

  defp get_index_helper(str, line, col, current_line, current_col, index) do
    get_index_helper(
      String.slice(str, 1..-1),
      line,
      col,
      current_line,
      current_col + 1,
      index + 1
    )
  end
end
