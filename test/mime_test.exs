defmodule MimeMailTest do
  use ExUnit.Case

  @qp_test """
  Hello world,\r
  This line must have trailing spaces encoded,    \t  \r
  you have special characters like € and é...\r
  abéééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé\r
  but also very long long long long long long long long  long long long long long long long long  long long long long long long long long  long long long long long long long long  long long long long long long long long  long long long long long long long long line...\r
  I hope this will be OK...
  """
  test "qp encoding => no line > 76 char && only ascii && no space at end of lines" do
    res = MimeMail.string_to_qp(@qp_test)
    Enum.each String.split(res,"\r\n"), fn line->
      assert false == Regex.match? ~r/[\t ]+$/, line
      assert String.length(line) < 77
      assert [] = Enum.filter('#{line}',&(&1 < 32 or &1 > 127))
    end
  end
  test "round trip quoted-printable" do
    assert @qp_test = (@qp_test |> MimeMail.string_to_qp |> MimeMail.qp_to_binary)
  end

  test "decode qp basic" do
    assert "!" = MimeMail.qp_to_binary("=21")
    assert "!!" = MimeMail.qp_to_binary("=21=21")
    assert "=:=" = MimeMail.qp_to_binary("=3D:=3D")
    assert "€" = MimeMail.qp_to_binary("=E2=82=AC")
    assert "Thequickbrownfoxjumpedoverthelazydog." = MimeMail.qp_to_binary("Thequickbrownfoxjumpedoverthelazydog.")
  end

  test "decode qp lowercase" do
    assert "=:=" = MimeMail.qp_to_binary("=3d:=3d")
  end

  test "decode qp with spaces" do
    assert "The quick brown fox jumped over the lazy dog." = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.")
  end

  test "decode qp with tabs" do
    assert "The\tquick brown fox jumped over\tthe lazy dog." = MimeMail.qp_to_binary("The\tquick brown fox jumped over\tthe lazy dog.")
  end

  test "decode qp with trailing spaces" do
    assert "The quick brown fox jumped over the lazy dog." = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.       ")
  end

  test "decode qp with non-strippable trailing whitespace" do
    assert "The quick brown fox jumped over the lazy dog.        " = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.       =20")
    assert "The quick brown fox jumped over the lazy dog.       \t" = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.       =09")
    assert "The quick brown fox jumped over the lazy dog.\t \t \t \t " = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.\t \t \t =09=20")
    assert "The quick brown fox jumped over the lazy dog.\t \t \t \t " = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.\t \t \t =09=20\t                  \t")
  end

  test "decode qp with trailing tabs" do
    assert "The quick brown fox jumped over the lazy dog." = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.\t\t\t\t\t")
  end

  test "decode qp with soft new line" do
    assert "The quick brown fox jumped over the lazy dog.       " = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.       =")
  end
  test "decode qp soft new line with trailing whitespace" do
    assert "The quick brown fox jumped over the lazy dog.       " = MimeMail.qp_to_binary("The quick brown fox jumped over the lazy dog.       =  	")
  end
  test "decode qp multiline stuff" do
    assert "Now's the time for all folk to come to the aid of their country." = MimeMail.qp_to_binary("Now's the time =\r\nfor all folk to come=\r\n to the aid of their country.")
    assert "Now's the time\r\nfor all folk to come\r\n to the aid of their country." = MimeMail.qp_to_binary("Now's the time\r\nfor all folk to come\r\n to the aid of their country.")
    assert "hello world" = MimeMail.qp_to_binary("hello world")
    assert "hello\r\n\r\nworld" = MimeMail.qp_to_binary("hello\r\n\r\nworld")
  end
  test "decode qp invalid input" do
    assert_raise(ArgumentError, fn->MimeMail.qp_to_binary("=21=G1") end)
    assert_raise(ArgumentError, fn->MimeMail.qp_to_binary("=21=D1 = g ") end)
  end

  @header "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce at ultrices augue, et vulputate dui. Nullam quis magna quam. Donec venenatis lobortis viverra. Donec at tincidunt urna. Cras et tortor porta mauris cursus dictum. Morbi tempor venenatis tortor eget scelerisque."
  test "fold header create lines < 76 char" do
    Enum.each String.split(MimeMail.fold_header(@header),"\r\n"), fn line->
      assert String.length(line) < 77
    end
  end

  test "roundtrip body encoding decoding" do
    decoded = File.read!("test/mails/encoded.eml")
    |> MimeMail.from_string
    |> MimeMail.decode_headers([DKIM,MimeMail.Emails,MimeMail.Words,MimeMail.CTParams])
    |> MimeMail.decode_body
    roundtrip = decoded
    |> MimeMail.to_string
    |> MimeMail.from_string
    |> MimeMail.decode_body
    assert String.rstrip(decoded.body) == String.rstrip(roundtrip.body)
  end

  test "email bodies with wrong encoding must be converted to printable utf8" do
    decoded = File.read!("test/mails/free.eml")
    |> MimeMail.from_string
    |> MimeMail.decode_headers([DKIM,MimeMail.Emails,MimeMail.Words,MimeMail.CTParams])
    |> MimeMail.decode_body
    for child<-decoded.body, match?({"text/"<>_,_},child.headers[:'content-type']) do
      assert String.printable?(child.body)
    end
  end

  test "multipart tree decoding [txt,[html,png]]" do
    # 137 80 78 71 13 10 26 10 are png signature bytes
    decoded = File.read!("test/mails/free.eml")
    |> MimeMail.from_string
    |> MimeMail.decode_body
    assert [%{body: _txt},
            %{body: [
               %{body: "<html"<>_},
               %{body: <<137,80,78,71,13,10,26,10,_::binary>>}
             ]}] = decoded.body
  end
end
