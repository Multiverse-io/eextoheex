defmodule EexToHeexTest do
  use ExUnit.Case, async: true
  doctest EexToHeex

  require Logger

  describe "eex_to_EexToHeex/1" do
    test "plain html comes back unmodified" do
      input_templ = """
      <div class="class">
        <p>Hey there!</p>
        <form>
          <input type="hidden" name="hidden" value="hidden">
          <form class="nested form">
            <input type="hidden" name="hidden" value="hidden">
          </form>
        </form>
      </div>
      """

      assert {:ok, out_templ} = EexToHeex.eex_to_heex(input_templ)

      assert input_templ == out_templ
    end

    test "<%= foo %> forms within attribute values are converted to { } syntax or plain string values as appropriate" do
      input_templ = """
      <p class="<%= if @foo do "class1" else "class2" end %>" style="some style" attr="<%= foo(bar) %>">
        Blah blah blah...
        <div attr="prefix&lsquo;<%= if @foo do "class1" else "class2" end %>suffix&rsquo;">
        </div>
      </p>
      <div class="profile-strength__container <%= class %>"></div>
      <div class="<%= class %> profile-strength__container"></div>
      """

      out_templ = """
      <p class={"\#{ if @foo do "class1" else "class2" end }"} style="some style" attr={"\#{ foo(bar) }"}>
        Blah blah blah...
        <div attr={"prefix‘\#{ if @foo do "class1" else "class2" end }suffix’"}>
        </div>
      </p>
      <div class={"profile-strength__container \#{ class }"}></div>
      <div class={"\#{ class } profile-strength__container"}></div>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "handles gross non-quoted attributes with template substituted values" do
      input_templ = """
      <p class=<%= this_should_have_been_quoted() %>>
      </p>
      """

      out_templ = """
      <p class={"\#{ this_should_have_been_quoted() }"}>
      </p>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "not fooled by things that look like attributes outside of opening tags" do
      input_templ = """
      <p>Foo</p>
      class=<%= this_should_have_been_quoted() %>
      class="<%= @foo %>"
      <p>Bar</p>
      """

      out_templ = """
      <p>Foo</p>
      class=<%= this_should_have_been_quoted() %>
      class="<%= @foo %>"
      <p>Bar</p>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "live view forms are converted correctly; </form> tags that don't close form_for don't confuse the parser; spurious closing </form> tags don't confuse the parser" do
      input_templ = """
      <form>
        <%= f = form_for @changeset, "#", [phx_submit: "save", phx_change: "change"] %>
          <%= PlatformWeb.Patterns.card_buttons() do %>
            <button class="button-primary" phx-action="Save" phx_disable_with="Saving...">Add Postcode</button>
          <% end %>
        </form>
      </form>
      </form> <!-- spurious closing tag; there are no open forms here -->
      <%= foobar2 = form_for @changeset, "#", [phx_submit: "save", phx_change: if foo do bar else amp end] %>
        <%= PlatformWeb.Patterns.card_buttons() do %>
          <button class="button-primary" phx-action="Save" phx_disable_with="Saving...">Add Postcode</button>
          <form>
            Perhaps this nested form will confuse the parser!
          </form>
        <% end %>
      </form>
      <%= bar = form_for @changeset, "#" %>
        ...
      </form>
      """

      out_templ = """
      <form>
        <.form let={f} for={@changeset} url="#" phx-submit="save" phx-change="change">
          <%= PlatformWeb.Patterns.card_buttons() do %>
            <button class="button-primary" phx-action="Save" phx_disable_with="Saving...">Add Postcode</button>
          <% end %>
        </.form>
      </form>
      </form> <!-- spurious closing tag; there are no open forms here -->
      <.form let={foobar2} for={@changeset} url="#" phx-submit="save" phx-change={if(foo) do
        bar
      else
        amp
      end}>
        <%= PlatformWeb.Patterns.card_buttons() do %>
          <button class="button-primary" phx-action="Save" phx_disable_with="Saving...">Add Postcode</button>
          <form>
            Perhaps this nested form will confuse the parser!
          </form>
        <% end %>
      </.form>
      <.form let={bar} for={@changeset} url="#">
        ...
      </.form>
      """

      assert {:error, ^out_templ, err} = EexToHeex.eex_to_heex(input_templ)
      assert err.description =~ ~r[missing opening tag for </form>$]
    end

    test "not fooled by f=form_for when using a block (not a live view form)" do
      input_templ = """
      <%= f = form_for @changeset, "#", [phx_submit: "save", phx_change: "change"], fn f -> %>
        <%= PlatformWeb.Patterns.card_buttons() do %>
          <button class="button-primary" phx-action="Save" phx_disable_with="Saving...">Add Postcode</button>
        <% end %>
      <% end %>
      """

      assert {:ok, out_templ} = EexToHeex.eex_to_heex(input_templ)

      assert input_templ == out_templ
    end

    test "not fooled by > inside attribute value" do
      input_templ = """
      <p></p><p class="<%= foo %> > <%= bar %> >>" foo="<%= foo %> >" amp="<%= foo %> >"></p>
      """

      out_templ = """
      <p></p><p class={"\#{ foo } > \#{ bar } >>"} foo={"\#{ foo } >"} amp={"\#{ foo } >"}></p>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "check some tricky complex attributes" do
      input_templ = """
      <p class="aa <%= foo <> "" %> bb <%= bar %> cc"></p>
      <p class="aa <%= foo %> bb"></p>
      <p class="aa <%= foo %>"></p>
      <%= for x <- y do %>
        <p class="aa <%= foo %> bb"></p>
      <% end %>
      <p class="<%= foo %> ccc"></p>
      <p class=<%= foo %>></p>
      """

      out_templ = """
      <p class={"aa \#{ foo <> "" } bb \#{ bar } cc"}></p>
      <p class={"aa \#{ foo } bb"}></p>
      <p class={"aa \#{ foo }"}></p>
      <%= for x <- y do %>
        <p class={"aa \#{ foo } bb"}></p>
      <% end %>
      <p class={"\#{ foo } ccc"}></p>
      <p class={"\#{ foo }"}></p>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "single and double quotes for attribute values" do
      input_templ = """
      <p class="'''<%= foo %>'''"></p>
      <p class='""<%= foo %>""'></p>
      """

      out_templ = """
      <p class={"'''\#{ foo }'''"}></p>
      <p class={"\\"\\"\#{ foo }\\"\\""}></p>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "a bug triggering case that came up" do
      input_templ = """
      <%= for local <- assigns[:localisation] do %>
        <link rel="alternate" hreflang="<%= local.hreflang %>" href="<%= PlatformWeb.Endpoint.url %><%= local.href %>" />
      <% end %>
      <link rel="stylesheet" href="<%= PlatformRoutes.static_path(@conn, @css_bundle) %>">
      """

      out_templ = """
      <%= for local <- assigns[:localisation] do %>
        <link rel="alternate" hreflang={"\#{ local.hreflang }"} href={"\#{ PlatformWeb.Endpoint.url }\#{ local.href }"} />
      <% end %>
      <link rel="stylesheet" href={"\#{ PlatformRoutes.static_path(@conn, @css_bundle) }"}>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "test case with a complex attribute value" do
      input_templ = """
      <%= Patterns.card(
        full_width: true,
        icon: {"briefcase", :green}) do %>
        <%= render RoleView, "_role_heading.html", Map.merge(assigns, %{tab: :availability}) %>
          <input id="role-id" type="hidden" value="<%= @role.id %>" />
          <input id="breadcrumbs" type="hidden" value="[
              [&quot;Companies&quot;, &quot;<%= PlatformRoutes.manager_company_path(@conn, :index) %>&quot;],
              [&quot;<%= @company.name %>&quot;, &quot;<%=PlatformRoutes.manager_company_path(@conn, :show, @company) %>&quot;],
              [&quot;<%= @job_title %>&quot;, &quot;<%=PlatformRoutes.manager_company_role_overview_path(@conn, :show, @company, @role.id) %>&quot;]
          ]" />
        <%= render CommonView, "_elm.html" %>
      <% end %>
      """

      out_templ = """
      <%= Patterns.card(
        full_width: true,
        icon: {"briefcase", :green}) do %>
        <%= render RoleView, "_role_heading.html", Map.merge(assigns, %{tab: :availability}) %>
          <input id="role-id" type="hidden" value={"\#{ @role.id }"} />
          <input id="breadcrumbs" type="hidden" value={"[\\n        [\\"Companies\\", \\"\#{ PlatformRoutes.manager_company_path(@conn, :index) }\\"],\\n        [\\"\#{ @company.name }\\", \\"\#{PlatformRoutes.manager_company_path(@conn, :show, @company) }\\"],\\n        [\\"\#{ @job_title }\\", \\"\#{PlatformRoutes.manager_company_role_overview_path(@conn, :show, @company, @role.id) }\\"]\\n    ]"} />
        <%= render CommonView, "_elm.html" %>
      <% end %>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end

    test "test case with a complex attribute value, single quote variant" do
      input_templ = """
      <%= Patterns.card(
        full_width: true,
        icon: {"briefcase", :green}) do %>
        <%= render RoleView, "_role_heading.html", Map.merge(assigns, %{tab: :availability}) %>
          <input id="role-id" type="hidden" value="<%= @role.id %>" />
          <input id="breadcrumbs" type="hidden" value='[
              ["Companies", "<%= PlatformRoutes.manager_company_path(@conn, :index) %>"],
              ["<%= @company.name %>", "<%=PlatformRoutes.manager_company_path(@conn, :show, @company) %>"],
              ["<%= @job_title %>", "<%=PlatformRoutes.manager_company_role_overview_path(@conn, :show, @company, @role.id) %>"]
          ]' />
        <%= render CommonView, "_elm.html" %>
      <% end %>
      """

      out_templ = """
      <%= Patterns.card(
        full_width: true,
        icon: {"briefcase", :green}) do %>
        <%= render RoleView, "_role_heading.html", Map.merge(assigns, %{tab: :availability}) %>
          <input id="role-id" type="hidden" value={"\#{ @role.id }"} />
          <input id="breadcrumbs" type="hidden" value={"[\\n        [\\"Companies\\", \\"\#{ PlatformRoutes.manager_company_path(@conn, :index) }\\"],\\n        [\\"\#{ @company.name }\\", \\"\#{PlatformRoutes.manager_company_path(@conn, :show, @company) }\\"],\\n        [\\"\#{ @job_title }\\", \\"\#{PlatformRoutes.manager_company_role_overview_path(@conn, :show, @company, @role.id) }\\"]\\n    ]"} />
        <%= render CommonView, "_elm.html" %>
      <% end %>
      """

      assert {:ok, out_templ} == EexToHeex.eex_to_heex(input_templ)
    end
  end

  describe "ex_to_heex/1" do
    test "sigil_L heredoc is converted" do
      input_templ = """
      defmodule PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~L"""
          <p class="aa <%= foo %>"></p>
          <p class="bb <%= foo %>"></p>
          \"""
        end
      end
      """

      out_templ = """
      defmodule PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <p class={"aa \#{ foo }"}></p>
          <p class={"bb \#{ foo }"}></p>
          \"""
        end
      end
      """

      assert {:ok, out_templ} == EexToHeex.ex_to_heex(input_templ)
    end

    test "sigil_L is converted" do
      input_templ = """
      defmodule PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~L|<p class="aa <%= foo %>"></p>|
        end
      end
      """

      out_templ = """
      defmodule PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H|<p class={"aa \#{ foo }"}></p>|
        end
      end
      """

      assert {:ok, out_templ} == EexToHeex.ex_to_heex(input_templ)
    end

    test "returns error when leex heredoc cannot be converted" do
      input_templ = """
      defmodule PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~L"""
          <p class="bb <%= foo %>"></not_p>
          \"""
        end
      end
      """

      assert {:error, _, _} = EexToHeex.ex_to_heex(input_templ)
    end

    test "returns error when leex cannot be converted" do
      input_templ = """
      defmodule PageLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~L|<p class="bb <%= foo %>"></not_p>|
        end
      end
      """

      assert {:error, _, _} = EexToHeex.ex_to_heex(input_templ)
    end
  end
end
