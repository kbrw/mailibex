mailibex
========

Library containing Email related implementations in Elixir : dkim, spf, dmark, mimemail, smtp

## MimeMail ##

```elixir
%MimeMail{headers: [{key::atom, {:raw,binary} | MimeMail.Header.t}], body: binary | [MimeMail.t] | {:raw,binary}}
# headers contains a keywordlist of either the raw form of the header, 
# or an encodable version of the header (a term with a module implementing MimeMail.Header.to_ascii)
# body contains either the raw binary body, the decoded body as a binary (using content-transfer-encoding), 
# or a list of MimeMail struct to encode in case of a multipart
# If body is a text, then the decoded body binary will be the UTF8 version of the text converted from the source charset
```

- `MimeMail.from_string` parse the mimemail binary into a `MimeMail` struct explained above, with all the headers and body in their encoded form ('{:raw,binary}`)
- `MimeMail.encode_headers(mail)` apply the `MimeMail.Header.to_ascii` to every header to convert them into a `{:raw,binary}` form.
- `MimeMail.decode_headers(mail,[Mod1,Mod2])` applies successively `Mod1.decode_headers(mail)` the `Mod2.decode_headers(mail)` to the result.
- `MimeMail.encode_body(mail)` encodes the mail body from a decoded form (`binary | [MimeMail]`) into a `{:raw,binary}`form
- `MimeMail.decode_body(mail)` does the opposite.
- `MimeMail.to_string(mail)` encode headers and body of a `MimeMail` into an ascii mail binary.

Currently, the library contains three types of acceptable header value (implementing `MimeMail.Header`) :
- `binary` : simple binary headers are utf8 strings converted into encoded words
- `{value,%{}=params}` are only acceptable tuple as header, converted into a 'content-*' style header ( `value; param1=value1, param2=value2`)
- `[%MimeMail.Address{name="toto", address: "toto@example.org"}]` : lists are encoded into mailbox list header
- `%DKIM{}` : Converted into a dkim header

So for instance : 
```elixir
%MimeMail{headers: [
    to: [%MimeMail.Address{name="You",address: "you@m.org"}],
    from: [%MimeMail.Address{name="Me",address: "me@m.org"}],
    cc: "me@m.org", # only ascii so ok to encode it as a simple encoded word
    'content-type': {'text/plain',%{charset: "utf8"}},
  ],
  body: "Hello world"}
|> MimeMail.to_string
```

## FlatMail ##

Flat mail representation of MimeMail is simply a `KeywordList` where
all the keys `[:txt,:html,:attach,:attach_in,:include]` are used to construct the body tree of 
alternative/mixed/related multiparts in the `body` field of the
`MimeMail` struct, and the rest of the `KeywordList` became the
`header` field.

```elixir
MimeMail.Flat.to_mail(from: "me@example.org", txt: "Hello world", attach: "attached plain text", attach: File.read!("attachedfile"))
|> MimeMail.to_string
```

Need more explanations here...

## MimeTypes ##

`ext2mime` and `mime2ext` are functions generated at compilation time from the apache mime configuration file https://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types .

```elixir
"image/png" = MimeTypes.ext2mime(".png")
".png" = MimeTypes.mime2ext("image/png")
```

`bin2ext` matches the begining of the binary and sometimes decode the binary in order to determine the file extension (then we can use `ext2mime`to find the mime type if needed.

```elixir
".webm" = MimeTypes.bin2ext(File.read!("path/to/my/webm/file.webm"))
```

## DKIM ##

```elixir
[rsaentry] =  :public_key.pem_decode(File.read!("test/mails/key.pem"))
mail = MimeMail.from_string(data)

mail = DKIM.sign(mail,:public_key.pem_entry_decode(rsaentry), d: "order.brendy.fr", s: "cobrason")
case DKIM.check(mail) do
  :none      ->IO.puts("no dkim signature")
  {:pass,{key,org}}      ->IO.puts("the mail is signed by #{key} at #{org}")
  :tempfail  -> IO.puts("the dns record is unavailable, try later")
  {:permfail,msg}->IO.puts("the sender is not authorized because #{msg}")
end
```

Need more explanations here...

## DMARC ##

Organizational Domain implementation using public suffix database : 
(https://publicsuffix.org/list/effective_tld_names.dat)

```elixir
"orga2.gouv.fr" = DMARK.organization "orga0.orga1.orga2.gouv.fr"
```

## SPF ##

Full implementation of the Sender Policy Framework (https://tools.ietf.org/html/rfc7208).

```elixir
case SPF.check("me@example.org",{1,2,3,4}, helo: "relay.com", server_domain: "me.com") do
  :none      ->IO.puts("no SPF information")
  :neutral   ->IO.puts("nor authorized neither not authorized")
  :pass      ->IO.puts("the sender is authorized")
  {:fail,msg}->IO.puts("the sender is not authorized because #{msg}")
  :softfail  ->IO.puts("not authorized but don't be rude")
  :temperror ->IO.puts("temporary error, try again latter")
  :permerror ->IO.puts("spf error, ask to remote admin")
end
```

## Current Status

- DKIM is fully implemented (signature/check), missing DKIM-Quoted-Printable token management
- mimemail encoding/decoding of headers and body are fully implemented
- flat mime body representation for easy mail creation / modification
- DMARC implementation of organizational domains
- SPF is fully implemented

## TODO :

- DMARC report
- smtp client implementation
- smtp server implementation over Ranch

