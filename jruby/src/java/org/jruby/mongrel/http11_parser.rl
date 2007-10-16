package org.jruby.mongrel;

import org.jruby.util.ByteList;

public class Http11Parser {

/** machine **/
%%{
  machine http_parser;

  action mark {parser.mark = fpc; }

  action start_field { parser.field_start = fpc; }
  action write_field { 
    parser.field_len = fpc-parser.field_start;
  }

  action start_value { parser.mark = fpc; }
  action write_value { 
    if(parser.http_field != null) {
      parser.http_field.call(parser.data, parser.field_start, parser.field_len, parser.mark, fpc-parser.mark);
    }
  }
  action request_method { 
    if(parser.request_method != null) 
      parser.request_method.call(parser.data, parser.mark, fpc-parser.mark);
  }
  action request_uri { 
    if(parser.request_uri != null)
      parser.request_uri.call(parser.data, parser.mark, fpc-parser.mark);
  }

  action start_query {parser.query_start = fpc; }
  action query_string { 
    if(parser.query_string != null)
      parser.query_string.call(parser.data, parser.query_start, fpc-parser.query_start);
  }

  action http_version {	
    if(parser.http_version != null)
      parser.http_version.call(parser.data, parser.mark, fpc-parser.mark);
  }

  action request_path {
    if(parser.request_path != null)
      parser.request_path.call(parser.data, parser.mark, fpc-parser.mark);
  }

  action done { 
    parser.body_start = fpc + 1; 
    if(parser.header_done != null)
      parser.header_done.call(parser.data, fpc + 1, pe - fpc - 1);
    fbreak;
  }


#### HTTP PROTOCOL GRAMMAR
# line endings
  CRLF = "\r\n";

# character types
  CTL = (cntrl | 127);
  safe = ("$" | "-" | "_" | ".");
  extra = ("!" | "*" | "'" | "(" | ")" | ",");
  reserved = (";" | "/" | "?" | ":" | "@" | "&" | "=" | "+");
  unsafe = (CTL | " " | "\"" | "#" | "%" | "<" | ">");
  national = any -- (alpha | digit | reserved | extra | safe | unsafe);
  unreserved = (alpha | digit | safe | extra | national);
  escape = ("%" xdigit xdigit);
  uchar = (unreserved | escape);
  pchar = (uchar | ":" | "@" | "&" | "=" | "+");
  tspecials = ("(" | ")" | "<" | ">" | "@" | "," | ";" | ":" | "\\" | "\"" | "/" | "[" | "]" | "?" | "=" | "{" | "}" | " " | "\t");

# elements
  token = (ascii -- (CTL | tspecials));

# URI schemes and absolute paths
  scheme = ( alpha | digit | "+" | "-" | "." )* ;
  absolute_uri = (scheme ":" (uchar | reserved )*);

  path = (pchar+ ( "/" pchar* )*) ;
  query = ( uchar | reserved )* %query_string ;
  param = ( pchar | "/" )* ;
  params = (param ( ";" param )*) ;
  rel_path = (path? %request_path (";" params)?) ("?" %start_query query)?;
  absolute_path = ("/"+ rel_path);

  Request_URI = ("*" | absolute_uri | absolute_path) >mark %request_uri;
  Method = (upper | digit | safe){1,20} >mark %request_method;

  http_number = (digit+ "." digit+) ;
  HTTP_Version = ("HTTP/" http_number) >mark %http_version ;
  Request_Line = (Method " " Request_URI " " HTTP_Version CRLF) ;

  field_name = (token -- ":")+ >start_field %write_field;

  field_value = any* >start_value %write_value;

  message_header = field_name ":" " "* field_value :> CRLF;

  Request = Request_Line (message_header)* ( CRLF @done);

main := Request;
}%%

/** Data **/
%% write data;

   public static interface ElementCB {
     public void call(Object data, int at, int length);
   }

   public static interface FieldCB {
     public void call(Object data, int field, int flen, int value, int vlen);
   }

   public static class HttpParser {
      int cs;
      int body_start;
      int content_len;
      int nread;
      int mark;
      int field_start;
      int field_len;
      int query_start;

      Object data;
      ByteList buffer;

      public FieldCB http_field;
      public ElementCB request_method;
      public ElementCB request_uri;
      public ElementCB request_path;
      public ElementCB query_string;
      public ElementCB http_version;
      public ElementCB header_done;

      public void init() {
          cs = 0;

          %% write init;

          body_start = 0;
          content_len = 0;
          mark = 0;
          nread = 0;
          field_len = 0;
          field_start = 0;
      }
   }

   public final HttpParser parser = new HttpParser();

   public int execute(ByteList buffer, int off) {
     int p, pe;
     int cs = parser.cs;
     int len = buffer.realSize;
     assert off<=len : "offset past end of buffer";

     p = off;
     pe = len;
     byte[] data = buffer.bytes;
     parser.buffer = buffer;

     %% write exec;

     parser.cs = cs;
     parser.nread += (p - off);
     
     assert p <= pe                  : "buffer overflow after parsing execute";
     assert parser.nread <= len      : "nread longer than length";
     assert parser.body_start <= len : "body starts after buffer end";
     assert parser.mark < len        : "mark is after buffer end";
     assert parser.field_len <= len  : "field has length longer than whole buffer";
     assert parser.field_start < len : "field starts after buffer end";

     if(parser.body_start>0) {
        /* final \r\n combo encountered so stop right here */
        %%write eof;
        parser.nread++;
     }

     return parser.nread;
   }

   public int finish() {
     int cs = parser.cs;

     %%write eof;

     parser.cs = cs;
 
    if(has_error()) {
      return -1;
    } else if(is_finished()) {
      return 1;
    } else {
      return 0;
    }
  }

  public boolean has_error() {
    return parser.cs == http_parser_error;
  }

  public boolean is_finished() {
    return parser.cs == http_parser_first_final;
  }
}
