defmodule DMARC do
  def organization(host) when is_binary(host), do: 
    organization(host |> String.downcase |> String.split(".") |> Enum.reverse)

  :ssl.start ; :inets.start
  case :httpc.request(:get,{'https://publicsuffix.org/list/effective_tld_names.dat',[]},[], body_format: :binary) do
    {:ok,{{_,200,_},_,r}} -> r
    _ -> File.read!("#{:code.priv_dir(:mailibex)}/suffix.data")
  end 
  |> String.strip
  |> String.split("\n")
  |> Enum.filter(fn <<c,_::binary>>->not c in [?\s,?/]; _-> false end) # remove comments
  |> Enum.map(&String.split(&1,"."))                                   # divide domain components
  |> Enum.sort(fn                                                      # sort rule by priority 
       ["!"<>_|_],_ -> true                                            # exception rules are first ones
       _,["!"<>_|_] -> false                                           # 
       x,y -> length(x) > length(y)                                    # else priority to longest prefix match 
     end)
  |> Enum.each (fn spec->
    org_match = (spec|>Enum.reverse|>Enum.map (fn
      "!"<>rest->rest  # remove exception mark ! 
      "*"->quote do: _ # "*" component matches anything, so convert it to "_"
      x -> x           # match other components as they are
    end)) ++ quote do: [_org|_rest]  # ["com","*","pref"] -> must match ["com",_,"pref",_org|_rest]
    org_len = length(spec) + 1      # and 3+1=4 first components is organization
    def organization(unquote(org_match)=host), do:
      (host |> Enum.take(unquote(org_len)) |> Enum.reverse |> Enum.join("."))
  end)

  def organization([unknown_tld,org|_]), do:
    "#{org}.#{unknown_tld}"

  def organization(host), do: 
    (host |> Enum.reverse |> Enum.join("."))
end
