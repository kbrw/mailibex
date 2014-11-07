#include <iconv.h>
#include <string.h>
#include <errno.h>
#include <erl_nif.h>

#include <stdio.h>

#define CONV_DESC_LEN 80

static ERL_NIF_TERM _atom_ok;
static ERL_NIF_TERM _atom_error;
static ERL_NIF_TERM _atom_enomem;
static ERL_NIF_TERM _atom_eilseq;
static ERL_NIF_TERM _atom_eunknown;
static ERL_NIF_TERM _atom_badcharset;

static ERL_NIF_TERM eiconv_make_error(ErlNifEnv* env, int error_number) {
    ERL_NIF_TERM error;
    if(error_number == EILSEQ) {
        error = _atom_eilseq;
    } else if (error_number == EINVAL) {
        error = _atom_badcharset;
    } else {
        error = _atom_eunknown;
    }
    return enif_make_tuple2(env, _atom_error, error);
}

static ERL_NIF_TERM eiconv_conv_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) 
{
  char tocode[CONV_DESC_LEN], fromcode[CONV_DESC_LEN];
  ErlNifBinary tocode_bin, fromcode_bin, inbuf, outbuf;
  unsigned char *in, *out;
  size_t inbytesleft, outbytesleft, outbufsize, rc;
  iconv_t cd;
  
  // retrieve erlang function parameters
  if (!enif_inspect_iolist_as_binary(env, argv[0], &inbuf))
    return enif_make_badarg(env);
  if (!enif_inspect_iolist_as_binary(env, argv[1], &fromcode_bin))
    return enif_make_badarg(env);
  if (!enif_inspect_iolist_as_binary(env, argv[2], &tocode_bin))
    return enif_make_badarg(env);

  // guard against buffer overflow
  if (tocode_bin.size >= CONV_DESC_LEN-1)
    return enif_make_badarg(env);
  if (fromcode_bin.size >= CONV_DESC_LEN-1)
    return enif_make_badarg(env);

  // convert erlang encoding_desc into iconv compatible c string
  memcpy((void*) tocode, tocode_bin.data, tocode_bin.size);
  tocode[tocode_bin.size] = '\0';
  memcpy((void *) fromcode, fromcode_bin.data, fromcode_bin.size);
  fromcode[fromcode_bin.size] = '\0';

  // convert erlang input binary to iconv compatible pointers
  in = inbuf.data;

  // calculate output buffer size, conv_encoding == +50% max
  inbytesleft = inbuf.size;
  outbufsize = inbytesleft + (inbytesleft/2); 
  outbytesleft = outbufsize;

  // prepare output binary buffer
  if(!enif_alloc_binary(outbufsize, &outbuf)) 
    return enif_make_tuple2(env, _atom_error, _atom_enomem);
  out = outbuf.data;

  cd = iconv_open(tocode, fromcode); // alloc iconv
  if((iconv_t)(-1) == cd) return eiconv_make_error(env, EINVAL);
  iconv(cd, NULL, NULL, NULL, NULL); // init iconv
  do {
    rc = iconv(cd, (char **) &in, &inbytesleft, (char **) &out, &outbytesleft);
    if(rc == 0) break;

    if (errno == E2BIG) { // output buffer not large enough, realocate it +50%
      outbytesleft += outbufsize;
      outbufsize *= 2;
      if (!enif_realloc_binary(&outbuf, outbufsize)) {
	    enif_release_binary(&outbuf);
	    return enif_make_tuple2(env, _atom_error, _atom_enomem);
      }
      out = outbuf.data + (outbufsize - outbytesleft);
    } else {
      enif_release_binary(&outbuf);
      return eiconv_make_error(env, errno);
    }
  } while (rc != 0);

  if(outbytesleft > 0)
    enif_realloc_binary(&outbuf, outbufsize - outbytesleft);

  iconv_close(cd);

  return enif_make_tuple2(env, _atom_ok, enif_make_binary(env, &outbuf));
}

/* 
 * loading -- reloading and upgrade eiconv_nif 
 */
static int on_load(ErlNifEnv* env, void** priv, ERL_NIF_TERM info)
{
  /* Create some atoms 
   */
  _atom_ok = enif_make_atom(env, "ok");
  _atom_error = enif_make_atom(env, "error");
  _atom_enomem = enif_make_atom(env, "no_memory_left");
  _atom_eilseq = enif_make_atom(env, "invalid_sequence");
  _atom_eunknown = enif_make_atom(env, "unknown");
  _atom_badcharset = enif_make_atom(env, "bad_charset");
  return 0;
}

static ErlNifFunc nif_funcs[] = {
  {"conv", 3, eiconv_conv_nif},
};

ERL_NIF_INIT(Elixir.Iconv, nif_funcs, on_load, NULL, NULL, NULL);
