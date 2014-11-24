defmodule Mix.Tasks.Compile.Iconv do
  @shortdoc "Compiles Iconv"
  def run(_) do
    if not File.exists?("priv/Elixir.Iconv_nif.so") do
      [i_erts]=Path.wildcard("#{:code.root_dir}/erts*/include")
      i_ei=:code.lib_dir(:erl_interface,:include)
      l_ei=:code.lib_dir(:erl_interface,:lib)
      args = " -L#{l_ei} -lerl_interface -lei -I#{i_ei} -I#{i_erts} -Wall -shared -fPIC "
      args = args <> if {:unix,:darwin}==:os.type, do: "-undefined dynamic_lookup -dynamiclib", else: ""
      Mix.shell.info to_string :os.cmd('gcc #{args} -v -o priv/Elixir.Iconv_nif.so c_src/iconv_nif.c')
    end
  end
end

defmodule Mailibex.Mixfile do
  use Mix.Project

  def project do
    [app: :mailibex,
     version: "0.0.1",
     elixir: "~> 1.0.0",
     description: description,
     package: package,
     compilers: [:iconv, :elixir, :app],
     deps: []]
  end

  def application do
    [applications: [:logger]]
  end

  defp package do
    [ contributors: ["Arnaud Wetzel"],
      licenses: ["The MIT License (MIT)"],
      links: [ { "GitHub", "https://github.com/awetzel/mailibex" } ] ]
  end

  defp description do
    """
    Mailibex is an email library in Elixir : currently implements
    DKIM, SPF, DMARC, MimeMail (using iconv nif for encoding),
    MimeType (and file type detection), a simplified api to modify or create
    mimemail as a keyword list. Next step is a full implementation of
    SMTP client and server, to make it possible to use emails as a routable API for
    events and messages between your applications.
    """
  end
end
