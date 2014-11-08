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
    parsed_mail_headers=for {k,{:raw,v}}<-headers, k in [:from,:to,:cc,:cci], do: {k,v|>MimeMail.header_value|>parse_header}
    %{mail| headers: Enum.reduce(parsed_mail_headers,headers, fn {k,v},acc-> Dict.put(acc,k,v) end)}
  end
  defimpl MimeMail.Header, for: List do # a list header is a mailbox spec list
    def to_ascii(mail_list) do # a mail is a struct %{name: nil, address: ""}
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
  defimpl MimeMail.Header, for: Map do # a map header is "key1=value1; key2=value2"
    def to_ascii(params) do
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
    parsed_mail_headers=for {k,v}<-headers,match?("content-"<>_,"#{k}"), do: {k,v|>MimeMail.header_value|>parse_header}
    %{mail| headers: Enum.reduce(parsed_mail_headers,headers, fn {k,v},acc-> Dict.put(acc,k,v) end)}
  end

  defimpl MimeMail.Header, for: Tuple do # a 2 tuple header is "value; key1=value1; key2=value2"
    def to_ascii({value,%{}=params}) do
      "#{value}; #{MimeMail.Header.to_string(params)}"
    end
  end
end

defmodule MimeMail.Words do
  
  def word_encode(line) do
    for <<char::utf8<-line>> do
      case char do 
        ?\s -> ?_
        c when c < 127 and c > 32 and c !== ?= and c !== ?? and c !== ?_-> c
        c -> for(<<a,b<-Base.encode16(<<c::utf8>>)>>,into: "",do: <<?=,a,b>>)
      end
    end |> to_string |> chunk_line |> Enum.map(&"=?UTF-8?Q?#{&1}?=") |> Enum.join("\r\n ")
  end
  defp chunk_line(<<vline::size(61)-binary,?=,rest::binary>>), do: [vline|chunk_line("="<>rest)]
  defp chunk_line(<<vline::size(62)-binary,?=,rest::binary>>), do: [vline|chunk_line("="<>rest)]
  defp chunk_line(<<vline::size(63)-binary,rest::binary>>), do: [vline|chunk_line(rest)]
  defp chunk_line(other), do: [other]
  
  def qwords_to_string(qwords) do
    qwords |> String.split(~r/\s*/) |> Enum.map(&q_to_string/1) |> Enum.join
  end
  def q_to_string(str), do: 
    (str |> String.rstrip |> String.rstrip(?=) |> q_to_string([]))
  def q_to_string("_"<>rest,acc), do: 
    q_to_string(rest,[?\s|acc])
  def q_to_string(<<?=,x1,x2>><>rest,acc), do: 
    q_to_string(rest,[<<x1,x2>> |> String.upcase |> Base.decode16! | acc])
  def q_to_string(<<c,rest::binary>>,acc), do:
    q_to_string(rest,[c | acc])
  def q_to_string("",acc), do:
    (acc |> Enum.reverse |> Kernel.to_string)

  defimpl MimeMail.Header, for: Binary do # a 2 tuple header is "value; key1=value1; key2=value2"
    def to_ascii(value) do
      MimeMail.Words.word_encode(value)
    end
  end
end
