defmodule MimeMail.Flat do
  def to_mail(headers_flat_body) do
    {flat_body,headers} = Enum.partition(headers_flat_body,fn {k,_}->k in [:txt,:html,:attach,:include,:attach_in] end)
    htmlcontent =  mail_htmlcontent(flat_body[:html],for({:include,v}<-flat_body,do: expand_attached(v)))
    plaincontent = mail_plaincontent(flat_body[:txt])
    content = mail_content(htmlcontent,plaincontent)
    %{headers: bodyheaders, body: body} = mail_final(content,for({:attach,v}<-flat_body,do: expand_attached(v)),
                                                             for({:attach_in,v}<-flat_body,do: expand_attached(v)))
    %MimeMail{headers: headers++bodyheaders, body: body}
  end

  def from_mail(%MimeMail{}=mail) do
    mail
    |> MimeMail.decode_body
    |> find_bodies
    |> Enum.concat(mail.headers)
    |> Enum.filter(fn {k,_}->not k in [:inline,:'content-type',:'content-disposition',:'content-transfer-encoding',:'content-id'] end)
  end

  def update_mail(%MimeMail{}=mail,updatefn) do
    mail |> from_mail |> updatefn.() |> to_mail
  end

  defp expand_attached({_id,_ct,_body}=attached), do: 
    attached
  defp expand_attached({id,body}), do: 
    {id,MimeTypes.path2mime(id),body}
  defp expand_attached(body) when is_binary(body), do: 
    expand_attached({gen_id(MimeTypes.bin2ext(body)),body})

  def find_bodies(childs) when is_list(childs), do:
    List.flatten(for(child<-childs, do: find_bodies(child)))
  def find_bodies(%MimeMail{headers: headers, body: body}) do
    find_bodies(headers[:'content-type'],headers[:'content-disposition'],headers[:'content-id'],body)
  end

  def find_bodies({"multipart/mixed",_},_,_,childs) do
    find_bodies(childs) |> Enum.map(fn
      {:inline,{_,_,_}=child}->{:attach_in,child}
      {_,{_,_,_}=child}->{:attach,child}
      txt_or_html->txt_or_html
    end)
  end
  def find_bodies({"multipart/related",_},_,_,childs) do
    find_bodies(childs) |> Enum.map(fn
      {_,{_,_,_}=child}->{:include,child}
      other->other
    end)
  end
  def find_bodies({"multipart/alternative",_},_,_,childs) do
    find_bodies(childs)
  end
  # default content type is content/plain : 
  def find_bodies(nil,cd,id,body), do: 
    find_bodies({"content/plain",%{}},cd,id,body)
  # cases where html and txt are not attachements
  def find_bodies({"text/html",_},{"inline",_},_,body), do:
    [html: body]
  def find_bodies({"text/html",_},nil,_,body), do:
    [html: body]
  def find_bodies({"text/plain",_},{"inline",_},_,body), do:
    [txt: body]
  def find_bodies({"text/plain",_},nil,_,body), do:
    [txt: body]
  # default disposition is attachments, default id is name or guess from mime
  def find_bodies(ct,nil,id,body), do: 
    find_bodies(ct,{"attachment",%{}},id,body)
  def find_bodies({mime,ctparams}=ct,{_,cdparams}=cd,nil,body), do: 
    find_bodies(ct,cd,{"<#{ctparams[:name]||cdparams[:filename]||gen_id(MimeTypes.mime2ext(mime))}>",%{}},body)
  def find_bodies({mime,_},{"inline",_},{id,_},body), do:
    [inline: {(id |> String.rstrip(?>) |> String.lstrip(?<)),mime,body}]
  def find_bodies({mime,_},{"attachment",_},{id,_},body), do:
    [attach: {(id |> String.rstrip(?>) |> String.lstrip(?<)),mime,body}]

  def gen_id(ext), do:
    "#{Base.encode16(:crypto.rand_bytes(16), case: :lower)}#{ext}"

  defp mail_htmlcontent(nil,_), do: nil
  defp mail_htmlcontent(body,[]), do:
    %MimeMail{headers: ['content-type': {"text/html",%{}}], body: body}
  defp mail_htmlcontent(body,included), do:
    %MimeMail{
      headers: ['content-type': {"multipart/related",%{}}],
      body: [mail_htmlcontent(body,[]) | for {id,contenttype,binary}<-included do
        %MimeMail{
          headers: ['content-type': {contenttype,%{name: id}},
                    'content-disposition': {"inline",%{filename: id}},
                    'content-id': {"<#{id}>",%{}}],
          body: binary
        }
      end]
    }

  defp mail_plaincontent(nil), do: nil
  defp mail_plaincontent(body), do:
    %MimeMail{headers: ['content-type': {"text/plain",%{}}], body: body}

  defp mail_content(nil,nil), do: mail_plaincontent(" ")
  defp mail_content(htmlcontent,nil), do: htmlcontent
  defp mail_content(nil,plaincontent), do: plaincontent
  defp mail_content(htmlcontent,plaincontent), do:
    %MimeMail{
      headers: ['content-type': {"multipart/alternative",%{}}], 
      body: [plaincontent,htmlcontent] 
    }

  defp mail_final(content,[],[]), do: content
  defp mail_final(content,attached,attached_in), do:
    %MimeMail{
      headers: ['content-type': {"multipart/mixed",%{}}], 
      body: [content | 
        for {name,contenttype,binary}<-attached do
          %MimeMail{
            headers: ['content-type': {contenttype,%{name: name}},
                      'content-disposition': {"attachment",%{filename: name}}], 
            body: binary
          }
        end ++
        for {name,contenttype,binary}<-attached_in do
          %MimeMail{
            headers: ['content-type': {contenttype,%{name: name}},
                      'content-disposition': {"inline",%{filename: name}}],
            body: binary
          }
        end
      ] 
    }
end
