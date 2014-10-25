defmodule DKIM do
  def check(%Mailibex{}=mail) do
    %{headers: headers, raw: body} = Mailibex.with(mail,DKIM)
    sig = headers[:'dkim-signature'].v
    if (sig.bh == body_hash(body,sig)) do
      case :inet_res.lookup('#{sig.s}._domainkey.#{sig.d}', :in, :txt) do
        [rec|_] -> 
          pubkey = Mailibex.parse_params(IO.chardata_to_string(rec))
          if :"#{pubkey[:k]||"rsa"}" == sig.a.sig do
            case extract_key64(pubkey[:p]||"") do
              {:ok,key}->
                header_h = headers_hash(headers,sig)
                if :crypto.verify(:rsa,:sha256,header_h,sig.b,key) do
                  {:ok,{sig.s,sig.d}}
                else {:error,:sig_not_match} end
              :error-> {:error,:invalid_pub_key} end
          else {:error,:sig_algo_not_match} end
        _ -> {:error,{:unavailable_pubkey,"#{sig.s}._domainkey.#{sig.d}"}} end
    else {:error,:body_hash_no_match} end
  end
  def sign(%Mailibex{headers: headers}=mail,sig_params \\ []) do
    mail=%{mail|headers: Dict.delete(headers,:'dkim-signature')}
  end

  def parse(%Mailibex{headers: headers}=mail,_rec) do
    case headers[:'dkim-signature'] do
      %{raw: raw, v: nil}-> 
        sig = Mailibex.parse_params(raw)
        |> Dict.update(:c,%{header: :simple,body: :simple},fn sig_c->
             case String.split(sig_c,"/") do
               [t] -> %{header: :"#{t}",body: :simple}
               [t1,t2] -> %{header: :"#{t1}",body: :"#{t2}"}
               _ -> %{header: :simple,body: :simple}
             end
           end)
        |> Dict.update(:b,"", fn sig_b->
             case Base.decode64(String.replace(sig_b,~r/\s/,"")) do
               {:ok,b}->b
               :error-> ""
             end
           end)
        |> Dict.update(:a,%{sig: :rsa, hash: :sha256}, fn sig_a->
            case String.split(sig_a,"-") do
              [sig,hash]->%{sig: :"#{sig}",hash: :"#{hash}"}
              _ ->%{sig: :rsa, hash: :sha256}
            end
           end)
        |> Dict.update(:l,nil, fn sig_l->
             case Integer.parse(sig_l) do
               :error->nil
               {l,_}->l
             end
           end)
        |> Dict.update(:bh,"", &String.replace(&1,~r/\s/,""))
        |> Dict.update(:h,[],fn e->e|>String.downcase|>String.split(":")|>Enum.map(&String.to_atom/1) end)
        put_in(mail,[:headers,:'dkim-signature',:v],sig)
      _ -> mail
    end
  end

  def canon_header(header,:simple), do: header
  def canon_header(header,:relaxed) do
    [k,v] = String.split(header,~r/\s*:\s*/, parts: 2)
    "#{String.downcase(k)}:#{v |> Mailibex.unfold |> String.replace(~r"[\t ]+"," ") |> String.rstrip}"
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
    |>Base.encode64
  end
  def headers_hash(headers,sig) do
    sig.h
    |> Enum.filter(&Dict.has_key?(headers,&1))
    |> Enum.map(&(canon_header(headers[&1].raw,sig.c.header)))
    |> Enum.concat([headers[:"dkim-signature"].raw
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
