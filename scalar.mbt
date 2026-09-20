///| Scalar resolution (YAML 1.2 core schema) and quoted / flow parsing.

///|
/// Resolve a plain scalar string into a typed Yaml value.
fn resolve_scalar(raw : String) -> Yaml {
  let s = trim_end_str(raw)
  if s.is_empty() {
    return Null
  }
  match s {
    "~" | "null" | "Null" | "NULL" => return Null
    "true" | "True" | "TRUE" => return Bool(true)
    "false" | "False" | "FALSE" => return Bool(false)
    _ => ()
  }
  // numbers
  match parse_number(s) {
    Some(v) => return v
    None => ()
  }
  Str(s)
}

///|
fn parse_number(s : String) -> Yaml? {
  let cs = s.to_array()
  let mut i = 0
  let mut neg = false
  if i < cs.length() && (cs[i] == '-' || cs[i] == '+') {
    neg = cs[i] == '-'
    i = i + 1
  }
  let rest = s[i:].to_owned()
  let rl = rest.to_lower()
  if rl == ".inf" {
    return Some(Float(if neg { -1.0 / 0.0 } else { 1.0 / 0.0 }))
  }
  if rl == ".nan" {
    return Some(Float(0.0 / 0.0))
  }
  // strip underscores
  let sb = StringBuilder()
  let rc = rest.to_array()
  let mut any_digit = false
  for c in rc {
    if c >= '0' && c <= '9' {
      any_digit = true
    }
    if c != '_' {
      sb.write_char(c)
    }
  }
  if !any_digit {
    return None
  }
  let clean = sb.to_string()
  let cc = clean.to_array()
  // hex / octal
  if cc.length() > 2 && cc[0] == '0' && (cc[1] == 'x' || cc[1] == 'X') {
    let digits = clean[2:].to_owned()
    match parse_radix(digits, 16) {
      Some(v) => return Some(Int(if neg { -v } else { v }))
      None => return None
    }
  }
  if cc.length() > 2 && cc[0] == '0' && (cc[1] == 'o' || cc[1] == 'O') {
    let digits = clean[2:].to_owned()
    match parse_radix(digits, 8) {
      Some(v) => return Some(Int(if neg { -v } else { v }))
      None => return None
    }
  }
  // decimal int
  let mut all_digit = true
  for c in cc {
    if !(c >= '0' && c <= '9') {
      all_digit = false
    }
  }
  if all_digit && cc.length() > 0 {
    match parse_radix(clean, 10) {
      Some(v) => return Some(Int(if neg { -v } else { v }))
      None => return None
    }
  }
  // float: contains '.', 'e' or 'E' and remaining chars are numeric-ish
  let mut has_dot_or_e = false
  let mut ok = true
  for c in cc {
    match c {
      '.' | 'e' | 'E' => has_dot_or_e = true
      '+' | '-' => ()
      _ => if !(c >= '0' && c <= '9') { ok = false }
    }
  }
  if ok && has_dot_or_e {
    let full = if neg { "-" + clean } else { clean }
    let d : Double? = try @string.parse_double(full) catch {
      _ => None
    } noraise {
      d => Some(d)
    }
    match d {
      Some(d) => return Some(Float(d))
      None => return None
    }
  }
  None
}

///|
fn parse_radix(digits : String, radix : Int) -> Int64? {
  let cs = digits.to_array()
  if cs.length() == 0 {
    return None
  }
  let mut v : Int64 = 0
  for c in cs {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    if d >= radix {
      return None
    }
    v = v * radix.to_int64() + d.to_int64()
  }
  Some(v)
}

///|
/// Parse a double-quoted scalar starting at pos (cs[pos.i] == '"').
fn parse_double_quoted(cs : Array[Char], pos : Pos) -> String {
  let sb = StringBuilder()
  pos.i = pos.i + 1 // skip opening quote
  while pos.i < cs.length() {
    let c = cs[pos.i]
    if c == '"' {
      pos.i = pos.i + 1
      break
    }
    if c == '\\' && pos.i + 1 < cs.length() {
      let e = cs[pos.i + 1]
      match e {
        'n' => {
          sb.write_char('\n')
          pos.i = pos.i + 2
        }
        't' => {
          sb.write_char('\t')
          pos.i = pos.i + 2
        }
        'r' => {
          sb.write_char('\r')
          pos.i = pos.i + 2
        }
        '0' => {
          sb.write_char('\u{0}')
          pos.i = pos.i + 2
        }
        'b' => {
          sb.write_char('\u{8}')
          pos.i = pos.i + 2
        }
        'f' => {
          sb.write_char('\u{c}')
          pos.i = pos.i + 2
        }
        'e' => {
          sb.write_char('\u{1b}')
          pos.i = pos.i + 2
        }
        '"' => {
          sb.write_char('"')
          pos.i = pos.i + 2
        }
        '\\' => {
          sb.write_char('\\')
          pos.i = pos.i + 2
        }
        '/' => {
          sb.write_char('/')
          pos.i = pos.i + 2
        }
        'x' => {
          let h = take_hex(cs, pos.i + 2, 2)
          sb.write_char(h.0)
          pos.i = h.1
        }
        'u' => {
          let h = take_hex(cs, pos.i + 2, 4)
          sb.write_char(h.0)
          pos.i = h.1
        }
        _ => {
          sb.write_char(e)
          pos.i = pos.i + 2
        }
      }
    } else {
      sb.write_char(c)
      pos.i = pos.i + 1
    }
  }
  sb.to_string()
}

