defmodule MailibexTest do
  use ExUnit.Case

  test "DKIM relaxed/relaxed check" do # test cases from mail sended by gmail
    assert {:ok,_} = DKIM.check(File.read!("test/mails/valid_dkim_relaxed_canon.mail"))
    assert {:ok,_} = DKIM.check(File.read!("test/mails/valid_dkim_relaxed_uncanon.mail"))
    assert {:error,:body_hash_no_match} = DKIM.check(File.read!("test/mails/invalid_dkim_bodyh.mail"))
    assert {:error,"DKIM key unavailable"<>_} = DKIM.check(File.read!("test/mails/invalid_dkim_dns.mail"))
    assert {:error,:sig_not_match} = DKIM.check(File.read!("test/mails/invalid_dkim_sig.mail"))
  end
end
