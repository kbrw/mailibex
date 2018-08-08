defmodule MimeMail.Address do
  defstruct name: nil, address: ""

  @behaviour Access
  defdelegate get_and_update(dict,k,v), to: Map
  defdelegate fetch(dict,k), to: Map
  defdelegate get(dict,k,v), to: Map
  defdelegate pop(dict,k), to: Map

  def decode(addr_spec) do
    case Regex.run(~r/^([^<]*)<([^>]*)>/, addr_spec) do
      [_, desc, addr] ->
        name = desc |> MimeMail.Words.word_decode() |> String.trim("\"")
        %MimeMail.Address{name: name, address: addr}
      _ ->
        %MimeMail.Address{name: nil, address: String.strip(addr_spec)}
    end
  end

  defimpl MimeMail.Header, for: MimeMail.Address do
    def to_ascii(%{name: nil, address: address}), do: address
    def to_ascii(%{name: name, address: address}), do:
      "#{MimeMail.Words.word_encode name} <#{address}>"
  end
end

defmodule MimeMail.Emails do
  def parse_header(data) do
    data |> String.strip |> String.split(~r/(?!\B"[^"]*),(?![^"]*"\B)/) |> Enum.map(&MimeMail.Address.decode/1)
  end
  def decode_headers(%MimeMail{headers: headers}=mail) do
    parsed=for {k,{:raw,v}}<-headers, k in [:from,:to,:cc,:cci,:'delivered-to'] do
      {k,v|>MimeMail.header_value|>parse_header}
    end
    %{mail| headers: Enum.reduce(parsed,headers, fn {k,v},acc-> Dict.put(acc,k,v) end)}
  end
  defimpl MimeMail.Header, for: List do # a list header is a mailbox spec list
    def to_ascii(mail_list) do # a mail is a struct %{name: nil, address: ""}
      mail_list
      |> Enum.filter(&match?(%MimeMail.Address{},&1))
      |> Enum.map(&MimeMail.Header.to_ascii/1) |> Enum.join(", ")
    end
  end
end