///|
fn take_hex(cs : Array[Char], start : Int, n : Int) -> (Char, Int) {
  let mut v = 0
  let mut i = start
  let mut k = 0
  while k < n && i < cs.length() {
    let c = cs[i]
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      break
    }
    v = v * 16 + d
    i = i + 1
    k = k + 1
  }
  (v.unsafe_to_char(), i)
}

///|
/// Parse a single-quoted scalar ('' escapes a quote).
fn parse_single_quoted(cs : Array[Char], pos : Pos) -> String {
  let sb = StringBuilder()
  pos.i = pos.i + 1
  while pos.i < cs.length() {
    let c = cs[pos.i]
    if c == '\'' {
      if pos.i + 1 < cs.length() && cs[pos.i + 1] == '\'' {
        sb.write_char('\'')
        pos.i = pos.i + 2
        continue
      }
      pos.i = pos.i + 1
      break
    }
    sb.write_char(c)
    pos.i = pos.i + 1
  }
  sb.to_string()
}

///|
/// Flow style: parse one value from a char stream. Plain scalars that
/// start with '*' are resolved as aliases through the context.
fn parse_flow(ctx : Ctx, cs : Array[Char], pos : Pos) -> Yaml raise YamlError {
  skip_ws(cs, pos)
  if pos.i >= cs.length() {
    return Null
  }
  match cs[pos.i] {
    '{' => {
      pos.i = pos.i + 1
      let pairs : Array[(Yaml, Yaml)] = []
      skip_ws(cs, pos)
      if pos.i < cs.length() && cs[pos.i] == '}' {
        pos.i = pos.i + 1
        return Map(pairs)
      }
      while pos.i < cs.length() {
        skip_ws(cs, pos)
        let key = parse_flow_scalar_or_quoted_key(cs, pos)
        skip_ws(cs, pos)
        let mut value : Yaml = Null
        if pos.i < cs.length() && cs[pos.i] == ':' {
          pos.i = pos.i + 1
          value = parse_flow(ctx, cs, pos)
        }
        pairs.push((key, value))
        skip_ws(cs, pos)
        if pos.i < cs.length() && cs[pos.i] == ',' {
          pos.i = pos.i + 1
          continue
        }
        if pos.i < cs.length() && cs[pos.i] == '}' {
          pos.i = pos.i + 1
          break
        }
        break
      }
      Map(pairs)
    }
    '[' => {
      pos.i = pos.i + 1
      let items : Array[Yaml] = []
      skip_ws(cs, pos)
      if pos.i < cs.length() && cs[pos.i] == ']' {
        pos.i = pos.i + 1
        return Arr(items)
      }
      while pos.i < cs.length() {
        let v = parse_flow(ctx, cs, pos)
        items.push(v)
        skip_ws(cs, pos)
        if pos.i < cs.length() && cs[pos.i] == ',' {
          pos.i = pos.i + 1
          continue
        }
        if pos.i < cs.length() && cs[pos.i] == ']' {
          pos.i = pos.i + 1
          break
        }
        break
      }
      Arr(items)
    }
    '"' => Str(parse_double_quoted(cs, pos))
    '\'' => Str(parse_single_quoted(cs, pos))
    _ => {
      let s = parse_plain_flow_scalar(cs, pos)
      if s.has_prefix("*") {
        match lookup_alias(ctx, s) {
          Some(v) => return v
          None => raise YamlError("unknown alias: " + s)
        }
      }
      resolve_scalar(s)
    }
  }
}

///|
fn skip_ws(cs : Array[Char], pos : Pos) -> Unit {
  while pos.i < cs.length() && (cs[pos.i] == ' ' || cs[pos.i] == '\t') {
    pos.i = pos.i + 1
  }
}

///|
fn parse_flow_scalar_or_quoted_key(cs : Array[Char], pos : Pos) -> Yaml {
  if pos.i < cs.length() && cs[pos.i] == '"' {
    return Str(parse_double_quoted(cs, pos))
  }
  if pos.i < cs.length() && cs[pos.i] == '\'' {
    return Str(parse_single_quoted(cs, pos))
  }
  resolve_scalar(parse_plain_flow_scalar(cs, pos))
}

///|
/// Plain scalar inside flow context: ends at , } ] or a ": " separator.
fn parse_plain_flow_scalar(cs : Array[Char], pos : Pos) -> String {
  let sb = StringBuilder()
  while pos.i < cs.length() {
    let c = cs[pos.i]
    match c {
      ',' | '}' | ']' => break
      ':' => {
        let nxt = if pos.i + 1 < cs.length() { cs[pos.i + 1] } else { ' ' }
        if nxt == ' ' ||
          nxt == ',' ||
          nxt == '}' ||
          nxt == ']' ||
          pos.i + 1 >= cs.length() {
          break
        }
        sb.write_char(c)
        pos.i = pos.i + 1
      }
      '#' => {
        if pos.i > 0 && cs[pos.i - 1] == ' ' {
          break
        }
        sb.write_char(c)
        pos.i = pos.i + 1
      }
      _ => {
        sb.write_char(c)
        pos.i = pos.i + 1
      }
    }
  }
  trim_end_str(sb.to_string())
}
