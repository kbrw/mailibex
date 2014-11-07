defmodule Mix.Tasks.Compile.Iconv do
  @shortdoc "Compiles Iconv"
  def run(_) do
    [i_erts]=Path.wildcard("#{:code.root_dir}/erts*/include")
    i_ei=:code.lib_dir(:erl_interface,:include)
    l_ei=:code.lib_dir(:erl_interface,:lib)
    args = " -L#{l_ei} -lerl_interface -lei -I#{i_ei} -I#{i_erts} -Wall -shared -fPIC "
    args = args <> if {:unix,:darwin}==:os.type, do: "-undefined dynamic_lookup -dynamiclib", else: ""
    Mix.shell.info to_string :os.cmd('gcc #{args} -o priv/Elixir.Iconv_nif.so c_src/iconv_nif.c')
  end
end

defmodule Mailibex.Mixfile do
  use Mix.Project

  def project do
    [app: :mailibex,
     version: "0.0.1",
     elixir: "~> 1.0.0",
     deps: []]
  end

  def application do
    [applications: [:logger]]
  end
end
