defmodule MimeTypes do
  :ssl.start ; :inets.start
  {ext2mime,mime2ext} = case :httpc.request('https://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types') do
    {:ok,{{_,200,_},_,r}} -> "#{r}"
    _ -> File.read!("#{:code.priv_dir(:mailibex)}/mime.types")
  end 
  |> String.strip 
  |> String.split("\n")
  |> Enum.filter(&not(Regex.match?(~r"^\s*#",&1))) #remove comments
  |> Enum.reduce({[],[]},fn line,{ext2mime,mime2ext}-> #construct dict and reverse dict ext->mime
       [mime|exts] = line |> String.strip |> String.split(~r/\s+/)
       {Enum.into(for(ext<-exts,do: {ext,mime}),ext2mime),[{mime,hd(exts)}|mime2ext]}
     end)

  def ext2mime(""), do: "text/plain"
  ext2mime |> Enum.uniq_by(&elem(&1,0)) |> Enum.sort_by(& &1 |> elem(0) |> byte_size) |> Enum.reverse |> Enum.each(fn {ext,mime}->
    def ext2mime(unquote("."<>ext)), do: unquote(mime)
  end)
  def ext2mime(_), do: "application/octet-stream"

  Enum.each mime2ext, fn {mime,ext}->
    def mime2ext(unquote(mime)), do: unquote("."<>ext)
  end
  def mime2ext(_), do: ".bin"

  def path2mime(path), do:
    (path |> Path.extname |> String.downcase |> ext2mime)

  def bin2ext(<<0x89,"PNG\r\n",0x1A,"\n",_::binary>>), do: ".png"
  def bin2ext(<<0xFF,0xD8,0xFF,_,_,_,"JFIF\0",_::binary>>), do: ".jpg"
  def bin2ext(<<"GIF8",v,"a",_::binary>>) when v in [?7,?9], do: ".gif"
  def bin2ext(<<"BM",len::size(32)-little,_::binary>>=bin) when byte_size(bin) == len, do: ".bmp"
  def bin2ext("8BPS"<>_), do: ".psd"
  def bin2ext("II*"<>_), do: ".tiff"
  def bin2ext(<<"RIFF",_len::size(32)-little,"AVI ",_::binary>>), do: ".avi"
  def bin2ext(<<"RIFF",_len::size(32)-little,"WAVE",_::binary>>), do: ".wav"
  def bin2ext(<<_::size(32),"ftyp",_::binary>>), do: ".mp4"
  def bin2ext(<<1::size(24),streamid,_::binary>>) when streamid in [0xB3,0xBA], do: ".mpg"
  def bin2ext(<<0b11111111111::size(11),mpeg::size(2),0b01::size(2),_::size(1),_::binary>>) when mpeg in [0b11,0b10], do: ".mp3"
  def bin2ext(<<0b11111111111::size(11),mpeg::size(2),0b10::size(2),_::size(1),_::binary>>) when mpeg in [0b11,0b10], do: ".mp2"
  def bin2ext(<<"MThd",6::size(32),_::binary>>), do: ".mid"
  def bin2ext(<<"OggS",0,2,_::binary>>), do: ".ogg"
  def bin2ext(<<0x3026B2758E66CF11A6D900AA0062CE6C::size(128),_::binary>>), do: ".wmv" #handle ASF only for wmv files (need parsing to find wma)
  def bin2ext("fLaC"<>_), do: ".flac"
  def bin2ext(<<".ra",0xfd,version::size(16),_::binary>>) when version in [3,4,5], do: ".ram"
  def bin2ext(<<".RMF",0,0,0,_::binary>>), do: ".rm"
  def bin2ext(<<0x1A,0x45,0xDF,0xA3,_::binary>>=bin) do #in case of ebml file, parse it to retrieve file type
    case EBML.parse(bin)[:"EBML"].()[:"DocType"].() do
      "matroska"->".mkv"
      "webm"->".webm"
    end
  end
  def bin2ext(<<0x04034b50::size(32)-little,_::binary>>=zip) do
    {:ok,ziph} = :zip.zip_open(zip,[:memory])
    {:ok,files} = :zip.zip_list_dir(ziph)
    files = for {:zip_file,name,_,_,_,_}<-files, do: name
    res = cond do
      Enum.all?(['[Content_Types].xml','word/styles.xml'],&(&1 in files))-> ".docx"
      Enum.all?(['[Content_Types].xml','xl/styles.xml'],&(&1 in files))-> ".xlsx"
      Enum.all?(['[Content_Types].xml','ppt/presProps.xml'],&(&1 in files))-> ".pptx"
      Enum.all?(['content.xml','styles.xml','META-INF/manifest.xml'],&(&1 in files))->
        {:ok,{_,manifest}}=:zip.zip_get('META-INF/manifest.xml',ziph) 
        case Regex.run(~r/media-type="([^"]*)"/,manifest) do #"
          [_,"application/vnd.oasis.opendocument.text"]->".odt"
          [_,"application/vnd.oasis.opendocument.presentation"]->".odp"
          [_,"application/vnd.oasis.opendocument.spreadsheet"]->".ods"
          [_,"application/vnd.oasis.opendocument.graphics"]->".odg"
          [_,"application/vnd.oasis.opendocument.chart"]->".odc"
          [_,"application/vnd.oasis.opendocument.formula"]->".odf"
          [_,"application/vnd.oasis.opendocument.image"]->".odi"
          [_,"application/vnd.oasis.opendocument.base"]->".odb"
          [_,"application/vnd.oasis.opendocument.database"]->".odb"
        end
      'META-INF/MANIFEST.MF' in files->".jar"
      true -> ".zip"
    end
    :zip.zip_close(ziph)
    res
  end
  def bin2ext(<<"Rar!",0x1A,0x07,_::binary>>), do: ".rar"
  def bin2ext(<<_::size(257)-binary,"ustar\000",_::binary>>), do: ".tar"
  def bin2ext(<<31,139,_::binary>>), do: ".gz"
  def bin2ext("BZh"<>_), do: ".bz2"
  def bin2ext(<<"7z",0xBC,0xAF,0x27,0x1C,_::binary>>), do: ".7z"
  def bin2ext("wOFF"<>_), do: ".woff"
  def bin2ext("wOF2"<>_), do: ".woff"
  def bin2ext(<<48,1::size(1)-unit(1),lenlen::size(7),len::size(lenlen)-unit(8),_::size(len)-binary>>), do: ".der"
  def bin2ext(<<48,len,_::size(len)-binary>>), do: ".der"
  def bin2ext("-----BEGIN CERTIFICATE-----"<>_), do: ".crt"
  def bin2ext("-----BEGIN "<>_), do: ".pem"
  def bin2ext(<<0xEF,0xBB,0xBF,rest::binary>>), do: bin2ext(rest)
  def bin2ext(<<0xd0cf11e0a1b11ae1::size(64),_::binary>>), do: ".doc" #compound file is doc (do not handle .xls,.ppt)
  def bin2ext("BEGIN:VCARD\r\nVERSION:"<>_), do: ".vcf"
  def bin2ext(<<"%PDF-",_v1,?.,_v2,_::binary>>), do: ".pdf"
  def bin2ext("{\\rtf"<>_), do: ".rtf"
  def bin2ext("{"<>_), do: ".json"
  def bin2ext("["<>_), do: ".json"
  def bin2ext("#!/"<>_), do: ".sh"
  def bin2ext("<!DOCTYPE html"<>_), do: ".html"
  def bin2ext("<!DOCTYPE HTML"<>_), do: ".html"
  def bin2ext("<!DOCTYPE svg"<>_), do: ".svg"
  def bin2ext("<!DOCTYPE rss"<>_), do: ".rss"
  def bin2ext("<!DOCTYPE "<>_), do: ".xml"
  def bin2ext("<html"<>_), do: ".html"
  def bin2ext("<svg"<>_), do: ".svg"
  def bin2ext("<rss"<>_), do: ".rss"
  def bin2ext(<<"<?xml ",begin::size(200)-binary,_::binary>>) do
    cond do
      String.contains?(begin,"<svg")->".svg"
      String.contains?(begin,"<html")->".html"
      String.contains?(begin,"<rss")->".rss"
      true->".xml"
    end
  end
  def bin2ext(content), do:
    if(String.printable?(content), do: ".txt", else: ".bin")
