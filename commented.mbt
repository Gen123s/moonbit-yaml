///| Comment-preserving parse/emit layer.
///
/// The plain `parse`/`to_yaml_string` API treats comments as whitespace:
/// they are dropped on parse and cannot be restored on emit. This layer
/// keeps them: `parse_commented` builds a `CNode` tree that carries the
/// comments attached to each node, and `Commented::to_yaml_string` writes
/// them back out. Editing a value through `CNode::set_path` therefore
/// produces output in which every original comment survives — the
/// "edit a config file without destroying it" capability.

///|
/// A YAML node that carries comments.
///
/// `head` holds the full-line comments (and blank-line markers, "") that
/// appeared immediately before this node in the source; `tail` holds the
/// `# comment` written on the same line after the value.
pub(all) struct CNode {
  mut val : CVal
  mut head : Array[String]
  mut tail : String?
} derive(Debug)

///|
pub extend CNode with Debug::{to_repr}

///|
/// The shape of a commented node: a scalar leaf, or a collection of
/// commented children.
pub(all) enum CVal {
  Leaf(Yaml)
  Seq(Array[CNode])
  Map(Array[(Yaml, CNode)])
} derive(Debug)

///|
pub extend CVal with Debug::{to_repr}

///|
/// A parsed document with comments. `epilogue` holds the comments and blank
/// lines that trail the last node of the file.
pub(all) struct Commented {
  root : CNode
  epilogue : Array[String]
} derive(Debug)

///|
pub extend Commented with Debug::{to_repr}

///|
/// Parser context for the commented layer: anchor table plus the pending
/// trailing comments that a enclosing collection must flush.
priv struct CCtx {
  anchors : Map[String, CNode]
  epilogue : Array[String]
}

///|
/// Parse a YAML document into a comment-preserving tree. Only the first
/// document of a stream is returned (like `parse`).
pub fn parse_commented(input : String) -> Commented raise YamlError {
  let lines = preprocess(input)
  let ctx : CCtx = { anchors: {}, epilogue: [], }
  let (head, i) = collect_head(lines, 0)
  if i >= lines.length() {
    return { root: { val: Leaf(Null), head, tail: None, }, epilogue: [], }
  }
  let (root, next) = parse_cvalue(ctx, lines, i, lines[i].indent)
  root.head = head + root.head
  // trailing comments / blank lines after the last node
  let (tail_comments, j) = collect_head(lines, next)
  for c in tail_comments {
    ctx.epilogue.push(c)
  }
  let _ = j
  { root, epilogue: ctx.epilogue, }
}

///|
/// Serialize a commented document back to YAML text, restoring every
/// comment in its original position.
pub fn Commented::to_yaml_string(self : Commented) -> String {
  let sb = StringBuilder()
  let es : ES = { at_start: true, }
  for c in self.root.head {
    cmt_line(es, sb, 0, c)
  }
  line(es, sb, 0)
  emit_cval(es, self.root.val, 0, sb, true)
  for c in self.epilogue {
    cmt_line(es, sb, 0, c)
  }
  sb.to_string()
}

///|
/// Emitter state: `at_start` = cursor sits at the beginning of a line.
priv struct ES {
  mut at_start : Bool
}

///|
/// Start a new line at `indent` (newline only when the cursor is mid-line).
/// The caller immediately writes content afterwards, so the cursor ends up
/// mid-line.
fn line(es : ES, sb : StringBuilder, indent : Int) -> Unit {
  if !es.at_start {
    sb.write_char('\n')
  }
  write_indent(sb, indent)
  es.at_start = true
}

///|
/// Start a comment line. A blank marker renders as one empty line: it
/// terminates the current line (if any) and then adds the blank line.
fn cmt_line(es : ES, sb : StringBuilder, indent : Int, c : String) -> Unit {
  if !es.at_start {
    sb.write_char('\n')
  }
  if !c.is_empty() {
    write_indent(sb, indent)
    sb.write_string(c)
    es.at_start = false
  } else {
    sb.write_char('\n')
    es.at_start = true
  }
}

