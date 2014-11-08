:code.unstick_dir(:code.lib_dir(:kernel)++'/ebin')
defmodule :inet_res do #mock external dns calls to hard define DKIM pub key when mock mails were constructed
  def lookup('20120113._domainkey.gmail.com',:in,:txt) do
    [['k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1Kd87/UeJjenpabgbFwh+eBCsSTrqmwIYYvywlbhbqoo2DymndFkbjOVIPIldNs/m40KF+yzMn1skyoxcTUGCQs8g3FgD2Ap3ZB5DekAo5wMmk4wimDO+U8QzI3SD0', '7y2+07wlNWwIt8svnxgdxGkVbbhzY8i+RQ9DpSVpPbF7ykQxtKXkv/ahW3KjViiAH+ghvvIhkx4xYSIc9oSwVmAl5OctMEeWUwg8Istjqz8BZeTWbf41fbNhte7Y+YqZOwq1Sd0DbvYAD9NOZK9vlfuac0598HY+vtSBczUiKERHv1yRbcaQtZFh5wtiRrN04BLUTD21MycBX5jYchHjPY/wIDAQAB']]
  end
  def lookup('cobrason._domainkey.order.brendy.fr',:in,:txt) do
    [['k=rsa; t=y; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAofRImu739BK3m4Qj6uxZr/IBb2Jk5xuxY17pBgRp1ANAPFqJBg1mgUiwooT5n6/EjSA3dvt8MarlGNl+fOOOY02IWttkXW0fXWxW324iNaNE1aSyhHaP7dTmcSE3BnVjOVUGbZ5voLxjULq5+Ml1sy5Xt17cW38I0gja4ZtC0HQ9aUv4+eWZwxv4WIWpPUVH', 'qEFEptOHc1v1YbKO8lo9JFlO1wVvnQjEpWbg5ORGxaBnr92I0bZ2Hm5gU4WHOUiPKKk7J94wpO1KV++SGLaCeHDV8cW9e3RgGJs2IQzpjMDTyGEyHTo5WrgN3d9AOljyb2GOCnFEZ3lqI/+4XXbyHQIDAQAB']]
  end
  def lookup(_,_,_), do: []
end
defmodule DKIMTest do
  use ExUnit.Case

  def check(file) do
    file |> File.read! |> MimeMail.from_string |> DKIM.check
  end

  test "DKIM relaxed/relaxed check" do # test cases from mail sended by gmail
    assert {:ok,_} = check("test/mails/valid_dkim_relaxed_canon.mail")
    assert {:ok,_} = check("test/mails/valid_dkim_relaxed_uncanon.mail")
    assert {:error,:body_hash_no_match} = check("test/mails/invalid_dkim_bodyh.mail")
    assert {:error,{:unavailable_pubkey,_}} = check("test/mails/invalid_dkim_dns.mail")
    assert {:error,:sig_not_match} = check("test/mails/invalid_dkim_sig.mail")
  end
  test "DKIM relaxed/simple check" do # test cases from mail sended by gen_smtp_client
    assert {:ok,_} = check("test/mails/valid_dkim_relaxedsimple_canon.mail")
    assert {:ok,_} = check("test/mails/valid_dkim_relaxedsimple_uncanon.mail")
    assert {:error,:body_hash_no_match} = check("test/mails/invalid_dkim_relaxedsimple_uncanon.mail")
  end
  test "DKIM simple/simple check" do # test cases from mail sended by gen_smtp_client
    assert {:ok,_} = check("test/mails/valid_dkim_simple_canon.mail")
    assert {:error,:sig_not_match} = check("test/mails/invalid_dkim_simple_uncanon.mail")
  end

  test "DKIM signature round trip" do
    [rsaentry] =  :public_key.pem_decode(File.read!("test/mails/key.pem"))
    assert {:ok,_} = 
      File.read!("test/mails/valid_dkim_relaxed_canon.mail")
      |> MimeMail.from_string
      |> DKIM.sign(:public_key.pem_entry_decode(rsaentry), d: "order.brendy.fr", s: "cobrason")
      |> MimeMail.to_string
      |> MimeMail.from_string
      |> DKIM.check
  end
end
