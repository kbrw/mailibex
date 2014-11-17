defmodule DMARCTest do
  use ExUnit.Case

  test "Mixed case." do
    assert  "example.com" = DMARC.organization "example.COM"
    assert  "example.com" = DMARC.organization "WwW.example.COM"
  end

  test "Unlisted TLD." do
    assert  "example.example" = DMARC.organization "example.example"
    assert  "example.example" = DMARC.organization "b.example.example"
    assert  "example.example" = DMARC.organization "a.b.example.example"
  end

  test "TLD with only 1 rule." do
    assert  "domain.biz" = DMARC.organization "domain.biz"
    assert  "domain.biz" = DMARC.organization "b.domain.biz"
    assert  "domain.biz" = DMARC.organization "a.b.domain.biz"
  end

  test "TLD with some 2-level rules." do
    assert  "example.com" = DMARC.organization "example.com"
    assert  "example.com" = DMARC.organization "b.example.com"
    assert  "example.com" = DMARC.organization "a.b.example.com"
    assert  "uk.com" = DMARC.organization "uk.com"
    assert  "example.uk.com" = DMARC.organization "example.uk.com"
    assert  "example.uk.com" = DMARC.organization "b.example.uk.com"
    assert  "example.uk.com" = DMARC.organization "a.b.example.uk.com"
    assert  "test.ac" = DMARC.organization "test.ac"
  end

  test "TLD with only 1 (wildcard) rule." do
    assert  "cy" = DMARC.organization "cy"
    assert  "c.cy" = DMARC.organization "c.cy"
    assert  "b.c.cy" = DMARC.organization "b.c.cy"
    assert  "b.c.cy" = DMARC.organization "a.b.c.cy"
  end

  test "More complex TLD." do
    assert  "jp" = DMARC.organization "jp"
    assert  "test.jp" = DMARC.organization "test.jp"
    assert  "test.jp" = DMARC.organization "www.test.jp"
    assert  "ac.jp" = DMARC.organization "ac.jp"
    assert  "test.ac.jp" = DMARC.organization "test.ac.jp"
    assert  "test.ac.jp" = DMARC.organization "www.test.ac.jp"
    assert  "kyoto.jp" = DMARC.organization "kyoto.jp"
    assert  "test.kyoto.jp" = DMARC.organization "test.kyoto.jp"
    assert  "ide.kyoto.jp" = DMARC.organization "ide.kyoto.jp"
    assert  "b.ide.kyoto.jp" = DMARC.organization "b.ide.kyoto.jp"
    assert  "b.ide.kyoto.jp" = DMARC.organization "a.b.ide.kyoto.jp"
    #assert  "c.kobe.jp" = DMARC.organization "c.kobe.jp"
    assert  "b.c.kobe.jp" = DMARC.organization "b.c.kobe.jp"
    assert  "b.c.kobe.jp" = DMARC.organization "a.b.c.kobe.jp"
    assert  "www.city.kobe.jp" = DMARC.organization "www.city.kobe.jp"
  end

  test "TLD with a wildcard rule and exceptions." do
    assert  "ck" = DMARC.organization "ck"
    assert  "test.ck" = DMARC.organization "test.ck"
    assert  "b.test.ck" = DMARC.organization "b.test.ck"
    assert  "b.test.ck" = DMARC.organization "a.b.test.ck"
    assert  "www.ck" = DMARC.organization "www.ck"
    #assert  "www.ck" = DMARC.organization "www.www.ck"
  end

  test "US K12." do
    assert  "us" = DMARC.organization "us"
    assert  "test.us" = DMARC.organization "test.us"
    assert  "test.us" = DMARC.organization "www.test.us"
    assert  "ak.us" = DMARC.organization "ak.us"
    assert  "test.ak.us" = DMARC.organization "test.ak.us"
    assert  "test.ak.us" = DMARC.organization "www.test.ak.us"
    assert  "k12.ak.us" = DMARC.organization "k12.ak.us"
    assert  "test.k12.ak.us" = DMARC.organization "test.k12.ak.us"
    assert  "test.k12.ak.us" = DMARC.organization "www.test.k12.ak.us"
  end

  test "IDN labels." do
    assert  "食狮.com.cn" = DMARC.organization "食狮.com.cn"
    assert  "食狮.公司.cn" = DMARC.organization "食狮.公司.cn"
    assert  "食狮.公司.cn" = DMARC.organization "www.食狮.公司.cn"
    assert  "shishi.公司.cn" = DMARC.organization "shishi.公司.cn"
    assert  "公司.cn" = DMARC.organization "公司.cn"
    assert  "食狮.中国" = DMARC.organization "食狮.中国"
    assert  "食狮.中国" = DMARC.organization "www.食狮.中国"
    assert  "shishi.中国" = DMARC.organization "shishi.中国"
    assert  "中国" = DMARC.organization "中国"
  end
end
