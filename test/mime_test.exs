
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
      assert false = Regex.match? ~r/[\t ]+$/, line
      assert String.length(line) < 77
      assert [] = Enum.filter('#{line}',&(&1 < 32 or &1 > 127))
    end
  end
  test "round trip quoted-printable" do
    assert @qp_test = (@qp_test |> MimeMail.string_to_qp |> MimeMail.qp_to_string)
  end

  test "decode qp basic" do
    assert "!" = MimeMail.qp_to_string("=21")
    assert "!!" = MimeMail.qp_to_string("=21=21")
    assert "=:=" = MimeMail.qp_to_string("=3D:=3D")
    assert "€" = MimeMail.qp_to_string("=E2=82=AC")
    assert "Thequickbrownfoxjumpedoverthelazydog." = MimeMail.qp_to_string("Thequickbrownfoxjumpedoverthelazydog.")
  end

  test "decode qp lowercase" do
    assert "=:=" = MimeMail.qp_to_string("=3d:=3d")
  end

  test "decode qp with spaces" do
    assert "The quick brown fox jumped over the lazy dog." = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.")
  end

  test "decode qp with tabs" do
    assert "The\tquick brown fox jumped over\tthe lazy dog." = MimeMail.qp_to_string("The\tquick brown fox jumped over\tthe lazy dog.")
  end

  test "decode qp with trailing spaces" do
    assert "The quick brown fox jumped over the lazy dog." = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.       ")
  end

  test "decode qp with non-strippable trailing whitespace" do
    assert "The quick brown fox jumped over the lazy dog.        " = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.       =20")
    assert "The quick brown fox jumped over the lazy dog.       \t" = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.       =09")
    assert "The quick brown fox jumped over the lazy dog.\t \t \t \t " = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.\t \t \t =09=20")
    assert "The quick brown fox jumped over the lazy dog.\t \t \t \t " = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.\t \t \t =09=20\t                  \t")
  end

  test "decode qp with trailing tabs" do
    assert "The quick brown fox jumped over the lazy dog." = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.\t\t\t\t\t")
  end

  test "decode qp with soft new line" do
    assert "The quick brown fox jumped over the lazy dog.       " = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.       =")
  end
  test "decode qp soft new line with trailing whitespace" do
    assert "The quick brown fox jumped over the lazy dog.       " = MimeMail.qp_to_string("The quick brown fox jumped over the lazy dog.       =  	")
  end
  test "decode qp multiline stuff" do
    assert "Now's the time for all folk to come to the aid of their country." = MimeMail.qp_to_string("Now's the time =\r\nfor all folk to come=\r\n to the aid of their country.")
    assert "Now's the time\r\nfor all folk to come\r\n to the aid of their country." = MimeMail.qp_to_string("Now's the time\r\nfor all folk to come\r\n to the aid of their country.")
    assert "hello world" = MimeMail.qp_to_string("hello world")
    assert "hello\r\n\r\nworld" = MimeMail.qp_to_string("hello\r\n\r\nworld")
  end
  test "decode qp invalid input" do
    assert_raise(ArgumentError, fn->MimeMail.qp_to_string("=21=G1") end)
    assert_raise(ArgumentError, fn->MimeMail.qp_to_string("=21=D1 = g ") end)
  end

  @header "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce at ultrices augue, et vulputate dui. Nullam quis magna quam. Donec venenatis lobortis viverra. Donec at tincidunt urna. Cras et tortor porta mauris cursus dictum. Morbi tempor venenatis tortor eget scelerisque."
  test "fold header create lines < 76 char" do
    Enum.each String.split(MimeMail.fold_header(@header),"\r\n"), fn line->
      assert String.length(line) < 77
    end
  end
end