///|
/// Convert the commented tree back to a plain Yaml value (comments dropped).
pub fn Commented::to_yaml(self : Commented) -> Yaml {
  cval_to_yaml(self.root.val)
}

///|
fn cval_to_yaml(v : CVal) -> Yaml {
  match v {
    Leaf(y) => y
    Seq(items) => {
      let xs : Array[Yaml] = []
      for item in items {
        xs.push(cval_to_yaml(item.val))
      }
      Arr(xs)
    }
    Map(pairs) => {
      let ps : Array[(Yaml, Yaml)] = []
      for pair in pairs {
        let (k, node) = pair
        ps.push((k, cval_to_yaml(node.val)))
      }
      Map(ps)
    }
  }
}

///|
/// Navigate a dotted path ("services.web.image") through map children.
pub fn CNode::get_path(self : CNode, path : String) -> CNode? {
  let parts = path.split(".")
  let mut cur : CNode? = Some(self)
  for part in parts {
    match cur {
      Some(node) =>
        match node.val {
          Map(pairs) => {
            let mut found : CNode? = None
            for pair in pairs {
              let (k, v) = pair
              match k {
                Str(s) => if s == part.to_owned() { found = Some(v) }
                _ => ()
              }
            }
            cur = found
          }
          _ => return None
        }
      None => return None
    }
  }
  cur
}

///|
/// Replace the scalar (or whole subtree) at a dotted path with `y`.
/// Returns false when the path does not exist. Comments around the node
/// are preserved: only the value changes.
pub fn CNode::set_path(self : CNode, path : String, y : Yaml) -> Bool {
  let parts = path.split(".").collect()
  if parts.is_empty() {
    return false
  }
  let mut cur : CNode? = Some(self)
  for idx = 0; idx < parts.length() - 1; idx = idx + 1 {
    match cur {
      Some(node) =>
        match node.val {
          Map(pairs) => {
            let mut found : CNode? = None
            for pair in pairs {
              let (k, v) = pair
              match k {
                Str(s) => if s == parts[idx].to_owned() { found = Some(v) }
                _ => ()
              }
            }
            cur = found
          }
          _ => return false
        }
      None => return false
    }
  }
  match cur {
    Some(node) =>
      match node.val {
        Map(pairs) => {
          let last = parts[parts.length() - 1]
          for pair in pairs {
            let (k, v) = pair
            match k {
              Str(s) =>
                if s == last.to_owned() {
                  v.val = Leaf(y)
                  return true
                }
              _ => ()
            }
          }
          false
        }
        _ => {
          node.val = Leaf(y)
          true
        }
      }
    None => false
  }
}

///|
/// Collect full-line comments and blank-line markers starting at `start`,
/// until the first "real" content line. Returns (collected, index).
fn collect_head(lines : Array[Line], start : Int) -> (Array[String], Int) {
  let out : Array[String] = []
  let mut i = start
  while i < lines.length() {
    let l = lines[i]
    if l.content.is_empty() {
      out.push("")
      i = i + 1
    } else if l.content[0] == '#' {
      out.push(l.content)
      i = i + 1
    } else {
      break
    }
  }
  (out, i)
}

///|
/// Split " value  # comment" into (value_text, comment?). The comment must
/// be preceded by a space and outside quotes.
fn split_comment(s : String) -> (String, String?) {
  let cs = s.to_array()
  let mut in_sq = false
  let mut in_dq = false
  for i, c in cs {
    if in_sq {
      if c == '\'' {
        in_sq = false
      }
    } else if in_dq {
      if c == '\\' {
        // skip escaped char
      } else if c == '"' {
        in_dq = false
      }
    } else {
      match c {
        '\'' => in_sq = true
        '"' => in_dq = true
        '#' =>
          if i > 0 && cs[i - 1] == ' ' {
            let comment = trim_end_str(s[i:].to_owned())
            return (trim_end_str(s[:i].to_owned()), Some(comment))
          }
        _ => ()
      }
    }
  }
  (trim_end_str(s), None)
}

