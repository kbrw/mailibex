mailibex
========

Library containing Email related implementations in Elixir : dkim, spf, dmark, mimemail, smtp

## MimeMail ##

Use `MimeMail.from_string` to split email headers and body, this function keep
the raw representation of headers and body in a `{:raw,value}` term.

Need more explanations about pluggable header Codec...

`MimeMail.to_string` encode headers and body into the final ascii mail.

## DKIM ##

```elixir
[rsaentry] =  :public_key.pem_decode(File.read!("test/mails/key.pem"))
mail
|> MimeMail.from_string
|> DKIM.sign(:public_key.pem_entry_decode(rsaentry), d: "order.brendy.fr", s: "cobrason")
```

Need more explanations here...

## Current Status

- DKIM is fully implemented (signature/check), missing DKIM-Quoted-Printable token management
- mimemail encoding/decoding of headers and body are fully implemented, missing tests

## TODO :

- flat mime body representation for easy body creation / modification

## TODO later :

- SPF check
- DMARK check
- gen_smtp style interface over Ranch

