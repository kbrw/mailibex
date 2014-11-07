defmodule MimeMail do
  @type t :: %MimeMail{headers: [MimeMail.ToHeader.t], body: binary | [MimeMail.t] | {:raw,binary}}
  @derive [Access]
  defstruct headers: [], body: ""

  def from_string(data) do
    [headers,body]= String.split(data,"\r\n\r\n",parts: 2)
    headers=data
    |> String.replace(~r/\r\n([^\t ])/,"\r\n!\\1")
    |> String.split("\r\n!")
    |> Enum.map(&{String.split(&1,~r/\s*:/,parts: 2),&1})
    headers=for {[k,_],v}<-headers, do: {:"#{String.downcase(k)}", v}
    %MimeMail{headers: headers, body: {:raw,body}}
  end

  def to_string(%MimeMail{}=mail) do
    %{body: {:raw,body},headers: headers} = mail |> encode_headers |> encode_body
    headers = for({k,v}<-headers,do: v) |> Enum.join("\r\n")
    headers <> "\r\n\r\n" <> body
  end

  def decode_headers(%MimeMail{}=mail,decoders) do
    Enum.reduce(decoders,mail,fn decoder,acc-> decoder.decode_headers(acc) end)
  end

  def encode_headers(%MimeMail{headers: headers}=mail) do
    %{mail|headers: for({k,v}<-headers, do: {k,MimeMail.Header.encode(k,v)})}
  end

  def decode_body(%MimeMail{body: {:raw,body}}=mail) do
    
  end
  def decode_body(%MimeMail{body: _}=mail), do: mail

  def encode_body(%MimeMail{body: {:raw,body}}=mail), do: mail
  def encode_body(%MimeMail{body: body}=mail) when is_binary(body) do
    mail = MimeMail.CTParams.decode_headers(mail)
    case mail.headers[:'content-type'] do
      {"text/"<>_=type,params}-> 
        headers = mail.headers 
        |> Dict.put(:'content-type',{type,Dict.put(params,:charset,"utf-8")})
        |> Dict.put(:'content-transfer-encoding',"quoted-printable")
        %{mail|headers: headers, body: {:raw,string_to_qp(body)}}
      {type,params}->
        headers = mail.headers |> Dict.put(:'content-transfer-encoding',"base64")
        %{mail|headers: headers, body: {:raw,(body |> String.replace(~r/\s/,"") |> Base.encode64)}}
    end
  end
  def encode_body(%MimeMail{body: childs}=mail) when is_list(childs) do
    mail = MimeMail.CTParams.decode_headers(mail)
    boundary = "qsjdkfjsdkf" #generate boundary
    {"multipart/"<>_=type,params} = mail.headers[:'content-type']
    headers = mail.headers |> Dict.put(:'content-type',{type,Dict.put(params,:boundary,boundary)})
    body = childs |> String.map(&MimeMail.to_string/1) |> Enum.join(boundary)
    %{mail|body: {:raw,body}, headers: headers}
  end

  def string_to_qp(str) do
    str |> String.split("\r\n") |> Enum.map(fn line->
      {eol,line} = '#{line}' |> Enum.reverse |> Enum.split_while(&(&1==?\t or &1==?\s))
      enc_line = Enum.concat(Enum.map(eol,&char_to_qp/1),Enum.map(line,fn
        c when c == ?\t or (c < 127 and c > 31 and c !== ?=) -> c
        c -> char_to_qp(c)
      end)) |> Enum.reverse |> Kernel.to_string |> chunk_line
    end) |> Enum.join("\r\n")
  end
  defp char_to_qp(char), do: for(<<a,b<-Base.encode16(<<char::utf8>>)>>,into: "",do: <<?=,a,b>>)
  defp chunk_line(<<vline::size(73)-binary,?=,rest::binary>>), do: (vline<>"=\r\n="<>chunk_line(rest))
  defp chunk_line(<<vline::size(74)-binary,?=,rest::binary>>), do: (vline<>"=\r\n="<>chunk_line(rest))
  defp chunk_line(<<vline::size(75)-binary,rest::binary>>), do: (vline<>"=\r\n"<>chunk_line(rest))
  defp chunk_line(other), do: other
  
  def qp_to_string(str), do: 
    (str |> String.rstrip |> String.rstrip(?=) |> qp_to_string([]))
  def qp_to_string("=\r\n"<>rest,acc), do: 
    qp_to_string(rest,acc)
  def qp_to_string(<<?=,x1,x2>><>rest,acc), do: 
    qp_to_string(rest,[<<x1,x2>> |> String.upcase |> Base.decode16! | acc])
  def qp_to_string(<<c,rest::binary>>,acc), do:
    qp_to_string(rest,[c | acc])
  def qp_to_string("",acc), do:
    (acc |> Enum.reverse |> Kernel.to_string)
end

defprotocol MimeMail.ToHeader do
  def to_string(term)
end
defmodule MimeMail.Header do
  def unfold(value), do: 
    String.replace(value,~r/\r\n([\t ])/,"\\1")
  def fold(value) do
    value
  end

  def encode(_,value) when is_binary(value), do: value
  def encode(key,value) do
    encoded_value=value |> MimeMail.ToHeader.to_string |> encode_ascii |> fold
    "#{encode_key("#{key}")}: #{encoded_value}"
  end
  def decode(value) do
    case String.split(value,~r/:\s*/, parts: 2) do
      [_]->""
      [_,v]-> v |> decode_ascii |> unfold
    end
  end

  def encode_key(key), do:
    (String.split(key,"-") |> Enum.map(&encode_key_word/1) |> Enum.join("-"))
  def encode_key_word(word) when word in ["dkim","spf","x","id","mime"], do: #acronym, upcase
    String.upcase(word)
  def encode_key_word(word), do: # not acronym, camelcase
    String.capitalize(word)

  def encode_ascii(str) do
    str  
  end
  def decode_ascii(str) do
    str
  end
end

defmodule Iconv do
  @on_load :init
  def init, do: :erlang.load_nif('#{:code.priv_dir(:mailibex)}/Elixir.Iconv_nif',0)
  @doc "iconv interface, from and to are encoding supported by iconv"
  def conv(str,from,to), do: exit(:nif_library_not_loaded)
end
