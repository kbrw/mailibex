mailibex
========

Library containing Email related implementations in Elixir : dkim, spf, dmark, mimemail, smtp

## MimeMail ##

Use `MimeMail.from_string` to split email headers and body, this function keep
the raw representation of headers and body in a `{:raw,value}` term.

Need more explanations about pluggable header Codec...

`MimeMail.to_string` encode headers and body into the final ascii mail.

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

## DKIM ##

```elixir
[rsaentry] =  :public_key.pem_decode(File.read!("test/mails/key.pem"))
mail = MimeMail.from_string(data)

mail = DKIM.sign(mail,:public_key.pem_entry_decode(rsaentry), d: "order.brendy.fr", s: "cobrason")
case DKIM.check(mail) do
  :none      ->IO.puts("no dkim signature")
  :pass      ->IO.puts("the mail is signed by #{mail[:'dkim-signature'].s} at #{mail[:'dkim-signature'].d}")
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

