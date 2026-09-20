///| Blackbox tests for anchors, aliases, merge keys, multi-document streams
/// and the emitter.

///|
test "anchor and alias inline" {
  let doc = @yaml.parse(
    (
      #|defaults: &def
      #|  timeout: 30
      #|  retries: 3
      #|service_a: *def
      #|service_b: *def
    ),
  )
  assert_eq(doc.get_path("defaults.timeout"), Some(@yaml.Yaml::Int(30)))
  assert_eq(doc.get_path("service_a.retries"), Some(@yaml.Yaml::Int(3)))
  assert_eq(doc.get_path("service_b.timeout"), Some(@yaml.Yaml::Int(30)))
}

///|
test "anchor on inline scalar" {
  let doc = @yaml.parse(
    (
      #|name: &n moonbit
      #|alias: *n
    ),
  )
  assert_eq(doc.get("alias"), Some(@yaml.Yaml::Str("moonbit")))
}

///|
test "anchor on sequence" {
  let doc = @yaml.parse(
    (
      #|base: &items
      #|  - a
      #|  - b
      #|copy: *items
    ),
  )
  match doc.get("copy") {
    Some(@yaml.Yaml::Arr(xs)) => {
      assert_eq(xs.length(), 2)
      assert_eq(xs[0], @yaml.Yaml::Str("a"))
    }
    _ => fail("expected array")
  }
}

///|
test "merge key inherits defaults" {
  let doc = @yaml.parse(
    (
      #|defaults: &def
      #|  adapter: postgres
      #|  pool: 5
      #|  host: localhost
      #|production:
      #|  <<: *def
      #|  host: prod.example.com
      #|  pool: 20
    ),
  )
  assert_eq(
    doc.get_path("production.adapter"),
    Some(@yaml.Yaml::Str("postgres")),
  )
  // explicit key overrides the merged value
  assert_eq(
    doc.get_path("production.host"),
    Some(@yaml.Yaml::Str("prod.example.com")),
  )
  assert_eq(doc.get_path("production.pool"), Some(@yaml.Yaml::Int(20)))
}

///|
test "merge key with list of maps" {
  let doc = @yaml.parse(
    (
      #|a: &a
      #|  x: 1
      #|b: &b
      #|  y: 2
      #|combined:
      #|  <<: [*a, *b]
      #|  z: 3
    ),
  )
  assert_eq(doc.get_path("combined.x"), Some(@yaml.Yaml::Int(1)))
  assert_eq(doc.get_path("combined.y"), Some(@yaml.Yaml::Int(2)))
  assert_eq(doc.get_path("combined.z"), Some(@yaml.Yaml::Int(3)))
}

///|
test "multi document stream" {
  let docs = @yaml.parse_documents(
    (
      #|---
      #|name: first
      #|---
      #|name: second
      #|value: 2
      #|...
    ),
  )
  assert_eq(docs.length(), 2)
  assert_eq(docs[0].get("name"), Some(@yaml.Yaml::Str("first")))
  assert_eq(docs[1].get("name"), Some(@yaml.Yaml::Str("second")))
  assert_eq(docs[1].get("value"), Some(@yaml.Yaml::Int(2)))
}

///|
test "multi document without leading marker" {
  let docs = @yaml.parse_documents(
    (
      #|one: 1
      #|---
      #|two: 2
    ),
  )
  assert_eq(docs.length(), 2)
  assert_eq(docs[0].get("one"), Some(@yaml.Yaml::Int(1)))
  assert_eq(docs[1].get("two"), Some(@yaml.Yaml::Int(2)))
}

///|
test "emitter simple mapping" {
  let doc = @yaml.Yaml::Map([
    (Str("name"), Str("moonbit")),
    (Str("version"), Str("0.1.0")),
    (Str("stable"), Bool(true)),
  ])
  inspect(
    @yaml.to_yaml_string(doc),
    content=(
      #|name: moonbit
      #|version: 0.1.0
      #|stable: true
    ),
  )
}

///|
test "emitter nested structure" {
  let doc = @yaml.Yaml::Map([
    (
      Str("services"),
      Map([
        (
          Str("web"),
          Map([(Str("image"), Str("nginx:1.27")), (Str("replicas"), Int(3))]),
        ),
      ]),
    ),
    (Str("volumes"), Arr([])),
  ])
  inspect(
    @yaml.to_yaml_string(doc),
    content=(
      #|services:
      #|  web:
      #|    image: nginx:1.27
      #|    replicas: 3
      #|volumes: []
    ),
  )
}

///|
test "emitter sequence of mappings" {
  let doc = @yaml.Yaml::Map([
    (
      Str("steps"),
      Arr([
        Map([(Str("name"), Str("build")), (Str("run"), Str("moon build"))]),
        Map([(Str("name"), Str("test")), (Str("run"), Str("moon test"))]),
      ]),
    ),
  ])
  inspect(
    @yaml.to_yaml_string(doc),
    content=(
      #|steps:
      #|  - name: build
      #|    run: moon build
      #|  - name: test
      #|    run: moon test
    ),
  )
}

///|
test "emitter quotes ambiguous scalars" {
  let doc = @yaml.Yaml::Map([
    (Str("number_like"), Str("123")),
    (Str("bool_like"), Str("true")),
    (Str("has_colon"), Str("a: b")),
    (Str("plain"), Str("hello world")),
    (Str("multiline"), Str("line1\nline2")),
  ])
  inspect(
    @yaml.to_yaml_string(doc),
    content=(
      #|number_like: "123"
      #|bool_like: "true"
      #|has_colon: "a: b"
      #|plain: hello world
      #|multiline: "line1\nline2"
    ),
  )
}

///|
test "emitter float format" {
  let doc = @yaml.Yaml::Map([
    (Str("a"), Float(1.5)),
    (Str("b"), Float(1500.0)),
    (Str("c"), Int(42)),
  ])
  inspect(
    @yaml.to_yaml_string(doc),
    content=(
      #|a: 1.5
      #|b: 1500.0
      #|c: 42
    ),
  )
}

///|
test "round trip parse then emit then parse" {
  let input =
    #|name: moonbit-yaml
    #|features:
    #|  - yaml
    #|  - parser
    #|  - emitter
    #|meta:
    #|  version: 0.1.0
    #|  pure: true
    #|  lines: 4600
  let doc1 = @yaml.parse(input)
  let emitted = @yaml.to_yaml_string(doc1)
  let doc2 = @yaml.parse(emitted)
  assert_eq(doc1, doc2)
}

///|
test "round trip anchors expanded" {
  let input =
    #|base: &b
    #|  x: 1
    #|derived:
    #|  <<: *b
    #|  y: 2
  let doc = @yaml.parse(input)
  let emitted = @yaml.to_yaml_string(doc)
  // re-parsing the emitted text must preserve the merged semantics
  let doc2 = @yaml.parse(emitted)
  assert_eq(doc2.get_path("derived.x"), Some(@yaml.Yaml::Int(1)))
  assert_eq(doc2.get_path("derived.y"), Some(@yaml.Yaml::Int(2)))
}

///|
test "unknown alias raises" {
  let result : @yaml.Yaml? = try
    @yaml.parse(
      (
        #|a: *missing
      ),
    )
  catch {
    _ => None
  } noraise {
    d => Some(d)
  }
  assert_eq(result, None)
}
