defmodule MimeMail.Emails do
  def parse_header(data) do
    data
    |> String.split(~r/\s*,\s*/)
    |> Enum.map(fn addr_spec->
      case Regex.run(~r/^([^<]*)<([^>]*)>/,addr_spec) do
        [desc,addr]->%{name: String.rstrip(desc), address: addr}
        nil -> %{name: nil, address: String.strip(addr_spec)}
      end
    end)
  end
  def decode_headers(%MimeMail{headers: headers}=mail) do
    parsed_mail_headers=for {k,v}<-headers, k in [:from,:to,:cc,:cci], do: {k,parse_header(v)}
    %{mail| headers: Enum.reduce(parsed_mail_headers,headers, fn {k,v},acc-> Dict.put(acc,k,v) end)}
  end
  defimpl MimeMail.ToHeader, for: List do # a list header is a mailbox spec list
    def to_string(mail_list) do # a mail is a struct %{name: nil, address: ""}
      mail_list |> Enum.map(fn 
        %{name: nil,address: address} -> address
        %{name: name, address: address} -> "#{name} <#{address}>"
      end) |> Enum.join(", ")
    end
  end
end

defmodule MimeMail.Params do
  def parse_header(data) do
    params=data
    |> String.split(~r"\s*;\s*",trim: true)
    |> Enum.map(&String.split(&1,"=",parts: 2))
    Enum.into(for([k,v]<-params, do: {:"#{k}",v}), %{})
  end
  defimpl MimeMail.ToHeader, for: Map do # a map header is "key1=value1; key2=value2"
    def to_string(params) do
      params |> Enum.map(fn {k,v}->"#{k}=#{v}" end) |> Enum.join("; ")
    end
  end
end
defmodule MimeMail.CTParams do
  def parse_header(data) do
    case String.split(data,~r"\s*;\s*", parts: 2) do
      [value,params] -> {value,MimeMail.Params.parse_header(params)}
      [value] -> {value,%{}}
    end
  end
  def decode_headers(%MimeMail{headers: headers}=mail) do
    parsed_mail_headers=for {k,v}<-headers,match?("content-"<>_,"#{k}"), do: {k,parse_header(v)}
    %{mail| headers: Enum.reduce(parsed_mail_headers,headers, fn {k,v},acc-> Dict.put(acc,k,v) end)}
  end

  defimpl MimeMail.ToHeader, for: Tuple do # a 2 tuple header is "value; key1=value1; key2=value2"
    def to_string({value,%{}=params}) do
      "#{value}; #{MimeMail.ToHeader.to_string(params)}"
    end
  end
end
