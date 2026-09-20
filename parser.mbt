///| Line-based recursive descent parser for YAML block style, with an
/// embedded flow-style parser. Anchors and aliases are resolved through a
/// per-document anchor table carried in `Ctx`.

///|
/// A logical line of the input document.
priv struct Line {
  indent : Int // number of leading spaces (tabs rejected)
  content : String // line without leading spaces, trailing spaces trimmed
  raw : String // original line (for block scalars)
}

///|
/// Parser context: the anchor table of the current document.
priv struct Ctx {
  anchors : Map[String, Yaml]
}

///|
priv struct Pos {
  mut i : Int
}

///|
fn preprocess(input : String) -> Array[Line] {
  let out : Array[Line] = []
  let lines = input.split("\n")
  for l0 in lines {
    let l1 = l0.to_owned()
    let l = if l1.has_suffix("\r") {
      l1[:l1.length() - 1].to_owned()
    } else {
      l1
    }
    let mut indent = 0
    let cs = l.to_array()
    while indent < cs.length() && cs[indent] == ' ' {
      indent = indent + 1
    }
    let content = l[indent:].to_owned() |> trim_end_str
    out.push({ indent, content, raw: l, })
  }
  out
}

///|
fn trim_end_str(s : String) -> String {
  let cs = s.to_array()
  let mut e = cs.length()
  while e > 0 && (cs[e - 1] == ' ' || cs[e - 1] == '\t') {
    e = e - 1
  }
  s[:e].to_owned()
}

///|
fn is_blank_or_comment(l : Line) -> Bool {
  l.content.is_empty() || l.content[0] == '#'
}

///|
fn skip_ignorable(lines : Array[Line], start : Int) -> Int {
  let mut i = start
  while i < lines.length() && is_blank_or_comment(lines[i]) {
    i = i + 1
  }
  i
}

///|
/// Parse a block node starting at or after `start`, whose entries sit at
/// indentation `indent`. Returns the value and the first unconsumed line
/// index.
fn parse_block(
  ctx : Ctx,
  lines : Array[Line],
  start : Int,
  indent : Int,
) -> (Yaml, Int) raise YamlError {
  let i = skip_ignorable(lines, start)
  if i >= lines.length() {
    return (Null, i)
  }
  if lines[i].indent < indent {
    return (Null, i)
  }
  let line = lines[i]
  if line.content == "---" {
    return parse_block(ctx, lines, i + 1, line.indent)
  }
  if line.content == "..." {
    return (Null, i + 1)
  }
  if is_seq_item(line) && line.indent == indent {
    parse_sequence(ctx, lines, i, indent)
  } else if find_top_colon(line.content) is Some(_) && line.indent == indent {
    parse_mapping(ctx, lines, i, indent)
  } else {
    // plain / quoted / flow scalar on its own line(s)
    parse_inline(ctx, lines, i)
  }
}

///|
fn is_seq_item(l : Line) -> Bool {
  l.content == "-" || l.content.has_prefix("- ")
}

///|
/// Find the position of the ':' that separates a plain key from its value,
/// at the top level (not inside quotes or flow brackets). The ':' must be
/// followed by a space or be the last character.
fn find_top_colon(s : String) -> Int? {
  let cs = s.to_array()
  let mut i = 0
  let mut depth = 0
  let mut in_sq = false
  let mut in_dq = false
  while i < cs.length() {
    let c = cs[i]
    if in_sq {
      if c == '\'' {
        if i + 1 < cs.length() && cs[i + 1] == '\'' {
          i = i + 1
        } else {
          in_sq = false
        }
      }
    } else if in_dq {
      if c == '\\' {
        i = i + 1
      } else if c == '"' {
        in_dq = false
      }
    } else {
      match c {
        '\'' => in_sq = true
        '"' => in_dq = true
        '[' | '{' => depth = depth + 1
        ']' | '}' => depth = depth - 1
        ':' =>
          if depth == 0 && (i + 1 >= cs.length() || cs[i + 1] == ' ') {
            return Some(i)
          }
        '#' => if i > 0 && cs[i - 1] == ' ' { return None }
        _ => ()
      }
    }
    i = i + 1
  }
  None
}

///|
/// Split "&name rest" into (name, rest). Returns None if s does not start
/// with an anchor.
fn split_anchor(s : String) -> (String, String)? {
  if !s.has_prefix("&") {
    return None
  }
  let cs = s.to_array()
  let mut i = 1
  while i < cs.length() && cs[i] != ' ' {
    i = i + 1
  }
  let name = s[1:i].to_owned()
  let rest = strip_leading_spaces(s[i:].to_owned())
  Some((name, rest))
}

///|
/// Resolve "*name" alias text into its anchored value.
fn lookup_alias(ctx : Ctx, s : String) -> Yaml? {
  if !s.has_prefix("*") {
    return None
  }
  let name = s[1:].to_owned() |> trim_end_str
  ctx.anchors.get(name)
}