///|
fn parse_cvalue(
  ctx : CCtx,
  lines : Array[Line],
  start : Int,
  indent : Int,
) -> (CNode, Int) raise YamlError {
  if start >= lines.length() {
    return ({ val: Leaf(Null), head: [], tail: None, }, start)
  }
  let line = lines[start]
  if line.content == "---" || line.content == "..." {
    return ({ val: Leaf(Null), head: [], tail: None, }, start)
  }
  if is_seq_item(line) && line.indent == indent {
    parse_cseq(ctx, lines, start, indent)
  } else if find_top_colon(line.content) is Some(_) && line.indent == indent {
    parse_cmap(ctx, lines, start, indent)
  } else {
    parse_cinline_block(ctx, lines, start)
  }
}

///|
/// A scalar (or flow collection) standing on its own line(s) as a block value.
fn parse_cinline_block(
  ctx : CCtx,
  lines : Array[Line],
  start : Int,
) -> (CNode, Int) raise YamlError {
  let line = lines[start]
  let (s, tail) = split_comment(line.content)
  if s.is_empty() {
    return ({ val: Leaf(Null), head: [], tail: None, }, start + 1)
  }
  let (node, next) = parse_cinline(ctx, lines, start, s)
  node.tail = tail
  (node, next)
}

///|
fn parse_cseq(
  ctx : CCtx,
  lines : Array[Line],
  start : Int,
  indent : Int,
) -> (CNode, Int) raise YamlError {
  let items : Array[CNode] = []
  let mut i = start
  while true {
    let (head, j) = collect_head(lines, i)
    if j >= lines.length() {
      i = j
      flush_epilogue(ctx, head)
      break
    }
    let line = lines[j]
    if line.indent != indent || !is_seq_item(line) {
      i = j
      flush_epilogue(ctx, head)
      break
    }
    let rest0 = if line.content == "-" {
      ""
    } else {
      line.content[2:].to_owned()
    }
    let (rest, line_tail) = split_comment(rest0)
    let (node, next) = parse_centry_rest(ctx, lines, j, indent, rest)
    node.head = head + node.head
    node.tail = line_tail
    items.push(node)
    i = next
  }
  ({ val: Seq(items), head: [], tail: None, }, i)
}

///|
fn parse_cmap(
  ctx : CCtx,
  lines : Array[Line],
  start : Int,
  indent : Int,
) -> (CNode, Int) raise YamlError {
  let pairs : Array[(Yaml, CNode)] = []
  let merges : Array[CNode] = [] // deferred "<<" merge values
  let mut i = start
  while true {
    let (head, j) = collect_head(lines, i)
    if j >= lines.length() {
      i = j
      flush_epilogue(ctx, head)
      break
    }
    let line = lines[j]
    if line.indent != indent || is_seq_item(line) {
      i = j
      flush_epilogue(ctx, head)
      break
    }
    match find_top_colon(line.content) {
      None => {
        i = j
        flush_epilogue(ctx, head)
        break
      }
      Some(cpos) => {
        let key = parse_flow_scalar_key(line.content[:cpos].to_owned())
        let rest0 = line.content[cpos + 1:].to_owned()
        let (rest, line_tail) = split_comment(rest0)
        let (node, next) = parse_centry_rest(ctx, lines, j, indent, rest)
        node.head = head + node.head
        node.tail = line_tail
        if key is Str("<<") {
          merges.push(node)
        } else {
          pairs.push((key, node))
        }
        i = next
      }
    }
  }
  // merge keys: explicit keys always win; earlier merges win over later
  for v in merges {
    cmerge_into(pairs, v)
  }
  ({ val: Map(pairs), head: [], tail: None, }, i)
}

///|
/// Merge `v` (a mapping, or a sequence of mappings) into `pairs`; existing
/// keys are never overwritten.
fn cmerge_into(pairs : Array[(Yaml, CNode)], v : CNode) -> Unit {
  match v.val {
    Map(src) => cmerge_pairs(pairs, src)
    Seq(xs) =>
      for x in xs {
        cmerge_into(pairs, x)
      }
    _ => ()
  }
}

