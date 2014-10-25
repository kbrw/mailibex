defmodule DKIM do
  def check(mail) do
    {headers,body}=split_body(mail)
    headers = parse_headers(headers)
    sig = parse_params(headers["dkim-signature"].value)
    {cano_h,cano_body,sig_alg,hash_alg} = select_algos(sig.a,sig.c)
    if (sig.bh == body_hash(body,cano_body,hash_alg,sig[:l])) do
      case :inet_res.lookup('#{sig.s}._domainkey.#{sig.d}', :in, :txt) do
        [rec|_] -> 
          pubkey = parse_params(IO.chardata_to_string(rec))
          if :"#{pubkey.k}" == sig_alg do
            header_h = headers_hash(headers,sig.h,cano_h)
            target_sig = Base.decode64!(String.replace(sig.b,~r/\s/,""))
            key = extract_key(Base.decode64!(pubkey.p))
            if :crypto.verify(:rsa,:sha256,header_h,target_sig,key) do
              {:ok,{sig.s,sig.d}}
            else {:error,:sig_not_match} end
          else {:error,:sig_algo_not_match} end
        _ -> {:error,"DKIM key unavailable for #{sig.s}._domainkey.#{sig.d}"} end
    else {:error,:body_hash_no_match} end
  end

  def split_body(data), do: 
    (data |> String.split("\r\n\r\n",parts: 2) |> List.to_tuple)
  
  def parse_params(param) do
    param
    |> String.split(~r"\s*;\s*",trim: true)
    |> Enum.map(fn e-> [k,v]=String.split(e,"=",parts: 2);{:"#{k}",v} end)
    |> Enum.into(%{})
  end
  def parse_headers(headers) when is_binary(headers) do
    headers
    |> String.replace(~r/\r\n([^\t ])/,"\r\n!\\1")
    |> String.split("\r\n!")
    |> Enum.map(fn e->
         [k,v]=String.split(canon_header(e,:relaxed),":", parts: 2)
         {k,%{raw: e,value: v}}
       end)
    |> Enum.into(%{})
  end

  def unfold(value), do: 
    String.replace(value,~r/\r\n([\t ])/,"\\1")

  def select_algos(sig_a,sig_c) do
    {cano_h,cano_body}=case String.split(sig_c,"/") do
      [t] -> {:"#{t}",:simple}
      [t1,t2] -> {:"#{t1}",:"#{t2}"}
    end
    [sig_alg,hash_alg]=for e<-String.split(sig_a,"-"), do: :"#{e}"
    {cano_h,cano_body,sig_alg,hash_alg}
  end

  def canon_header(header,:simple), do: header
  def canon_header(header,:relaxed) do
    [k,v] = String.split(header,~r/\s*:\s*/, parts: 2)
    "#{String.downcase(k)}:#{v |> unfold |> String.replace(~r"[\t ]+"," ") |> String.rstrip}"
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
  def truncate_body(body,l) when is_binary(l), do:
    truncate_body(body,elem(Integer.parse(l),0))
  def truncate_body(body,l) when is_integer(l) do
    <<trunc_body::binary-size(l),_::binary>> = body
    trunc_body
  end
  
  def hash(bin,:sha256), do: :crypto.hash(:sha256,bin)
  def hash(bin,:sha1), do: :crypto.hash(:sha,bin)

  def body_hash(body,cano_alg,hash_alg,trunc_l \\ nil) do
    body
    |>canon_body(cano_alg)
    |>truncate_body(trunc_l)
    |>hash(hash_alg)
    |>Base.encode64
  end
  def headers_hash(headers,sig_h,cano_alg) do
    sig_h
    |> String.split(":")
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(&Dict.has_key?(headers,&1))
    |> Enum.map(&(canon_header(headers[&1].raw,cano_alg)))
    |> Enum.concat([headers["dkim-signature"].raw
                    |>canon_header(cano_alg)
                    |>String.replace(~r/b=[^;]*/,"b=")])
    |> Enum.join("\r\n")
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
    [exp,mod]
  end
  def extract_key(<<0,rest::binary>>), do: extract_key(rest) # strip leading 0 if needed
end
