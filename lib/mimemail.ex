defmodule MimeMail do
  @type header :: {:raw,binary} | MimeMail.Header.t #ever the raw line or any term implementing MimeMail.Header.to_ascii
  @type body :: binary | [MimeMail.t] | {:raw,binary} #ever the raw body or list of mail for multipart or binary for decoded content
  @type t :: %MimeMail{headers: [{key::binary,header}], body: body}
  @derive [Access]
  defstruct headers: [], body: ""

  def from_string(data) do
    [headers,body]= String.split(data,"\r\n\r\n",parts: 2)
    headers=headers
    |> String.replace(~r/\r\n([^\t ])/,"\r\n!\\1")
    |> String.split("\r\n!")
    |> Enum.map(&{String.split(&1,~r/\s*:/,parts: 2),&1})
    headers=for {[k,_],v}<-headers, do: {:"#{String.downcase(k)}", {:raw,v}}
    %MimeMail{headers: headers, body: {:raw,body}}
  end

  def to_string(%MimeMail{}=mail) do
    %{body: {:raw,body},headers: headers} = mail |> encode_headers |> encode_body
    headers = for({_k,{:raw,v}}<-headers,do: v) |> Enum.join("\r\n")
    headers <> "\r\n\r\n" <> body
  end

  def decode_headers(%MimeMail{}=mail,decoders) do
    Enum.reduce(decoders,mail,fn decoder,acc-> decoder.decode_headers(acc) end)
  end
  def encode_headers(%MimeMail{headers: headers}=mail) do
    %{mail|headers: for({k,v}<-headers, do: {k,encode_header(k,v)})}
  end

  def decode_body(%MimeMail{body: {:raw,body}}=mail) do
    %{headers: headers} = mail = MimeMail.CTParams.decode_headers(mail)
    body = case headers[:'content-disposition'] do
      {"quoted-printable",_}-> body |> qp_to_string
      {"base64",_}-> body |> String.replace(~r/\s/,"") |> Base.decode64!
      _ -> body
    end
    body = case headers[:'content-type'] do
      {"multipart/"<>_,%{boundary: bound}}-> 
        body |> String.split(bound) |> Enum.map(&from_string/1) |> Enum.map(&decode_body/1)
      {"text/"<>_,%{charset: charset}} ->
        body |> Iconv.conv(charset,"utf8")
      _ -> body
    end
    %{mail|body: body}
  end
  def decode_body(%MimeMail{body: _}=mail), do: mail

  def encode_body(%MimeMail{body: {:raw,_body}}=mail), do: mail
  def encode_body(%MimeMail{body: body}=mail) when is_binary(body) do
    mail = MimeMail.CTParams.decode_headers(mail)
    case mail.headers[:'content-type'] do
      {"text/"<>_=type,params}-> 
        headers = mail.headers 
        |> Dict.put(:'content-type',{type,Dict.put(params,:charset,"utf-8")})
        |> Dict.put(:'content-transfer-encoding',"quoted-printable")
        %{mail|headers: headers, body: {:raw,string_to_qp(body)}}
      _->
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
      Enum.concat(Enum.map(eol,&char_to_qp/1),Enum.map(line,fn
        c when c == ?\t or (c < 127 and c > 31 and c !== ?=) -> c
        c -> char_to_qp(c)
      end)) |> Enum.reverse |> Kernel.to_string |> chunk_line
    end) |> Enum.join("\r\n")
  end
  defp char_to_qp(char), do: for(<<a,b<-Base.encode16(<<char::utf8>>)>>,into: "",do: <<?=,a,b>>)
  defp chunk_line(<<vline::size(73)-binary,?=,rest::binary>>), do: (vline<>"=\r\n"<>chunk_line("="<>rest))
  defp chunk_line(<<vline::size(74)-binary,?=,rest::binary>>), do: (vline<>"=\r\n"<>chunk_line("="<>rest))
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

  def unfold_header(value), do: 
    String.replace(value,~r/\r\n([\t ])/,"\\1")

  def fold_header(header), do:
    (header |> String.split("\r\n") |> Enum.map(&fold_header(&1,[])) |> Enum.join("\r\n"))
  def fold_header(<<line::size(65)-binary,rest::binary>>,acc) do
    case ('#{line}' |> Enum.reverse |> Enum.split_while(&(&1!==?\t and &1!==?\s))) do
      {eol,[]}-> fold_header(rest,[eol|acc])
      {eol,bol}-> fold_header("#{Enum.reverse(eol)}"<>rest,["\r\n          ",bol|acc])
    end
  end
  def fold_header(other,acc), do:
    ((acc |> List.flatten |> Enum.reverse |> Kernel.to_string)<>other)

  def header_value(value) do
    case String.split(value,~r/:\s*/, parts: 2) do
      [_]->""
      [_,v]-> unfold_header(v)
    end
  end

  def ensure_ascii(bin) do
    for(<<c<-bin>>, (c<127 and c>31) or c in [?\t,?\r,?\n], do: c)
    |> Kernel.to_string
  end

  def encode_header(_,{:raw,value}), do: {:raw,value}
  def encode_header(key,value) do
    key = key |> encode_header_key |> ensure_ascii
    value = value |> MimeMail.Header.to_ascii |> ensure_ascii |> fold_header
    {:raw,"#{key}: #{value}"}
  end
  def encode_header_key(key), do:
    (String.split("#{key}","-") |> Enum.map(&header_key/1) |> Enum.join("-"))
  def header_key(word) when word in ["dkim","spf","x","id","mime"], do: #acronym, upcase
    String.upcase(word)
  def header_key(word), do: # not acronym, camelcase
    String.capitalize(word)
end

defprotocol MimeMail.Header do
  def to_ascii(term)
end

defmodule Iconv do
  @on_load :init
  def init, do: :erlang.load_nif('#{:code.priv_dir(:mailibex)}/Elixir.Iconv_nif',0)
  @doc "iconv interface, from and to are encoding supported by iconv"
  def conv(_str,_from,_to), do: exit(:nif_library_not_loaded)
end