///|
fn cmerge_pairs(
  pairs : Array[(Yaml, CNode)],
  src : Array[(Yaml, CNode)],
) -> Unit {
  for pair in src {
    let (k, v) = pair
    let exists = pairs.iter().any(fn(p) { p.0 == k })
    if !exists {
      pairs.push((k, v))
    }
  }
}

///|
/// Parse the value that follows "key:" or "-" on the entry line `j`
/// (comment already stripped from `rest`). Mirrors parse_value_rest but
/// returns commented nodes.
fn parse_centry_rest(
  ctx : CCtx,
  lines : Array[Line],
  j : Int,
  indent : Int,
  rest0 : String,
) -> (CNode, Int) raise YamlError {
  let rest = strip_leading_spaces(rest0)
  // alias?
  if rest.has_prefix("*") {
    match lookup_calias(ctx, rest) {
      Some(node) => return (node, j + 1)
      None => raise YamlError("unknown alias: " + rest)
    }
  }
  // anchor?
  if rest.has_prefix("&") {
    match split_anchor(rest) {
      Some((name, remainder)) => {
        let (node, next) = parse_centry_rest(
          ctx,
          lines,
          j,
          indent,
          " " + remainder,
        )
        ctx.anchors.set(name, node)
        return (node, next)
      }
      None => ()
    }
  }
  if rest.is_empty() {
    // nested block on following lines (comments belong to the child)
    let (head, k) = collect_head(lines, j + 1)
    if k < lines.length() && lines[k].indent > indent {
      let (node, next) = parse_cvalue(ctx, lines, k, lines[k].indent)
      node.head = head + node.head
      return (node, next)
    }
    if k < lines.length() && lines[k].indent == indent && is_seq_item(lines[k]) {
      let (node, next) = parse_cseq(ctx, lines, k, indent)
      node.head = head + node.head
      return (node, next)
    }
    return ({ val: Leaf(Null), head: [], tail: None, }, j + 1)
  }
  if is_block_scalar_header(rest) {
    let (v, next) = parse_block_scalar(lines, j + 1, indent, rest)
    return ({ val: Leaf(v), head: [], tail: None, }, next)
  }
  // mapping whose first entry sits on this entry line: "- key: value"
  if find_top_colon(rest) is Some(_) &&
    !rest.has_prefix("[") &&
    !rest.has_prefix("{") {
    let child_indent = indent + 2
    let vlines : Array[Line] = [
      { indent: child_indent, content: rest, raw: lines[j].raw, },
    ]
    for k = j + 1; k < lines.length(); k = k + 1 {
      vlines.push(lines[k])
    }
    let (node, consumed) = parse_cmap(ctx, vlines, 0, child_indent)
    return (node, j + consumed)
  }
  // inline scalar / flow value
  let (node, next) = parse_cinline(ctx, lines, j, rest)
  (node, next)
}

///|
fn parse_cinline(
  ctx : CCtx,
  lines : Array[Line],
  j : Int,
  s : String,
) -> (CNode, Int) raise YamlError {
  if s.has_prefix("[") || s.has_prefix("{") {
    // flow collection, possibly spanning lines
    let sb = StringBuilder()
    let mut consumed = j
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
    let v = parse_flow(ctx_to_anchors(ctx), chars, pos)
    return ({ val: Leaf(v), head: [], tail: None, }, consumed)
  }
  if s.has_prefix("\"") {
    return (
      {
        val: Leaf(Str(parse_double_quoted(s.to_array(), { i: 0, }))),
        head: [],
        tail: None,
      },
      j + 1,
    )
  }
  if s.has_prefix("'") {
    return (
      {
        val: Leaf(Str(parse_single_quoted(s.to_array(), { i: 0, }))),
        head: [],
        tail: None,
      },
      j + 1,
    )
  }
  ({ val: Leaf(resolve_scalar(s)), head: [], tail: None, }, j + 1)
}