end

defmodule EBML do
  @moduledoc """
  # Simple  EBML parser in Elixir, 

  Use online specification to get {keyid,keyname,valuetype} for each key, and
  generate functions accordingly.
  Return a list of `{:key,fun}` where `fun.()` decode the value associated with `key`

  Example usage :
  > EBML.parse(File.read!("sample.mkv"))[:"EBML"].()[:"DocType"].()
  "matroska"
  """
  def parse(bin), do: parse(bin,[])
  def parse("",acc), do: Enum.reverse(acc)
  def parse(bin,acc) do
    {class,bin} = case bin do
      <<1::size(1),data::size(7),tail::binary>> -> {<<1::size(1),data::size(7)>>,tail}
      <<1::size(2),data::size(14),tail::binary>>->{<<1::size(2),data::size(14)>>,tail}
      <<1::size(3),data::size(21),tail::binary>>->{<<1::size(3),data::size(21)>>,tail}
      <<1::size(4),data::size(28),tail::binary>>->{<<1::size(4),data::size(28)>>,tail}
    end
    {len,data,bin} = case bin do
      <<1::size(1),len::size(7),data::size(len)-binary,tail::binary>>->{len,data,tail}
      <<1::size(2),len::size(14),data::size(len)-binary,tail::binary>>->{len,data,tail}
      <<1::size(3),len::size(21),data::size(len)-binary,tail::binary>>->{len,data,tail}
      <<1::size(4),len::size(28),data::size(len)-binary,tail::binary>>->{len,data,tail}
      <<1::size(5),len::size(35),data::size(len)-binary,tail::binary>>->{len,data,tail}
      <<1::size(6),len::size(42),data::size(len)-binary,tail::binary>>->{len,data,tail}
      <<1::size(7),len::size(49),data::size(len)-binary,tail::binary>>->{len,data,tail}
      <<1::size(8),len::size(56),data::size(len)-binary,tail::binary>>->{len,data,tail}
    end
    {key,type} = class|>Base.encode16|>key_of
    parse(bin,[{:"#{key}",fn -> convert(type,len,data) end}|acc])
  end

  defp convert(:master,_,bin), do: parse(bin)
  defp convert(:integer,len,bin), do: (<<i::signed-size(len)-unit(8)>>=bin;i)
  defp convert(:uinteger,len,bin), do: (<<i::unsigned-size(len)-unit(8)>>=bin;i)
  defp convert(:float,len,bin), do: (<<f::float-size(len)-unit(8)>>=bin;f)
  defp convert(:string,_,bin), do: String.strip(bin,0)
  defp convert(:"utf-8",_,bin), do: String.strip(bin,0)
  defp convert(:binary,_,bin), do: bin
  defp convert(:date,8,<<since2001::signed-size(8)-unit(8)>>) do
    ts = 978307200 + div(since2001,1_000_000_000)
    :calendar.now_to_datetime {div(ts,1_000_000),rem(ts,1_000_000),0}
  end

  ebml_spec = case :httpc.request('https://raw.githubusercontent.com/Matroska-Org/foundation-source/master/spectool/specdata.xml') do
    {:ok,{{_,200,_},_,r}} -> "#{r}"
    _ -> File.read!("#{:code.priv_dir(:mailibex)}/ebml.xml")
  end 
  Regex.scan(~r/<element [^>]*name="([^"]*)"[^>]* id="0x([^"]*)"[^>]* type="([^"]*)"[^>]*>/,ebml_spec) #"
  |> Enum.each fn [_,key,hexkey,type]->
    def key_of(unquote(hexkey)), do: {unquote(key),unquote(:"#{type}")}
  end
end