///|
/// Parse the value part that follows "key:" or "-" on an entry line.
/// `i` is the index of the entry line; `rest` is the text after the marker;
/// `indent` is the indentation of the entry line.
fn parse_value_rest(
  ctx : Ctx,
  lines : Array[Line],
  i : Int,
  indent : Int,
  rest0 : String,
) -> (Yaml, Int) raise YamlError {
  let rest = strip_leading_spaces(rest0)
  // alias?
  if rest.has_prefix("*") {
    match lookup_alias(ctx, rest) {
      Some(v) => return (v, i + 1)
      None => raise YamlError("unknown alias: " + rest)
    }
  }
  // anchor?
  match split_anchor(rest) {
    Some((name, remainder)) => {
      let (v, next) = parse_value_rest(ctx, lines, i, indent, " " + remainder)
      ctx.anchors.set(name, v)
      return (v, next)
    }
    None => ()
  }
  if rest.is_empty() {
    // nested block on following lines, or sequence at same indent
    let j = skip_ignorable(lines, i + 1)
    if j < lines.length() && lines[j].indent > indent {
      let (v, next) = parse_block(ctx, lines, j, lines[j].indent)
      return (v, next)
    }
    if j < lines.length() && lines[j].indent == indent && is_seq_item(lines[j]) {
      let (v, next) = parse_sequence(ctx, lines, j, indent)
      return (v, next)
    }
    return (Null, i + 1)
  }
  if is_block_scalar_header(rest) {
    return parse_block_scalar(lines, i + 1, indent, rest)
  }
  // mapping whose first entry sits on this entry line: "- key: value"
  if find_top_colon(rest) is Some(_) &&
    !rest.has_prefix("[") &&
    !rest.has_prefix("{") {
    let child_indent = indent + 2
    let vlines : Array[Line] = [
      { indent: child_indent, content: rest, raw: lines[i].raw, },
    ]
    for k = i + 1; k < lines.length(); k = k + 1 {
      vlines.push(lines[k])
    }
    let (v, consumed) = parse_mapping(ctx, vlines, 0, child_indent)
    return (v, i + consumed)
  }
  // inline value: build a virtual line carrying just the value text
  let vlines : Array[Line] = [
    { indent: indent + 2, content: rest, raw: lines[i].raw, },
  ]
  let (v, _) = parse_inline(ctx, vlines, 0)
  (v, i + 1)
}

///|
fn parse_sequence(
  ctx : Ctx,
  lines : Array[Line],
  start : Int,
  indent : Int,
) -> (Yaml, Int) raise YamlError {
  let items : Array[Yaml] = []
  let mut i = start
  while true {
    i = skip_ignorable(lines, i)
    if i >= lines.length() {
      break
    }
    let line = lines[i]
    if line.indent != indent || !is_seq_item(line) {
      break
    }
    let rest = if line.content == "-" {
      ""
    } else {
      line.content[2:].to_owned()
    }
    let (v, next) = parse_value_rest(ctx, lines, i, indent, rest)
    items.push(v)
    i = next
  }
  (Arr(items), i)
}

///|
fn parse_mapping(
  ctx : Ctx,
  lines : Array[Line],
  start : Int,
  indent : Int,
) -> (Yaml, Int) raise YamlError {
  let pairs : Array[(Yaml, Yaml)] = []
  let merges : Array[Yaml] = [] // deferred "<<" merge values
  let mut i = start
  while true {
    i = skip_ignorable(lines, i)
    if i >= lines.length() {
      break
    }
    let line = lines[i]
    if line.indent != indent {
      break
    }
    if is_seq_item(line) {
      break
    }
    match find_top_colon(line.content) {
      None => break
      Some(cpos) => {
        let key_str = line.content[:cpos].to_owned()
        let key = parse_flow_scalar_key(key_str)
        let rest = line.content[cpos + 1:].to_owned()
        let (v, next) = parse_value_rest(ctx, lines, i, indent, rest)
        if key is Str("<<") {
          merges.push(v)
        } else {
          pairs.push((key, v))
        }
        i = next
      }
    }
  }
  // merge keys: explicit keys always win; earlier merges win over later
  for v in merges {
    merge_into(pairs, v)
  }
  (Map(pairs), i)
}

///|
/// Merge `v` (a mapping, or a sequence of mappings) into `pairs`; existing
/// keys are never overwritten.
fn merge_into(pairs : Array[(Yaml, Yaml)], v : Yaml) -> Unit {
  match v {
    Map(src) => merge_pairs(pairs, src)
    Arr(xs) =>
      for x in xs {
        merge_into(pairs, x)
      }
    _ => ()
  }
}

///|
fn merge_pairs(pairs : Array[(Yaml, Yaml)], src : Array[(Yaml, Yaml)]) -> Unit {
  for pair in src {
    let (k, v) = pair
    let exists = pairs.iter().any(fn(p) { p.0 == k })
    if !exists {
      pairs.push((k, v))
    }
  }
}

///|
fn strip_leading_spaces(s : String) -> String {
  let cs = s.to_array()
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' {
    i = i + 1
  }
  s[i:].to_owned()
}

///|
fn is_block_scalar_header(s : String) -> Bool {
  let t = trim_end_str(s)
  t == "|" || t == ">" || t == "|-" || t == ">-" || t == "|+" || t == ">+"
}

