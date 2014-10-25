defmodule Mailibex do
  @derive [Access]
  defstruct headers: %{}, raw: "", v: []
  def decode(mail) do
    {headers,body}=split_body(mail)
    %Mailibex{headers: parse_headers(headers), raw: body, v: []}
  end

  def with(mail,parser), do: 
    with(mail,parser,true)
  def with(mail,parsers,recursive) when is_list(parsers), do:
    Enum.reduce(parsers,mail,&(with(&2,&1,recursive)))
  def with(mail,parser,recursive) when is_atom(parser) do
    if function_exported?(parser,:parse,2), do:
      parser.parse(mail,recursive), else: mail
  end

  def split_body(data), do: 
    (data |> String.split("\r\n\r\n",parts: 2) |> List.to_tuple)

  def parse_params(data) do
    params=data
    |> String.split(~r"\s*;\s*",trim: true)
    |> Enum.map(&String.split(&1,"=",parts: 2))
    Enum.into(for([k,v]<-params, do: {:"#{k}",v}), %{})
  end
  def parse_headers(data) do
    headers=data
    |> String.replace(~r/\r\n([^\t ])/,"\r\n!\\1")
    |> String.split("\r\n!")
    |> Enum.map(&{String.split(&1,~r/\s*:/,parts: 2),&1})
    for {[k,_],v}<-headers, do: {:"#{String.downcase(k)}", %{raw: v, v: nil}}
  end

  def unfold(value), do: 
    String.replace(value,~r/\r\n([\t ])/,"\\1")
end
