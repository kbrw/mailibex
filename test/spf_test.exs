defmodule SPFTest do
  use ExUnit.Case
  @moduledoc "most of the tests comes directly from rfc7208"

  setup_all do
    :code.unstick_dir(:code.lib_dir(:kernel)++'/ebin')
    previous_compiler_options = Code.compiler_options(ignore_module_conflict: true)
    defmodule :inet_res do #mock external dns calls to hard define SPF rules
      def lookup(dns,type,class,_opts), do: lookup(dns,type,class)
    
      def gethostbyname('colo.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{127,0,2,1},{127,0,2,2}]}}
      def gethostbyname('_spf2.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{127,0,3,2}]}}
      def gethostbyname('_spf5.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{127,0,3,5}]}}
    
      def gethostbyname('mx1.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{127,0,1,1},{127,0,1,2}]}}
      def gethostbyname('mx2.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{127,0,1,3},{127,0,1,4}]}}

      # examples of rfc7208 appendix A
      def gethostbyname('example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{192,0,2,10},{192,0,2,11}]}}
      def gethostbyname('amy.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{192,0,2,65}]}}
      def gethostbyname('bob.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{192,0,2,66}]}}
      def gethostbyname('mail-a.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{192,0,2,129}]}}
      def gethostbyname('mail-b.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{192,0,2,130}]}}
      def gethostbyname('www.example.com',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{192,0,2,10},{192,0,2,11}]}}
      def gethostbyname('mail-c.example.org',_), do:
        {:ok,{:hostent,nil,nil,nil,nil,[{192,0,2,140}]}}

      def gethostbyname(_,_), do: {:error,nil}
    
      def gethostbyaddr({127,0,0,1}), do:
        {:ok,{:hostent,'example.com',nil,nil,nil,[]}}
      def gethostbyaddr({127,0,3,2}), do:
        {:ok,{:hostent,'_spf2.example.com',nil,nil,nil,[]}}

      # examples of rfc7208 appendix A
      def gethostbyaddr({192,0,2,10}), do:
        {:ok,{:hostent,'example.com',nil,nil,nil,nil}}
      def gethostbyaddr({192,0,2,11}), do:
        {:ok,{:hostent,'example.com',nil,nil,nil,nil}}
      def gethostbyaddr({192,0,2,65}), do:
        {:ok,{:hostent,'amy.example.com',nil,nil,nil,nil}}
      def gethostbyaddr({192,0,2,66}), do:
        {:ok,{:hostent,'bob.example.com',nil,nil,nil,nil}}
      def gethostbyaddr({192,0,2,129}), do:
        {:ok,{:hostent,'mail-a.example.com',nil,nil,nil,nil}}
      def gethostbyaddr({192,0,2,130}), do:
        {:ok,{:hostent,'mail-b.example.com',nil,nil,nil,nil}}
      def gethostbyaddr({192,0,2,140}), do:
        {:ok,{:hostent,'mail-c.example.org',nil,nil,nil,nil}}
      def gethostbyaddr({10,0,0,4}), do:
        {:ok,{:hostent,'bob.example.com',nil,nil,nil,nil}}

      def gethostbyaddr(_), do: {:error,nil}
    
      def lookup('_spf1.example.com',:in,:txt), do:
        [['v=spf1 +mx a:colo.example.com/28 -all']]
      def lookup('_spf1.example.com',:in,:mx), do:
        [{1,'mx1.example.com'},{2,'mx2.example.com'}]
      def lookup('_spf2.example.com',:in,:txt), do:
        [['v=spf1 -ptr +all']]
      def lookup('_spf4.example.com',:in,:txt), do:
        [['v=spf1 -mx redirect=_spf1.example.com']]
      def lookup('_spf4.example.com',:in,:mx), do:
        [{1,'mx1.example.com'},{2,'mx2.example.com'}]
      def lookup('_spf5.example.com',:in,:txt), do:
        [['v=spf1 a mx -all']]
      def lookup('_spf5.example.com',:in,:mx), do:
        [{1,'mx1.example.com'},{2,'mx2.example.com'}]
      def lookup('_spf6.example.com',:in,:txt), do:
        [['v=spf1 include:_spf1.example.com include:_spf2.example.com -all']]
      def lookup('_spf7.example.com',:in,:txt), do:
        [['v=spf1 exists:%{ir}.%{l1r+-}._spf.%{d} -all']]
      def lookup('_spf8.example.com',:in,:txt), do:
        [['v=spf1 redirect=_spf.example.com']]
      def lookup('_spf9.example.com',:in,:txt), do:
        [['v=spf1 mx:example.com -all']]
      def lookup('_spf10.example.com',:in,:txt), do:
        [['v=spf1 mx -all exp=explain._spf.%{d}']]
      def lookup('explain._spf._spf10.example.com',:in,:txt), do:
        [['See http://%{d}','/why.html?s=%{S}&i=%{I}']]
      def lookup('_spf11.example.com',:in,:txt), do:
        [['v=spf1 mx -all exp=explain._spf.%{d}']]
      def lookup('_spf111.example.com',:in,:txt), do:
        [['v=spf1 mx -all exp=explain._spf.%{d}']]
      def lookup('explain._spf._spf111.example.com',:in,:txt), do:
        [['this message is %(d) wrong']]
      def lookup('_spf12.example.com',:in,:txt), do:
        [['v=spf1 ip4:192.0.2.1 ip4:192.0.2.129 -all']]
      def lookup('_spf13.example.com',:in,:txt), do:
        [['v=spf1 a:authorized-spf.example.com -all']]
      def lookup('_spf14.example.com',:in,:txt), do:
        [['v=spf1 mx:example.com -all']]
      def lookup('_spf15.example.com',:in,:txt), do:
        [['v=spf1 ip4:192.0.2.0/24 mx -all']]
      def lookup('_spf16.example.com',:in,:txt), do:
        [['v=spf1 -all']]
      def lookup('_spf17.example.com',:in,:txt), do:
        [['v=spf1 a -all']]
      def lookup('_spf27.example.com',:in,:txt), do:
        [['v=spf1 include:example.com include:example.net -all']]
      def lookup('_spf28.example.com',:in,:txt), do:
        [['v=spf1 ','-include:ip4._spf.%{d} ','-include:ptr._spf.%{d} ','+all']]
      def lookup('_spf29.example.com',:in,:txt), do:
        [['v=spf1 -ip4:192.0.2.0/24 +all']]

      # examples of rfc7208 appendix A
      def lookup('example.com',:in,:mx), do:
        [{10,'mail-a.example.com'},{20,'mail-b.example.com'}]
      def lookup('example.org',:in,:mx), do:
        [{10,'mail-c.example.org'}]

      def lookup(_,_,_), do: []
    end
    _ = Code.compiler_options(previous_compiler_options)
    :ok
  end
      
  test "single macro expansion" do
    params = %{sender: "strong-bad@email.example.com", client_ip: {192,0,2,3}, helo: "mx.example.com",
               curr_domain: "server.com",domain: "email.example.com"}
    assert "strong-bad@email.example.com"=SPF.target_name("%{s}",params)
    assert "email.example.com"=SPF.target_name("%{o}",params)
    assert "email.example.com"=SPF.target_name("%{d}",params)
    assert "email.example.com"=SPF.target_name("%{d4}",params)
    assert "email.example.com"=SPF.target_name("%{d3}",params)
    assert "example.com"=SPF.target_name("%{d2}",params)
    assert "com"=SPF.target_name("%{d1}",params)
    assert "com.example.email"=SPF.target_name("%{dr}",params)
    assert "example.email"=SPF.target_name("%{d2r}",params)
    assert "strong-bad"=SPF.target_name("%{l}",params)
    assert "strong.bad"=SPF.target_name("%{l-}",params)
    assert "strong-bad"=SPF.target_name("%{lr}",params)
    assert "bad.strong"=SPF.target_name("%{lr-}",params)
    assert "strong"=SPF.target_name("%{l1r-}",params)
  end
  
  test "complex string macro expansion" do
    params = %{sender: "strong-bad@email.example.com", client_ip: {192,0,2,3}, helo: "mx.example.org",
               curr_domain: "server.com",domain: "email.example.com"}
    assert "3.2.0.192.in-addr._spf.example.com"=SPF.target_name("%{ir}.%{v}._spf.%{d2}",params)
    assert "bad.strong.lp._spf.example.com"=SPF.target_name("%{lr-}.lp._spf.%{d2}",params)
    assert "bad.strong.lp.3.2.0.192.in-addr._spf.example.com"=SPF.target_name("%{lr-}.lp.%{ir}.%{v}._spf.%{d2}",params)
    assert "3.2.0.192.in-addr.strong.lp._spf.example.com"=SPF.target_name("%{ir}.%{v}.%{l1r-}.lp._spf.%{d2}",params)
    assert "example.com.trusted-domains.example.net"=SPF.target_name("%{d2}.trusted-domains.example.net",params)
  end
  
  test "ipv6 macro expansion" do
    params = %{sender: "strong-bad@email.example.com", client_ip: {8193, 3512, 0, 0, 0, 0, 0, 51969}, helo: "mx.example.org",
               curr_domain: "server.com",domain: "email.example.com"}
    assert "1.0.b.c.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6._spf.example.com"
           =SPF.target_name("%{ir}.%{v}._spf.%{d2}",params)
  end
  
  test "mix spf policies" do
    # _spf1.example.com => v=spf1 +mx a:colo.example.com/28 -all
    assert :pass =  # not match mx rule, but match a/28 rule
             SPF.check("toto@_spf1.example.com",{127,0,2,3})
    assert {:fail,_} = # not match mx rule, neither "a/28" rule, so -all
             SPF.check("toto@_spf1.example.com",{127,0,1,10})
    assert :pass = # match first mx rule
             SPF.check("toto@_spf1.example.com",{127,0,1,4})
    # _spf2.example.com => v=spf1 -ptr +all
    assert :pass = # has no ptr, so match +all
             SPF.check("toto@_spf2.example.com",{128,0,0,1})
    assert :pass = # has ptr but not subdomain of _spf2.example.com, so match +all
             SPF.check("toto@_spf2.example.com",{127,0,0,1})
    assert {:fail,_} = # has ptr subdomain of _spf2.example.com
             SPF.check("toto@_spf2.example.com",{127,0,3,2})
    # _spf4.example.com => v=spf1 -mx redirect=_spf1.example.com
    assert {:fail,_} =  # match mx rule, so no redirection and fail
             SPF.check("toto@_spf4.example.com",{127,0,1,2})
    assert :pass =  # not match mx rule, but match a/28 rule of _spf1
             SPF.check("toto@_spf4.example.com",{127,0,2,3})
  end
  
  test "use a custom fail message : exp= or default" do
    # _spf10.example.com => v=spf1 mx -all exp=explain._spf.%{d}
    assert {:fail,"See http://_spf10.example.com/why.html?s=toto@_spf10.example.com&i=127.0.2.3"} = 
             SPF.check("toto@_spf10.example.com",{127,0,2,3})
    # _spf11 same as 10 but not txt record at explain._spf._spf11.example.com
    assert {:fail,"domain of "<>_} = 
             SPF.check("toto@_spf11.example.com",{127,0,2,3})
    # _spf111 same as 10 but a txt record is malformed at explain._spf._spf111.example.com
    assert {:fail,"domain of "<>_} = 
             SPF.check("toto@_spf111.example.com",{127,0,2,3})
  end

  test "rfc7208 appendix A" do
    assert :pass =
             SPF.check("toto@example.com",{200,200,200,200}, spf: "+all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,10}, spf: "a -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,11}, spf: "a -all")
    assert {:fail,_} =
             SPF.check("toto@example.com",{192,0,2,11}, spf: "a:example.org -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,129}, spf: "mx -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,130}, spf: "mx -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,140}, spf: "mx:example.org -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,130}, spf: "mx mx:example.org -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,140}, spf: "mx mx:example.org -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,131}, spf: "mx/30 mx:example.org/30 -all")
    assert {:fail,_} =
             SPF.check("toto@example.com",{192,0,2,132}, spf: "mx/30 mx:example.org/30 -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,143}, spf: "mx/30 mx:example.org/30 -all")
    assert :pass =
             SPF.check("toto@example.com",{192,0,2,65}, spf: "ptr -all")
    assert {:fail,_} =
             SPF.check("toto@example.com",{192,0,2,140}, spf: "ptr -all")
    assert {:fail,_} =
             SPF.check("toto@example.com",{10,0,0,4}, spf: "ptr -all")
    assert {:fail,_} =
             SPF.check("toto@example.com",{192,0,2,65}, spf: "ip4:192.0.2.128/28 -all")
  end
end
