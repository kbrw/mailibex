defmodule SPF do
  
  @doc """
  check_host param = %{sender: "me@example.org", client_ip: {1,2,3,4}, helo: "relay.com", curr_domain: "me.com"}
  """
  def check_host(%{sender: sender}=params) do
    lookup_limit_reset
    check_host(params,sender|>String.split("@")|>Enum.at(1))
  end

  # none, :neutral,:pass,:fail,:softfail,:temperror,:permerror
  defp check_host(params,domain) do
    params = Dict.put(params,:domain,domain)
    if lookup_limit_exceeded do :permerror else
      case :inet_res.lookup('#{domain}', :in, :txt, edns: 0) do
        [] -> :temperror
        recs ->
          case for(rec<-recs,"v=spf1 "<>rule=Enum.join(rec),do: rule) do
            [rule] -> apply_rule(rule,params)
            [] -> :none
          end
      end
    end
  end

  def apply_rule(rule,params) do
    try do
      terms = rule |> String.strip |> String.split(" ")
      {modifiers,mechanisms} = Enum.partition(terms,&Regex.match?(~r/^[^:\/]+=/,&1))
      modifiers = Enum.map modifiers, fn modifier->
        [name,value]=String.split(modifier,"=")
        {:"#{name}",target_name(value,params) || ""}
      end
      matches = Enum.map mechanisms, fn term->
        fn-> 
          {ret,term} = return(term)
          case term_match(term,params) do
            :match->ret
            :notmatch->false
            other->other
          end
        end
      end
      result = Enum.find_value(matches,&(&1.()))
      result = result || if modifiers[:redirect] do
        case check_host(params,modifiers[:redirect]) do
          :none->:permerror
          other->other
        end
      end
      result = result || :neutral
      defaultfail = "domain of #{params.sender} does not designate #{:inet.ntoa params.client_ip} as permitted sender"
      case {result,modifiers[:exp]} do
        {:fail,nil}->{:fail,defaultfail}
        {:fail,expdomain}->
          try do
            false = lookup_limit_exceeded
            [rec] = :inet_res.lookup('#{expdomain}', :in, :txt, edns: 0)
            {:fail,rec|>IO.chardata_to_string|>target_name(params)}
          catch _, _ -> {:fail,defaultfail}
          end
        {ret,_}->ret
      end
    catch
      _, r -> 
        IO.puts inspect r
        IO.puts inspect(System.stacktrace, pretty: true)
        :permerror
    end
  end

  defp return("+"<>rest), do: {:pass,rest}
  defp return("-"<>rest), do: {:fail,rest}
  defp return("~"<>rest), do: {:softfail,rest}
  defp return("?"<>rest), do: {:neutral,rest}
  defp return(term), do: {:pass,term}

  def term_match("all",_), do: :match
  def term_match("include:"<>domain_spec,params) do
    case check_host(params,target_name(domain_spec,params)) do
      :pass -> :match
      {:fail,_} -> :notmatch
      res when res in [:softfail,:neutral] -> :notmatch
      res when res in [:permerror,:none] -> :permerror
      :temperror -> :temperror
    end
  end
  def term_match("a"<>arg,params) do
    domain_spec = if match?(":"<>_,arg), do: String.lstrip(arg,?:), else: params.domain<>arg
    family = if tuple_size(params.client_ip) == 4, do: :inet, else: :inet6
    {domain,prefix}=extract_prefix(target_name(domain_spec,params),family)
    false = lookup_limit_exceeded
    case :inet_res.gethostbyname('#{domain}',family) do
      {:ok,{:hostent,_,_,_,_,ip_list}}-> 
        if Enum.any?(ip_list,&ip_in_network(params.client_ip,&1,prefix)), do: :match, else: :notmatch
      _->:notmatch
    end
  end
  def term_match("mx"<>arg,params) do
    domain_spec = if match?(":"<>_,arg), do: String.lstrip(arg,?:), else: params.domain<>arg
    family = if tuple_size(params.client_ip) == 4, do: :inet, else: :inet6
    {domain,prefix}=extract_prefix(target_name(domain_spec,params),family)
    false = lookup_limit_exceeded
    case :inet_res.lookup('#{domain}', :in, :mx, edns: 0) do
      []->:notmatch
      res-> 
        Enum.find_value(res,fn {_prio,name}->
          false = lookup_limit_exceeded
          case :inet_res.gethostbyname(name,family) do
            {:ok,{:hostent,_,_,_,_,ip_list}}-> 
              if Enum.any?(ip_list,&ip_in_network(params.client_ip,&1,prefix)), do: :match
            _->false
          end
        end) || :notmatch
    end
  end
  def term_match("ptr"<>arg,params) do
    domain_spec = if arg=="", do: params.domain, else: String.lstrip(arg,?:)
    family = if tuple_size(params.client_ip) == 4, do: :inet, else: :inet6
    false = lookup_limit_exceeded
    case :inet_res.gethostbyaddr(params.client_ip) do
      {:ok,{:hostent,name,_,_,_,_}}->
        false = lookup_limit_exceeded
        case :inet_res.gethostbyname(name,family) do
          {:ok,{:hostent,_,_,_,_,ip_list}}-> 
            if params.client_ip in ip_list do
              if String.ends_with?("#{name}",target_name(domain_spec,params)), do: :match, else: :notmatch
            else :notmatch end
          _->:notmatch
        end
      {:error,_}->:notmatch
    end
  end
  def term_match(<<"ip",v,":",addr_spec::binary>>,params) when v in [?4,?6] do
    family = if tuple_size(params.client_ip) == 4, do: :inet, else: :inet6
    if (family==:inet and v !== ?4) or (family==:inet6 and v !== ?6) do :notmatch else
      {addr_spec,prefix}=extract_prefix(target_name(addr_spec,params),family)
      case :inet.parse_address('#{addr_spec}') do
        {:ok,addr} when (tuple_size(addr)==4 and family==:inet) or
                        (tuple_size(addr)==8 and family==:inet6)->
          if ip_in_network(params.client_ip,addr,prefix), do: :match, else: :notmatch
      end
    end
  end
  def term_match("exists:"<>domain_spec,params) do
    false = lookup_limit_exceeded
    case :inet_res.gethostbyname('#{target_name(domain_spec,params)}',:inet) do
      {:ok,{:hostent,_,_,_,_,ip_list}} when length(ip_list)>0-> :match
      _->:notmatch
    end
  end

  def lookup_limit_reset, do: 
    Process.put(:lookups,0)
  def lookup_limit_exceeded do
   case Process.get(:lookups,0) do
     10 -> true
     count -> Process.put(:lookups,count+1) ; false
   end
  end

  def extract_prefix(domain_spec,family) when is_binary(domain_spec), do:
    extract_prefix(String.split(domain_spec,"/"),family)

  def extract_prefix([domain,_,v6pref],:inet6), do:
    extract_prefix([domain,v6pref],:inet6)
  def extract_prefix([domain,pref|_],_) do
    {pref,_}=Integer.parse(pref)
    {domain,pref}
  end
  def extract_prefix([domain],:inet), do: 
    {domain,32}
  def extract_prefix([domain],:inet6), do: 
    {domain,128}

  defp bin_ip({ip1,ip2,ip3,ip4}), do:
    <<ip1::size(8),ip2::size(8),ip3::size(8),ip4::size(8)>>
  defp bin_ip({ip1,ip2,ip3,ip4,ip5,ip6,ip7,ip8}), do:
    <<ip1::size(4),ip2::size(16),ip3::size(16),ip4::size(16),ip5::size(16),ip6::size(16),ip7::size(16),ip8::size(16)>>
  defp int_ip(addr) do
    ip = bin_ip(addr) ; bitlen = bit_size(ip)
    <<ip::size(bitlen)>> = ip
    {bitlen,ip}
  end

  import Bitwise
  def ip_in_network(addr,net_addr,bitprefix) do
    {{bitlen,net_ip},{bitlen,ip}} = {int_ip(net_addr),int_ip(addr)}
    <<fullone::size(bitlen)>> = :binary.copy(<<0b11111111>>,div(bitlen,8))
    mask = fullone <<< (bitlen-bitprefix) # mask is bitprefix*1 + (bitlen-bitprefix)*0
    (mask &&& net_ip) == (mask &&& ip)
  end

  def target_name(name,params), do: 
    target_name(name,params,[])

  def target_name("",_,acc), do: 
    (acc |> Enum.reverse |> to_string)
  def target_name(<<"%{",macro,rest::binary>>,params,acc) 
      when macro in [?s,?l,?o,?d,?i,?p,?h,?c,?r,?t,?v,?S,?L,?O,?D,?I,?P,?H,?C,?R,?T,?V] do
    expanded = target_name_macro(String.downcase(<<macro>>),params)
    [transfo,rest] = String.split(rest,"}",parts: 2)
    expanded = case Integer.parse(String.downcase(transfo)) do
      {digits,splitspec}->target_name_transfo(expanded,-digits,splitspec)
      :error->target_name_transfo(expanded,0,transfo)
    end
    target_name(rest,params,[URI.encode(expanded)|acc])
  end
  def target_name("%%"<>rest,params,acc), do: 
    target_name(rest,params,[?%|acc])
  def target_name("%_"<>rest,params,acc), do: 
    target_name(rest,params,[?\s|acc])
  def target_name("%-"<>rest,params,acc), do: 
    target_name(rest,params,["%20"|acc])
  def target_name("%"<>_,_,_), do: throw(:wrongmacro)
  def target_name(<<c,rest::binary>>,params,acc), do:
    target_name(rest,params,[c|acc])

  def target_name_macro("s",%{sender: sender}), do: sender
  def target_name_macro("l",%{sender: sender}), do: (sender|>String.split("@")|>hd)
  def target_name_macro("o",%{sender: sender}), do: (sender|>String.split("@")|>Enum.at(1))
  def target_name_macro("d",%{domain: domain}), do: domain
  def target_name_macro("i",%{client_ip: {ip1,ip2,ip3,ip4,ip5,ip6,ip7,ip8}}) do
    <<ip1::size(16),ip2::size(16),ip3::size(16),ip4::size(16),ip5::size(16),ip6::size(16),ip7::size(16),ip8::size(16)>>
    |> Base.encode16(case: :lower)
    |> String.split("")
    |> Enum.join(".")
    |> String.strip(?.)
  end
  def target_name_macro("i",%{client_ip: {_,_,_,_}=ip4}) do
    ip4 |> Tuple.to_list |> Enum.join(".")
  end
  def target_name_macro("p",%{client_ip: ip}) do
    false = lookup_limit_exceeded
    family = if tuple_size(ip) == 4, do: :inet, else: :inet6
    case :inet_res.gethostbyaddr(ip) do
      {:ok,{:hostent,name,_,_,_,_}}->
        if not lookup_limit_exceeded do
          case :inet_res.gethostbyname(name,family) do
            {:ok,{:hostent,_,_,_,_,ip_list}}-> 
              if ip in ip_list do "#{name}" else "unknown" end
            _->"unknown"
          end
        end
      {:error,_}->"unknown"
    end
  end
  def target_name_macro("v",%{client_ip: ip}) when tuple_size(ip) == 4, do: "in-addr"
  def target_name_macro("v",%{client_ip: ip}) when tuple_size(ip) == 8, do: "ip6"
  def target_name_macro("h",%{helo: helo}), do: helo
  def target_name_macro("c",%{client_ip: ip}), do: "#{:inet.ntoa ip}"
  def target_name_macro("r",%{curr_domain: curr_domain}), do: curr_domain
  def target_name_macro("t",_) do
    {megasec,sec,_}=:os.timestamp
    "#{megasec*1_000_000+sec}"
  end

  def target_name_transfo(expanded,start_index,"r"<>delimiters), do:
    target_name_transfo(expanded,start_index,true,delimiters)
  def target_name_transfo(expanded,start_index,delimiters), do:
    target_name_transfo(expanded,start_index,false,delimiters)

  def target_name_transfo(expanded,start_index,reversed?,""), do:
    target_name_transfo(expanded,start_index,reversed?,".")
  def target_name_transfo(expanded,start_index,reversed?,delimiters) do
    delimiters = for <<c<-delimiters>>, c in [?.,?-,?+,?,,?/,?_,?=], into: "", do: <<c>>
    components=String.split(expanded,Regex.compile!("["<>delimiters<>"]"))
    components=if reversed?, do: Enum.reverse(components), else: components
    components=Enum.slice(components,max(-length(components),start_index)..-1)
    Enum.join(components,".")
  end
end
