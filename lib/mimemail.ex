defmodule MimeMail do
  @type header :: {:raw,binary} | MimeMail.Header.t #ever the raw line or any term implementing MimeMail.Header.to_ascii
  @type body :: binary | [MimeMail.t] | {:raw,binary} #ever the raw body or list of mail for multipart or binary for decoded content
  @type t :: %MimeMail{headers: [{key::binary,header}], body: body}
  defstruct headers: [], body: ""

  @behaviour Access
  defdelegate get_and_update(dict,k,v), to: Map
  defdelegate fetch(dict,k), to: Map
  defdelegate get(dict,k,v), to: Map
  defdelegate pop(dict,k), to: Map

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
    %{body: {:raw,body},headers: headers} = mail |> encode_body |> encode_headers
    headers = for({_k,{:raw,v}}<-headers,do: v) |> Enum.join("\r\n")
    headers <> "\r\n\r\n" <> body
  end

  def decode_headers(%MimeMail{}=mail,decoders) do
    Enum.reduce(decoders,mail,fn decoder,acc-> decoder.decode_headers(acc) end)
  end
  def encode_headers(%MimeMail{headers: headers}=mail) do
    %{mail|headers: for({k,v}<-headers, do: {k,encode_header(k,v)})}
  end

  def ok_or({:ok,res},_), do: res
  def ok_or(_,default), do: default

  def decode_body(%MimeMail{body: {:raw,body}}=mail) do
    %{headers: headers} = mail = MimeMail.CTParams.decode_headers(mail)
    body = case headers[:'content-transfer-encoding'] do
      {"quoted-printable",_}-> body |> qp_to_binary
      {"base64",_}-> body |> String.replace(~r/\s/,"") |> Base.decode64 |> ok_or("")
      _ -> body
    end
    body = case headers[:'content-type'] do
      {"multipart/"<>_,%{boundary: bound}}-> 
        body |> String.split(~r"\s*--#{bound}\s*") |> Enum.slice(1..-2) |> Enum.map(&from_string/1) |> Enum.map(&decode_body/1)
      {"text/"<>_,%{charset: charset}} ->
        body |> Iconv.conv(charset,"utf8") |> ok_or(ensure_ascii(body)) |> ensure_utf8
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
        headers = Dict.drop(mail.headers,[:'content-type',:'content-transfer-encoding']) ++[
          'content-type': {type,Dict.put(params,:charset,"utf-8")},
          'content-transfer-encoding': "quoted-printable"
        ]
        %{mail|headers: headers, body: {:raw,string_to_qp(body)}}
      _->
        headers = Dict.delete(mail.headers,:'content-transfer-encoding')
                 ++['content-transfer-encoding': "base64"]
        %{mail|headers: headers, body: {:raw,(body |> Base.encode64 |> chunk64 |> Enum.join("\r\n"))}}
    end
  end
  def encode_body(%MimeMail{body: childs}=mail) when is_list(childs) do
    mail = MimeMail.CTParams.decode_headers(mail)
    boundary = Base.encode16(:crypto.rand_bytes(20), case: :lower)
    full_boundary = "--#{boundary}"
    {"multipart/"<>_=type,params} = mail.headers[:'content-type']
    headers = Dict.delete(mail.headers,:'content-type')
              ++['content-type': {type,Dict.put(params,:boundary,boundary)}]
    body = childs |> Enum.map(&MimeMail.to_string/1) |> Enum.join("\r\n\r\n"<>full_boundary<>"\r\n")
    %{mail|body: {:raw,"#{full_boundary}\r\n#{body}\r\n\r\n#{full_boundary}--\r\n"}, headers: headers}
  end

  defp chunk64(<<vline::size(75)-binary,rest::binary>>), do: [vline|chunk64(rest)]
  defp chunk64(other), do: [other]

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
  
  def qp_to_binary(str), do: 
    (str |> String.rstrip |> String.rstrip(?=) |> qp_to_binary([]))
  def qp_to_binary("=\r\n"<>rest,acc), do: 
    qp_to_binary(rest,acc)
  def qp_to_binary(<<?=,x1,x2>><>rest,acc), do: 
    qp_to_binary(rest,[<<x1,x2>> |> String.upcase |> Base.decode16! | acc])
  def qp_to_binary(<<c,rest::binary>>,acc), do:
    qp_to_binary(rest,[c | acc])
  def qp_to_binary("",acc), do:
    (acc |> Enum.reverse |> IO.iodata_to_binary)

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

  def header_value({:raw,value}), do: header_value(value)
  def header_value(value) do
    case String.split(value,~r/:\s*/, parts: 2) do
      [_]->""
      [_,v]-> unfold_header(v)
    end
  end

  def ensure_ascii(bin), do:
    Kernel.to_string(for(<<c<-bin>>, (c<127 and c>31) or c in [?\t,?\r,?\n], do: c))
  def ensure_utf8(bin) do
    bin 
    |> String.chunk(:printable)
    |> Enum.filter(&String.printable?/1)
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