///|
/// Parse a literal (|) or folded (>) block scalar whose header is on the
/// entry line. Consumes all following lines indented deeper than
/// `parent_indent`.
fn parse_block_scalar(
  lines : Array[Line],
  start : Int,
  parent_indent : Int,
  header : String,
) -> (Yaml, Int) {
  let literal = header[0] == '|'
  let chomp_strip = header.has_suffix("-")
  let chomp_keep = header.has_suffix("+")
  let collected : Array[String] = []
  let mut i = start
  let mut block_indent = -1
  while i < lines.length() {
    let l = lines[i]
    if l.content.is_empty() {
      // blank lines belong to the block (if block has started or continues)
      collected.push("")
      i = i + 1
      continue
    }
    if l.indent <= parent_indent {
      break
    }
    if block_indent < 0 {
      block_indent = l.indent
    }
    if l.indent < block_indent {
      break
    }
    collected.push(l.raw[block_indent:].to_owned())
    i = i + 1
  }
  // drop trailing blank lines (they are handled by chomping)
  let mut n = collected.length()
  while n > 0 && collected[n - 1].is_empty() {
    n = n - 1
  }
  let body : Array[String] = []
  for k = 0; k < n; k = k + 1 {
    body.push(collected[k])
  }
  let sb = StringBuilder()
  if literal {
    for idx, part in body {
      sb.write_string(part)
      if idx < body.length() - 1 {
        sb.write_char('\n')
      }
    }
  } else {
    // folded: consecutive non-empty lines join with space; blank line => \n
    let mut prev_blank = false
    for idx, part in body {
      if part.is_empty() {
        sb.write_char('\n')
        prev_blank = true
      } else {
        if idx > 0 && !prev_blank {
          sb.write_char(' ')
        }
        sb.write_string(part)
        prev_blank = false
      }
    }
  }
  if chomp_keep {
    sb.write_char('\n')
    // re-append the trailing blank lines
    for k = n; k < collected.length(); k = k + 1 {
      sb.write_char('\n')
    }
  } else if !chomp_strip && body.length() > 0 {
    sb.write_char('\n')
  }
  (Str(sb.to_string()), i)
}

///|
/// Parse an inline node: flow collection (possibly multi-line), quoted
/// scalar, or plain scalar.
fn parse_inline(
  ctx : Ctx,
  lines : Array[Line],
  start : Int,
) -> (Yaml, Int) raise YamlError {
  let line = lines[start]
  let s0 = strip_comment(line.content)
  if s0.is_empty() {
    return (Null, start + 1)
  }
  let first = s0.to_array()[0]
  if first == '[' || first == '{' {
    // flow may span multiple lines: join until brackets balance
    let sb = StringBuilder()
    let mut consumed = start
    let mut depth = 0
    let mut done = false
    while consumed < lines.length() && !done {
      let part = lines[consumed].content
      sb.write_string(part)
      sb.write_char(' ')
      let cs = part.to_array()
      let mut in_sq = false
      let mut in_dq = false
      for c in cs {
        if in_sq {
          if c == '\'' {
            in_sq = false
          }
        } else if in_dq {
          if c == '"' {
            in_dq = false
          }
        } else {
          match c {
            '\'' => in_sq = true
            '"' => in_dq = true
            '[' | '{' => depth = depth + 1
            ']' | '}' => {
              depth = depth - 1
              if depth == 0 {
                done = true
              }
            }
            _ => ()
          }
        }
      }
      consumed = consumed + 1
    }
    let chars = sb.to_string().to_array()
    let pos : Pos = { i: 0, }
    let v = parse_flow(ctx, chars, pos)
    (v, consumed)
  } else if first == '"' {
    (Str(parse_double_quoted(s0.to_array(), { i: 0, })), start + 1)
  } else if first == '\'' {
    (Str(parse_single_quoted(s0.to_array(), { i: 0, })), start + 1)
  } else {
    (resolve_scalar(s0), start + 1)
  }
}

///|
/// Remove a trailing " # comment" from a plain scalar line (comment must be
/// preceded by a space and outside quotes).
fn strip_comment(s : String) -> String {
  let cs = s.to_array()
  let mut in_sq = false
  let mut in_dq = false
  for i, c in cs {
    if in_sq {
      if c == '\'' {
        in_sq = false
      }
    } else if in_dq {
      if c == '"' {
        in_dq = false
      }
    } else {
      match c {
        '\'' => in_sq = true
        '"' => in_dq = true
        '#' =>
          if i > 0 && cs[i - 1] == ' ' {
            return trim_end_str(s[:i].to_owned())
          }
        _ => ()
      }
    }
  }
  trim_end_str(s)
}

///|
/// Parse a mapping key (plain or quoted scalar).
fn parse_flow_scalar_key(s : String) -> Yaml {
  let t = trim_end_str(s)
  if t.is_empty() {
    return Null
  }
  let cs = t.to_array()
  if cs[0] == '"' {
    return Str(parse_double_quoted(cs, { i: 0, }))
  }
  if cs[0] == '\'' {
    return Str(parse_single_quoted(cs, { i: 0, }))
  }
  resolve_scalar(t)
}
