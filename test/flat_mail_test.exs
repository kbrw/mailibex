defmodule FlatMailTest do
  use ExUnit.Case

  test "unflat mail with attachments only" do
    mail = MimeMail.Flat.to_mail txt: "coucou arnaud", attach: "du texte attaché", attach: File.read!("test/mimes/sample.7z")
    assert {"multipart/mixed",_} = mail.headers[:'content-type']
    [text,text_attached,archive] = mail.body
    assert {"text/plain",%{}} = text.headers[:'content-type']
    assert {"text/plain",%{name: ct_txt_name}} = text_attached.headers[:'content-type']
    assert {"application/x-7z-compressed",%{name: ct_7z_name}} = archive.headers[:'content-type']
    assert nil == text.headers[:'content-disposition']
    assert {"attachment",%{filename: cd_txt_name}} = text_attached.headers[:'content-disposition']
    assert {"attachment",%{filename: cd_7z_name}} = archive.headers[:'content-disposition']
    assert String.contains?(ct_txt_name,".txt")
    assert String.contains?(cd_txt_name,".txt")
    assert String.contains?(ct_7z_name,".7z")
    assert String.contains?(cd_7z_name,".7z")
  end

  test "flat mail mixed(alternative(txt,html))" do
    flat = File.read!("test/mails/amazon.eml")
    |> MimeMail.from_string
    |> MimeMail.Flat.from_mail
    assert [{:txt, txt},{:html, html}|_headers] = flat
    assert is_binary(txt)
    assert is_binary(html)
  end

  test "flat mail alternative(txt,related(html,img))" do
    flat = File.read!("test/mails/free.eml")
    |> MimeMail.from_string
    |> MimeMail.Flat.from_mail
    assert [{:txt, txt},{:html, html},{:include,{"imglogo","image/png",png}}|_headers] = flat
    assert ".txt" = MimeTypes.bin2ext(txt)
    assert ".html" = MimeTypes.bin2ext(html)
    assert ".png" = MimeTypes.bin2ext(png)
    flat = flat
    |> MimeMail.Flat.to_mail
    |> MimeMail.to_string
    |> MimeMail.from_string
    |> MimeMail.Flat.from_mail
    assert [{:txt, txt},{:html, html},{:include,{"imglogo","image/png",png}}|_headers] = flat
    assert ".txt" = MimeTypes.bin2ext(txt)
    assert ".html" = MimeTypes.bin2ext(html)
    assert ".png" = MimeTypes.bin2ext(png)
  end
end
