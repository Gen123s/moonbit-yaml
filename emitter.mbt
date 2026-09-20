///| YAML emitter: serialize a Yaml value back into YAML text.

///|
/// Serialize a Yaml value into a YAML document string (block style).
pub fn to_yaml_string(v : Yaml) -> String {
  let sb = StringBuilder()
  emit_node(v, 0, sb, false)
  sb.to_string()
}

///|
pub fn Yaml::to_yaml(self : Yaml) -> String {
  to_yaml_string(self)
}

///|
fn write_indent(sb : StringBuilder, indent : Int) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    sb.write_char(' ')
  }
}

///|
fn emit_node(
  v : Yaml,
  indent : Int,
  sb : StringBuilder,
  after_key : Bool,
) -> Unit {
  match v {
    Null => sb.write_string("null")
    Bool(b) => sb.write_string(if b { "true" } else { "false" })
    Int(i) => sb.write_string(i.to_string())
    Float(f) => sb.write_string(emit_double(f))
    Str(s) => sb.write_string(emit_str(s))
    Arr(items) =>
      if items.is_empty() {
        sb.write_string("[]")
      } else {
        emit_seq(items, indent, sb, after_key)
      }
    Map(pairs) =>
      if pairs.is_empty() {
        sb.write_string("{}")
      } else {
        emit_map(pairs, indent, sb, after_key)
      }
  }
}

///|
fn emit_seq(
  items : Array[Yaml],
  indent : Int,
  sb : StringBuilder,
  after_key : Bool,
) -> Unit {
  for idx, item in items {
    if idx > 0 || after_key {
      sb.write_char('\n')
      write_indent(sb, indent)
    }
    sb.write_string("- ")
    match item {
      Arr(sub) =>
        if sub.is_empty() {
          sb.write_string("[]")
        } else {
          emit_seq(sub, indent + 2, sb, false)
        }
      Map(pairs) =>
        if pairs.is_empty() {
          sb.write_string("{}")
        } else {
          emit_map(pairs, indent + 2, sb, false)
        }
      _ => emit_node(item, indent + 2, sb, false)
    }
  }
}

///|
fn emit_map(
  pairs : Array[(Yaml, Yaml)],
  indent : Int,
  sb : StringBuilder,
  after_key : Bool,
) -> Unit {
  for idx, pair in pairs {
    let (k, v) = pair
    if idx > 0 || after_key {
      sb.write_char('\n')
      write_indent(sb, indent)
    }
    sb.write_string(emit_key(k))
    sb.write_char(':')
    match v {
      Arr(sub) =>
        if sub.is_empty() {
          sb.write_string(" []")
        } else {
          emit_seq(sub, indent + 2, sb, true)
        }
      Map(sub) =>
        if sub.is_empty() {
          sb.write_string(" {}")
        } else {
          emit_map(sub, indent + 2, sb, true)
        }
      _ => {
        sb.write_char(' ')
        emit_node(v, indent + 2, sb, true)
      }
    }
  }
}

///|
/// Emit a mapping key.
fn emit_key(k : Yaml) -> String {
  match k {
    Str(s) => emit_str(s)
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Int(i) => i.to_string()
    Float(f) => emit_double(f)
    _ => "..."
  }
}

///|
/// Emit a scalar string, quoting it when a plain form would be ambiguous.
fn emit_str(s : String) -> String {
  if plain_safe(s) {
    s
  } else {
    double_quote(s)
  }
}

///|
/// Whether the string can be emitted as a plain (unquoted) scalar.
fn plain_safe(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  let cs = s.to_array()
  // leading indicator characters make plain form invalid or ambiguous
  match cs[0] {
    '&'
    | '*'
    | '!'
    | '%'
    | '@'
    | '`'
    | '\''
    | '"'
    | '{'
    | '}'
    | '['
    | ']'
    | ','
    | '|'
    | '>'
    | '#' => return false
    '-' | '?' | ':' | ' ' =>
      // "- " etc. only when followed by space or alone
      if cs.length() == 1 || cs[1] == ' ' {
        return false
      }
    _ => ()
  }
  if cs[cs.length() - 1] == ' ' || cs[cs.length() - 1] == ':' {
    return false
  }
  for i, c in cs {
    if c == '\n' || c == '\t' {
      return false
    }
    if c == ':' && (i + 1 >= cs.length() || cs[i + 1] == ' ') {
      return false
    }
    if c == '#' && i > 0 && cs[i - 1] == ' ' {
      return false
    }
  }
  // would re-parse as a different scalar type?
  match resolve_scalar(s) {
    Str(_) => true
    _ => false
  }
}

///|
/// Double-quote a string with escapes.
fn double_quote(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s.to_array() {
    match c {
      '"' => {
        sb.write_string("\\\"")
        continue
      }
      '\\' => {
        sb.write_string("\\\\")
        continue
      }
      '\n' => {
        sb.write_string("\\n")
        continue
      }
      '\t' => {
        sb.write_string("\\t")
        continue
      }
      '\r' => {
        sb.write_string("\\r")
        continue
      }
      '\u{0}' => {
        sb.write_string("\\0")
        continue
      }
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// Render a double in a form that re-parses as a YAML float.
fn emit_double(f : Double) -> String {
  if f == f {
    if f == 1.0 / 0.0 {
      return ".inf"
    }
    if f == -1.0 / 0.0 {
      return "-.inf"
    }
    let s = f.to_string()
    let cs = s.to_array()
    let mut has_dot_or_exp = false
    for c in cs {
      if c == '.' || c == 'e' || c == 'E' {
        has_dot_or_exp = true
      }
    }
    if has_dot_or_exp || s == "0" || s == "-0" {
      s
    } else {
      s + ".0"
    }
  } else {
    ".nan"
  }
}