defmodule MimeMail.Params do
  def parse_header(bin), do: parse_kv(bin<>";",:key,[],[])

  def parse_kv(<<c,rest::binary>>,:key,keyacc,acc) when c in [?\s,?\t,?\r,?\n,?;], do:
    parse_kv(rest,:key,keyacc,acc) # not allowed characters in key, skip
  def parse_kv(<<?=,?",rest::binary>>,:key,keyacc,acc), do:
    parse_kv(rest,:quotedvalue,[],[{:"#{keyacc|>Enum.reverse|>to_string|>String.downcase}",""}|acc]) # enter in a quoted value, save key in res acc
  def parse_kv(<<?=,rest::binary>>,:key,keyacc,acc), do:
    parse_kv(rest,:value,[],[{:"#{keyacc|>Enum.reverse|>to_string|>String.downcase}",""}|acc]) # enter in a simple value, save key in res acc
  def parse_kv(<<c,rest::binary>>,:key,keyacc,acc), do:
    parse_kv(rest,:key,[c|keyacc],acc) # allowed char in key, add to key acc
  def parse_kv(<<?\\,?",rest::binary>>,:quotedvalue,valueacc,acc), do:
    parse_kv(rest,:quotedvalue,[?"|valueacc],acc) # \" in quoted value is "
  def parse_kv(<<?",rest::binary>>,:quotedvalue,valueacc,[{key,_}|acc]), do:
    parse_kv(rest,:key,[],[{key,"#{Enum.reverse(valueacc)}"}|acc]) # " in quoted value end the value
  def parse_kv(<<?;,rest::binary>>,:value,valueacc,[{key,_}|acc]), do:
    parse_kv(rest,:key,[],[{key,String.strip("#{Enum.reverse(valueacc)}")}|acc]) # ; in simple value ends the value and strip it
  def parse_kv(<<c,rest::binary>>,isvalue,valueacc,acc) when isvalue in [:value,:quotedvalue], do:
    parse_kv(rest,isvalue,[c|valueacc],acc) # allowed char in value, add to acc
  def parse_kv(_,_,_,acc), do:
    Enum.into(acc,%{}) # if no match just return kv acc as map

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
  def normalize({value,m},k) when k in
    [:"content-type",:"content-transfer-encoding",:"content-disposition"], do: {String.downcase(value),m}
  def normalize(h,_), do: h
  def decode_headers(%MimeMail{headers: headers}=mail) do
    parsed_mail_headers=for {k,{:raw,v}}<-headers,match?("content-"<>_,"#{k}"), do: {k,v|>MimeMail.header_value|>parse_header|>normalize(k)}
    %{mail| headers: Enum.reduce(parsed_mail_headers,headers, fn {k,v},acc-> Dict.put(acc,k,v) end)}
  end

  defimpl MimeMail.Header, for: Tuple do # a 2 tuple header is "value; key1=value1; key2=value2"
    def to_ascii({value,%{}=params}) do
      "#{value}; #{MimeMail.Header.to_ascii(params)}"
    end
  end
end

defmodule MimeMail.Words do
  def is_ascii(str) do
    [] == for(<<c<-str>>, (c>126 or c<32) and not(c in [?\t,?\r,?\n]), do: c)
  end
  def word_encode(line) do
    if is_ascii(line) do line else
      for <<char::utf8<-line>> do
        case char do
          ?\s -> ?_
          c when c < 127 and c > 32 and c !== ?= and c !== ?? and c !== ?_-> c
          c -> for(<<a,b<-Base.encode16(<<c::utf8>>)>>,into: "",do: <<?=,a,b>>)
        end
      end |> to_string |> chunk_line |> Enum.map(&"=?UTF-8?Q?#{&1}?=") |> Enum.join("\r\n ")
    end
  end
  defp chunk_line(<<vline::size(61)-binary,?=,rest::binary>>), do: [vline|chunk_line("="<>rest)]
  defp chunk_line(<<vline::size(62)-binary,?=,rest::binary>>), do: [vline|chunk_line("="<>rest)]
  defp chunk_line(<<vline::size(63)-binary,rest::binary>>), do: [vline|chunk_line(rest)]
  defp chunk_line(other), do: [other]

  def word_decode(str) do
    str |> String.split(~r/\s+/) |> Enum.map(&single_word_decode/1) |> Enum.join |> String.rstrip
  end

  def single_word_decode("=?"<>rest = str) do
    case String.split(rest,"?") do
      [enc,"Q",enc_str,"="] ->
        str = q_to_binary(enc_str,[])
        MimeMail.ok_or(Iconv.conv(str,enc,"utf8"),MimeMail.ensure_ascii(str))
      [enc,"B",enc_str,"="] ->
        str = Base.decode64(enc_str) |> MimeMail.ok_or(enc_str)
        MimeMail.ok_or(Iconv.conv(str,enc,"utf8"),MimeMail.ensure_ascii(str))
      _ -> "#{str} "
    end
  end
  def single_word_decode(str), do: "#{str} "

  def q_to_binary("_"<>rest,acc), do:
    q_to_binary(rest,[?\s|acc])
  def q_to_binary(<<?=,x1,x2>><>rest,acc), do:
    q_to_binary(rest,[<<x1,x2>> |> String.upcase |> Base.decode16! | acc])
  def q_to_binary(<<c,rest::binary>>,acc), do:
    q_to_binary(rest,[c | acc])
  def q_to_binary("",acc), do:
    (acc |> Enum.reverse |> IO.iodata_to_binary)

  def decode_headers(%MimeMail{headers: headers}=mail) do
    parsed_mail_headers=for {k,{:raw,v}}<-headers, k in [:subject], do: {k,v|>MimeMail.header_value|>word_decode}
    %{mail| headers: Enum.reduce(parsed_mail_headers,headers, fn {k,v},acc-> Dict.put(acc,k,v) end)}
  end

  defimpl MimeMail.Header, for: BitString do # a 2 tuple header is "value; key1=value1; key2=value2"
    def to_ascii(value) do
      MimeMail.Words.word_encode(value)
    end
  end
end