///|
fn ctx_to_anchors(ctx : CCtx) -> Ctx {
  let m : Map[String, Yaml] = Map([])
  // aliases inside flow collections resolve lazily from stored CNodes
  for pair in ctx.anchors {
    let (k, v) = pair
    m.set(k, cval_to_yaml(v.val))
  }
  { anchors: m, }
}

///|
fn lookup_calias(ctx : CCtx, s : String) -> CNode? {
  let name = s[1:].to_owned() |> trim_end_str
  ctx.anchors.get(name)
}

///|
fn flush_epilogue(ctx : CCtx, head : Array[String]) -> Unit {
  for c in head {
    ctx.epilogue.push(c)
  }
}

///|
/// Emit a commented value. `inline_first`: when true the first entry is
/// written on the current line (after "- " or nothing); when false the
/// first entry starts on a new line (block style under "key:").
fn emit_cval(
  es : ES,
  val : CVal,
  indent : Int,
  sb : StringBuilder,
  inline_first : Bool,
) -> Unit {
  match val {
    Leaf(y) => {
      emit_node(y, indent, sb, false)
      es.at_start = false
    }
    Seq(items) => emit_cseq(es, items, indent, sb, inline_first)
    Map(pairs) => emit_cmap(es, pairs, indent, sb, inline_first)
  }
}

///|
fn emit_tail(tail : String?, sb : StringBuilder) -> Unit {
  match tail {
    Some(c) => {
      sb.write_char(' ')
      sb.write_string(c)
    }
    None => ()
  }
}

///|
fn emit_cseq(
  es : ES,
  items : Array[CNode],
  indent : Int,
  sb : StringBuilder,
  inline_first : Bool,
) -> Unit {
  if items.is_empty() {
    sb.write_string("[]")
    return
  }
  for idx, item in items {
    if idx > 0 || !inline_first {
      line(es, sb, indent)
    }
    // head comments of a seq item go above the dash
    for c in item.head {
      cmt_line(es, sb, indent, c)
    }
    if item.head.length() > 0 {
      line(es, sb, indent)
    }
    sb.write_string("- ")
    match item.val {
      Seq(sub) =>
        if sub.is_empty() {
          sb.write_string("[]")
          emit_tail(item.tail, sb)
          es.at_start = false
        } else {
          emit_cval(es, Seq(sub), indent + 2, sb, true)
        }
      Map(pairs) =>
        if pairs.is_empty() {
          sb.write_string("{}")
          emit_tail(item.tail, sb)
          es.at_start = false
        } else {
          emit_cval(es, Map(pairs), indent + 2, sb, true)
        }
      Leaf(y) => {
        emit_node(y, indent + 2, sb, false)
        emit_tail(item.tail, sb)
        es.at_start = false
      }
    }
  }
}

///|
fn emit_cmap(
  es : ES,
  pairs : Array[(Yaml, CNode)],
  indent : Int,
  sb : StringBuilder,
  inline_first : Bool,
) -> Unit {
  if pairs.is_empty() {
    sb.write_string("{}")
    return
  }
  for idx, pair in pairs {
    let (k, node) = pair
    if idx > 0 || !inline_first {
      line(es, sb, indent)
    }
    // head comments (blank markers just produce empty lines)
    for c in node.head {
      cmt_line(es, sb, indent, c)
    }
    if node.head.length() > 0 {
      line(es, sb, indent)
    }
    sb.write_string(emit_key(k))
    sb.write_char(':')
    es.at_start = false
    match node.val {
      Seq(sub) =>
        if sub.is_empty() {
          sb.write_string(" []")
          emit_tail(node.tail, sb)
          es.at_start = false
        } else {
          emit_cval(es, Seq(sub), indent + 2, sb, false)
        }
      Map(sub) =>
        if sub.is_empty() {
          sb.write_string(" {}")
          emit_tail(node.tail, sb)
          es.at_start = false
        } else {
          emit_cval(es, Map(sub), indent + 2, sb, false)
        }
      Leaf(y) => {
        sb.write_char(' ')
        emit_node(y, indent + 2, sb, true)
        emit_tail(node.tail, sb)
        es.at_start = false
      }
    }
  }
}
