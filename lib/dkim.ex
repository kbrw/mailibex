defmodule DKIM do
  defstruct h: [:to,:from,:date,:subject,:"message-id",:"mime-version"], c: %{header: :relaxed, body: :simple},
            d: "example.org", s: "default", a: %{sig: :rsa, hash: :sha256}, b: "", bh: "", l: nil, v: "1",
            x: nil, i: nil, q: "dns/txt", t: nil, z: nil

  def check(mail) when is_binary(mail), do:
    check(MimeMail.from_string(mail))
  def check(%MimeMail{headers: headers,body: {:raw,body}}=mail) do
    mail = decode_headers(mail)
    case Dict.get(mail.headers, :"dkim-signature") do
      nil -> :none
      sig ->
        if (sig.bh == body_hash(body,sig)) do
          case :inet_res.lookup('#{sig.s}._domainkey.#{sig.d}', :in, :txt, edns: 0) do
            [rec|_] ->
              pubkey = MimeMail.Params.parse_header(IO.chardata_to_string(rec))
              if :"#{pubkey[:k]||"rsa"}" == sig.a.sig do
                case extract_key64(pubkey[:p]||"") do
                  {:ok,key}->
                    header_h = headers_hash(headers,sig)
                    if :crypto.verify(:rsa,:sha256,header_h,sig.b,key) do
                      {:pass,{sig.s,sig.d}}
                    else {:permfail,:sig_not_match} end
                  :error-> {:permfail,:invalid_pub_key} end
              else {:permfail,:sig_algo_not_match} end
            _ -> :tempfail end
        else {:permfail,:body_hash_no_match} end
    end
  end

  def sign(mail,key,sig_params \\ []) do
    sig = struct(DKIM,sig_params)
    %{body: {:raw,body}}=encoded_mail=MimeMail.encode_body(mail) #ensure body is binary
    sig = %{sig| bh: body_hash(body,sig)} #add body hash
    encoded_mail = MimeMail.encode_headers(%{encoded_mail|headers: Dict.put(encoded_mail.headers,:'dkim-signature',sig)}) #encoded mail without dkim.b
    sig = %{sig| b: encoded_mail.headers |> headers_hash(sig) |> :public_key.sign(:sha256,key)}
    %{encoded_mail|headers: Dict.put(encoded_mail.headers,:'dkim-signature',sig)}
  end

  def decode_headers(%MimeMail{headers: headers}=mail) do
    case Dict.get(headers, :"dkim-signature") do
      {:raw,raw} ->
        unquoted = MimeMail.header_value(raw)
        sig = struct(DKIM,for({k,v}<-MimeMail.Params.parse_header(unquoted),do: {k,decode_field(k,v)}))
        %MimeMail{mail | headers: put_in(mail.headers, [:"dkim-signature"], sig)}
      _ -> mail
    end
  end

  defp decode_field(:c,c) do
    case String.split(c,"/") do
      [t] -> %{header: :"#{t}",body: :simple}
      [t1,t2] -> %{header: :"#{t1}",body: :"#{t2}"}
      _ -> %{header: :simple,body: :simple}
    end
  end
  defp decode_field(:b,b) do
    case Base.decode64(String.replace(b,~r/\s/,"")) do
      {:ok,b}->b
      :error-> ""
    end
  end
  defp decode_field(:a,a) do
    case String.split(a,"-") do
      [sig,hash]->%{sig: :"#{sig}",hash: :"#{hash}"}
      _ ->%{sig: :rsa, hash: :sha256}
    end
  end
  defp decode_field(:l,l) do
    case Integer.parse(l) do
      :error->nil
      {l,_}->l
    end
  end
  defp decode_field(:bh,bh) do
    case (bh |> String.replace(~r/\s/,"") |> Base.decode64) do
      {:ok,b}->b
      :error-> ""
    end
  end
  defp decode_field(:h,h), do:
    (h|>String.downcase|>String.split(":")|>Enum.map(&String.to_atom/1))
  defp decode_field(_,e), do: e

  def canon_header(header,:simple), do: header
  def canon_header(header,:relaxed) do
    [k,v] = String.split(header,~r/\s*:\s*/, parts: 2)
    "#{String.downcase(k)}:#{v |> MimeMail.unfold_header |> String.replace(~r"[\t ]+"," ") |> String.rstrip}"
  end

  def canon_body(body,:simple), do:
    String.replace(body,~r/(\r\n)*$/,"\r\n", global: false)
  def canon_body(body,:relaxed) do
    body
    |> String.replace(~r/[\t ]+\r\n/, "\r\n")
    |> String.replace(~r/[\t ]+/, " ")
    |> String.replace(~r/(\r\n)*$/,"\r\n", global: false)
  end

  def truncate_body(body,nil), do: body
  def truncate_body(body,l) when is_integer(l) do
    <<trunc_body::binary-size(l),_::binary>> = body
    trunc_body
  end

  def hash(bin,:sha256), do: :crypto.hash(:sha256,bin)
  def hash(bin,:sha1), do: :crypto.hash(:sha,bin)

  def body_hash(body,sig) do
    body
    |>canon_body(sig.c.body)
    |>truncate_body(sig.l)
    |>hash(sig.a.hash)
  end
  def headers_hash(headers,sig) do
    {:raw,rawsig} = headers[:"dkim-signature"]
    sig.h
    |> Enum.filter(&Dict.has_key?(headers,&1))
    |> Enum.map(fn k->
         {:raw,v}=headers[k]
         canon_header(v,sig.c.header)
        end)
    |> Enum.concat([rawsig
                    |>canon_header(sig.c.header)
                    |>String.replace(~r/b=[^;]*/,"b=")])
    |> Enum.join("\r\n")
  end

  def extract_key64(data64) do
    case Base.decode64(String.replace(data64,~r/\s/,"")) do
      {:ok,data}->extract_key(data)
      _ -> :error
    end
  end
  # asn sizeof pubkey,rsapubkey,modulus > 128 <=> len = {1::1,lensize::7,objlen::lensize}
  # asn sizeof exp, algoid < 128 <=> len = {objlen::8}
  # ASN1 pubkey::SEQ(48){ algo::SEQ(48){Algoid,Algoparams}, pubkey::BITSTRING(3) }
  def extract_key(<<48,1::size(1)-unit(1),ll0::size(7),_l0::size(ll0)-unit(8),
           48,l1,_algoid::size(l1)-binary,
           3,1::size(1)-unit(1),ll2::size(7),l2::size(ll2)-unit(8),des_rsapub::size(l2)-binary>>) do
    extract_key(des_rsapub)
  end
  # ASN1 rsapubkey::SEQ(48){ modulus::INT(2), exp::INT(2) }
  def extract_key(<<48,1::size(1)-unit(1),ll0::size(7),_l0::size(ll0)-unit(8),
             2,1::size(1)-unit(1),ll1::size(7),l1::size(ll1)-unit(8),mod::size(l1)-binary,
             2,l2,exp::size(l2)-unit(8)-binary>>) do
    {:ok,[exp,mod]}
  end
  def extract_key(<<0,rest::binary>>), do: extract_key(rest) # strip leading 0 if needed
  def extract_key(_), do: :error
end

defimpl MimeMail.Header, for: DKIM do
  def to_ascii(dkim) do
    for({k,v}<-Map.from_struct(dkim), v !== nil,do: "#{k}=#{encode_field(k,v)}")
    |> Enum.join("; ")
  end
  defp encode_field(:h,h), do: Enum.join(h,":")
  defp encode_field(:c,c), do: "#{c.header}/#{c.body}"
  defp encode_field(:a,a), do: "#{a.sig}-#{a.hash}"
  defp encode_field(:bh,bh), do: Base.encode64(bh)
  defp encode_field(:b,b), do: (Base.encode64(b) |> chunk_hard([]) |> Enum.join("\r\n            "))
  defp encode_field(_,e), do: Kernel.to_string(e)

  defp chunk_hard(<<vline::size(50)-binary,rest::binary>>,acc), do: chunk_hard(rest,[vline|acc])
  defp chunk_hard(other,acc), do: Enum.reverse([other|acc])
end
