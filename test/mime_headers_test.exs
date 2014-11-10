defmodule MimeHeadersTest do
  use ExUnit.Case

  test "decoded params with quoted string" do
    assert %{withoutquote: "with no quote",
             withquote: " with; some \"quotes\" "}
           = MimeMail.Params.parse_header("   withoutquote =  with no quote  ; WithQuote =\" with; some \\\"quotes\\\" \"")
  end

  test "encode str into an encoded-word" do
    assert "=?UTF-8?Q?J=C3=A9r=C3=B4me_Nicolle?="
           = MimeMail.Words.word_encode("Jérôme Nicolle")
  end

  test "decode addresses headers" do
    mail = File.read!("test/mails/encoded.eml") 
    |> MimeMail.from_string
    |> MimeMail.Emails.decode_headers
    assert [%MimeMail.Address{name: "Jérôme Nicolle", address: "jerome@ceriz.fr"}]
           = mail.headers[:from]
    assert [%MimeMail.Address{address: "frnog@frnog.org"}]
           = mail.headers[:to]
  end

  test "encode addresses headers" do
    mail=%MimeMail{headers: [
      to: [%MimeMail.Address{address: "frnog@frnog.org"},
           %MimeMail.Address{name: "Jérôme Nicolle", address: "jerome@ceriz.fr"}],
      from: %MimeMail.Address{address: "frnog@frnog.org"}
    ]}
    headers = MimeMail.encode_headers(mail).headers
    assert "frnog@frnog.org, =?UTF-8?Q?J=C3=A9r=C3=B4me_Nicolle?= <jerome@ceriz.fr>"
           = (headers[:to] |> MimeMail.header_value |> String.replace(~r/\s+/," "))
    assert "frnog@frnog.org" = MimeMail.header_value(headers[:from])
  end
  
  test "round trip encoded-words" do
    assert "Jérôme Nicolle gave me €"
           = ("Jérôme Nicolle gave me €" |> MimeMail.Words.word_encode |> MimeMail.Words.word_decode)
  end

  test "decode str from base 64 encoded-word" do
    assert "Jérôme Nicolle"
           = MimeMail.Words.word_decode("=?UTF-8?B?SsOpcsO0bWUgTmljb2xsZQ==?=")
  end

  test "decode str from q-encoded-word" do
    assert "[FRnOG] [TECH] ToS implémentée chez certains transitaires" 
           = MimeMail.Words.word_decode("[FRnOG] =?UTF-8?Q?=5BTECH=5D_ToS_impl=C3=A9ment=C3=A9e_chez_certa?=\r\n =?UTF-8?Q?ins_transitaires?=")
  end

  test "encode str into multiple encoded-word, test line length and round trip" do
    to_enc = "Jérôme Nicolle, hello, you are really nice to be here,  \
              please talk to me, please stop my subject becomes too long, pleeeeeease    !! , \
              please stop my subject becomes too long, pleeeeeease    !! , \
              please stop my subject becomes too long, pleeeeeease    !!"
    Enum.each String.split(to_enc,"\r\n"), fn line->
      assert String.length(line) > 78
    end
    enc = MimeMail.Words.word_encode(to_enc)
    Enum.each String.split(enc,"\r\n"), fn line->
      assert String.length(line) < 78
    end
    assert ^to_enc = MimeMail.Words.word_decode(enc)
  end
end
