///| The YAML value model and the public API of the library.

///|
/// A YAML document node.
///
/// Mappings are stored as an ordered list of key/value pairs, which preserves
/// document order and allows non-scalar keys (permitted by the YAML spec).
pub(all) enum Yaml {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  Str(String)
  Arr(Array[Yaml])
  Map(Array[(Yaml, Yaml)])
} derive(Eq, Debug)

///|
pub extend Yaml with Eq::{equal, not_equal}

///|
pub extend Yaml with Debug::{to_repr}

///|
/// Human-readable debug rendering (constructor style).
pub impl Show for Yaml with fn output(self, logger) {
  match self {
    Null => logger <+ "Null"
    Bool(b) => logger <+ "Bool(\{b})"
    Int(i) => logger <+ "Int(\{i})"
    Float(f) => logger <+ "Float(\{f})"
    Str(s) => logger <+ "Str(\{s})"
    Arr(xs) => {
      logger <+ "Arr(["
      for i, x in xs {
        if i > 0 {
          logger <+ ", "
        }
        Show::output(x, logger)
      }
      logger <+ "])"
    }
    Map(pairs) => {
      logger <+ "Map(["
      for i, pair in pairs {
        let (k, v) = pair
        if i > 0 {
          logger <+ ", "
        }
        Show::output(k, logger)
        logger <+ " -> "
        Show::output(v, logger)
      }
      logger <+ "])"
    }
  }
}

///|
pub extend Yaml with Show::{to_string, output}

///|
pub(all) suberror YamlError {
  YamlError(String)
} derive(Debug)

///|
pub extend YamlError with Debug::{to_repr}

///|
pub impl Show for YamlError with fn output(self, logger) {
  match self {
    YamlError(s) => logger <+ "YamlError(\{s})"
  }
}

///|
pub extend YamlError with Show::{to_string, output}

///|
/// Parse a YAML document (block + flow styles, anchors, merge keys) into a
/// Yaml value. For multi-document streams, only the first document is
/// returned; see `parse_documents`.
pub fn parse(input : String) -> Yaml raise YamlError {
  let docs = parse_documents(input)
  if docs.is_empty() {
    return Null
  }
  docs[0]
}

///|
/// Parse every document of a YAML stream (separated by `---` / `...`)
/// into an array of Yaml values. Anchors do not cross document boundaries.
pub fn parse_documents(input : String) -> Array[Yaml] raise YamlError {
  let lines = preprocess(input)
  // split into document chunks at top-level markers
  let chunks : Array[Array[Line]] = []
  let cur : Array[Line] = []
  for l in lines {
    if l.indent == 0 && (l.content == "---" || l.content == "...") {
      if cur.length() > 0 {
        chunks.push(cur.copy())
        cur.clear()
      }
      continue
    }
    cur.push(l)
  }
  if cur.length() > 0 {
    chunks.push(cur)
  }
  let docs : Array[Yaml] = []
  for chunk in chunks {
    let ctx : Ctx = { anchors: {}, }
    let j = skip_ignorable(chunk, 0)
    if j >= chunk.length() {
      continue // whitespace-only chunk
    }
    let (v, _) = parse_block(ctx, chunk, j, chunk[j].indent)
    docs.push(v)
  }
  docs
}

///|
/// Convenience: parse then access a string key of the top-level mapping.
pub fn Yaml::get(self : Yaml, key : String) -> Yaml? {
  match self {
    Map(pairs) => {
      for pair in pairs {
        let (k, v) = pair
        match k {
          Str(s) => if s == key { return Some(v) }
          _ => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Access a nested path like "services.web.image".
pub fn Yaml::get_path(self : Yaml, path : String) -> Yaml? {
  let parts = path.split(".")
  let mut cur : Yaml = self
  for part in parts {
    match cur.get(part.to_owned()) {
      Some(v) => cur = v
      None => return None
    }
  }
  Some(cur)
}

///|
pub fn Yaml::as_str(self : Yaml) -> String? {
  match self {
    Str(s) => Some(s)
    _ => None
  }
}

///|
pub fn Yaml::as_int(self : Yaml) -> Int64? {
  match self {
    Int(i) => Some(i)
    _ => None
  }
}

///|
pub fn Yaml::as_float(self : Yaml) -> Double? {
  match self {
    Float(f) => Some(f)
    Int(i) => Some(i.to_double())
    _ => None
  }
}

///|
pub fn Yaml::as_bool(self : Yaml) -> Bool? {
  match self {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
pub fn Yaml::as_array(self : Yaml) -> Array[Yaml]? {
  match self {
    Arr(xs) => Some(xs)
    _ => None
  }
}
