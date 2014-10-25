defmodule SPF do
  def check(mail) do
      #{headers,body}=split_body(mail)
      #headers = parse_headers(headers)
  end
end
