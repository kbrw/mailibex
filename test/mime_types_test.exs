defmodule MimeTypesTest do
  use ExUnit.Case

  test "some extensions are OK" do
    assert "image/png" = MimeTypes.path2mime("toto/tata.png")
    assert "image/jpeg" = MimeTypes.path2mime("toto/tata.jpg")
    assert ".mpeg" = MimeTypes.mime2ext("video/mpeg")
  end

  test "default extensions" do
    assert "application/octet-stream" = MimeTypes.path2mime("toto/tata.toto")
    assert "text/plain" = MimeTypes.path2mime("toto/tata")
  end

  test "guess extensions from binaries" do
    for f<-Path.wildcard("test/mimes/*") do
      assert Path.extname(f) == MimeTypes.bin2ext(File.read!(f))
    end
  end
end
