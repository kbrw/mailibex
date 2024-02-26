defmodule Mix.Tasks.Compile.Iconv do
  @shortdoc "Compiles Iconv"

  use Mix.Task

  @doc """
  For Linux:
  1. Install gcc and libconv via your distro's package manager.

  For Mac OS X / macOS:
  1. Install gcc and libiconv via homebrew.

  For Windows:
  1. Install (MSYS2)[https://msys2.github.io], then open MSYS2 Shell to download latest repo with `pacman -Sy`.
  2. Install gcc from repo with `pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-libiconv`. Choose gcc only option if prompted.
  3. Open the MinGW Shell, ensure `which gcc` returns `/mingw64/gcc`.
  4. Add elxir bin folder and erlang bin folder to your $PATH, then run `mix deps.compile mailibex`.
  4. Once the dll is compiled in your priv folder, MSYS2 is no longer required as the dll compiled is native and redistributable.
  """
  def run(_) do
    lib_ext = if {:win32, :nt} == :os.type, do: "dll", else: "so"
    lib_file = "priv/Elixir.Iconv_nif.#{lib_ext}"
    if not File.exists?(lib_file) do
      [i_erts]=Path.wildcard("#{:code.root_dir}/erts*/include")
      i_ei=:code.lib_dir(:erl_interface,:include)
      l_ei=:code.lib_dir(:erl_interface,:lib)
      args = "-L\"#{l_ei}\" -lei -I\"#{i_ei}\" -I\"#{i_erts}\" -Wall -shared -fPIC"
      args = args <> if {:unix, :darwin}==:os.type, do: " -undefined dynamic_lookup -dynamiclib", else: ""
      args = args <> if {:win32, :nt}==:os.type, do: " -liconv", else: ""
      Mix.shell.info to_string :os.cmd('gcc #{args} -v -o #{lib_file} c_src/iconv_nif.c')
    end
    :ok
  end
end

defmodule Mailibex.Mixfile do
  use Mix.Project

  def app, do: :mailibex

  def version, do: "0.2.0"

  def source_url, do: "https://github.com/kbrw/#{app()}"

  def project do
    [app: app(),
     version: version(),
     elixir: "~> 1.12",
     description: description(),
     package: package(),
     compilers: [:iconv, :elixir, :app],
     deps: deps(),
     docs: docs(),
     elixirc_options: [warnings_as_errors: true],
     ]
  end

  def application do
    [
      extra_applications: [
        :crypto,
        :inets,
        :logger,
        :public_key,
        :ssl,
      ],
    ]
  end

  defp package do
    [ maintainers: ["Arnaud Wetzel","heri16"],
      licenses: ["The MIT License (MIT)"],
      links: %{
        "Changelog" => "https://hexdocs.pm/#{app()}/changelog.html",
        "GitHub" => source_url()
      },
    ]
  end

  defp description do
    """
    Mailibex is an email library in Elixir : currently implements
    DKIM, SPF, DMARC, MimeMail (using iconv nif for encoding),
    MimeType (and file type detection), a simplified api to modify or create
    mimemail as a keyword list.
    """
  end

  defp deps do
    [
      {:codepagex, "~> 0.1", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [title: "Changelog"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: source_url(),
      # We need to git tag with the corresponding format.
      source_ref: "v#{version()}",
    ]
  end
end
