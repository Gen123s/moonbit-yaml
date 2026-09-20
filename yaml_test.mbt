///| Blackbox tests: parse real-world shaped YAML documents.

///|
test "simple mapping" {
  let doc = @yaml.parse(
    (
      #|name: MoonBit
      #|version: 0.10
      #|stable: true
      #|desc: null
    ),
  )
  assert_eq(doc.get("name"), Some(@yaml.Yaml::Str("MoonBit")))
  assert_eq(doc.get("version"), Some(@yaml.Yaml::Float(0.1)))
  assert_eq(doc.get("stable"), Some(@yaml.Yaml::Bool(true)))
  assert_eq(doc.get("desc"), Some(@yaml.Yaml::Null))
}

///|
test "nested mapping" {
  let doc = @yaml.parse(
    (
      #|services:
      #|  web:
      #|    image: nginx:1.27
      #|    replicas: 3
      #|  db:
      #|    image: postgres:16
    ),
  )
  assert_eq(
    doc.get_path("services.web.image"),
    Some(@yaml.Yaml::Str("nginx:1.27")),
  )
  assert_eq(doc.get_path("services.web.replicas"), Some(@yaml.Yaml::Int(3)))
  assert_eq(
    doc.get_path("services.db.image"),
    Some(@yaml.Yaml::Str("postgres:16")),
  )
}

///|
test "block sequence" {
  let doc = @yaml.parse(
    (
      #|features:
      #|  - wasm
      #|  - native
      #|  - js
    ),
  )
  match doc.get("features") {
    Some(@yaml.Yaml::Arr(xs)) => {
      assert_eq(xs.length(), 3)
      assert_eq(xs[0], @yaml.Yaml::Str("wasm"))
      assert_eq(xs[2], @yaml.Yaml::Str("js"))
    }
    _ => fail("expected array")
  }
}

///|
test "sequence at same indent as key" {
  // legal YAML: sequence may sit at the same indentation as its key
  let doc = @yaml.parse(
    (
      #|services:
      #|- web
      #|- db
    ),
  )
  match doc.get("services") {
    Some(@yaml.Yaml::Arr(xs)) => assert_eq(xs.length(), 2)
    _ => fail("expected array")
  }
}

///|
test "sequence of mappings" {
  let doc = @yaml.parse(
    (
      #|steps:
      #|  - name: build
      #|    run: moon build
      #|  - name: test
      #|    run: moon test
    ),
  )
  match doc.get("steps") {
    Some(@yaml.Yaml::Arr(xs)) => {
      assert_eq(xs.length(), 2)
      assert_eq(xs[0].get("name"), Some(@yaml.Yaml::Str("build")))
      assert_eq(xs[1].get("run"), Some(@yaml.Yaml::Str("moon test")))
    }
    _ => fail("expected array of maps")
  }
}

///|
test "flow style" {
  let doc = @yaml.parse(
    (
      #|pos: {x: 1, y: 2}
      #|colors: [red, green, blue]
      #|empty_list: []
      #|empty_map: {}
    ),
  )
  assert_eq(doc.get_path("pos.x"), Some(@yaml.Yaml::Int(1)))
  assert_eq(doc.get_path("pos.y"), Some(@yaml.Yaml::Int(2)))
  match doc.get("colors") {
    Some(@yaml.Yaml::Arr(xs)) => {
      assert_eq(xs.length(), 3)
      assert_eq(xs[1], @yaml.Yaml::Str("green"))
    }
    _ => fail("expected array")
  }
  assert_eq(doc.get("empty_list"), Some(@yaml.Yaml::Arr([])))
  assert_eq(doc.get("empty_map"), Some(@yaml.Yaml::Map([])))
}

///|
test "quoted scalars" {
  let doc = @yaml.parse(
    (
      #|double: "hello\nworld"
      #|single: 'it''s'
      #|not_number: "123"
      #|url: https://example.com/a:b
    ),
  )
  assert_eq(doc.get("double"), Some(@yaml.Yaml::Str("hello\nworld")))
  assert_eq(doc.get("single"), Some(@yaml.Yaml::Str("it's")))
  assert_eq(doc.get("not_number"), Some(@yaml.Yaml::Str("123")))
  assert_eq(doc.get("url"), Some(@yaml.Yaml::Str("https://example.com/a:b")))
}

///|
test "scalar resolution" {
  let doc = @yaml.parse(
    (
      #|dec: 42
      #|neg: -17
      #|hex: 0x1F
      #|oct: 0o17
      #|underscores: 1_000_000
      #|float: 1.5e3
      #|t1: True
      #|t2: FALSE
      #|n1: ~
    ),
  )
  assert_eq(doc.get("dec"), Some(@yaml.Yaml::Int(42)))
  assert_eq(doc.get("neg"), Some(@yaml.Yaml::Int(-17)))
  assert_eq(doc.get("hex"), Some(@yaml.Yaml::Int(31)))
  assert_eq(doc.get("oct"), Some(@yaml.Yaml::Int(15)))
  assert_eq(doc.get("underscores"), Some(@yaml.Yaml::Int(1000000)))
  assert_eq(doc.get("float"), Some(@yaml.Yaml::Float(1500.0)))
  assert_eq(doc.get("t1"), Some(@yaml.Yaml::Bool(true)))
  assert_eq(doc.get("t2"), Some(@yaml.Yaml::Bool(false)))
  assert_eq(doc.get("n1"), Some(@yaml.Yaml::Null))
}

///|
test "literal block scalar" {
  let doc = @yaml.parse(
    (
      #|script: |
      #|  echo hello
      #|  echo world
      #|next: 1
    ),
  )
  assert_eq(
    doc.get("script"),
    Some(@yaml.Yaml::Str("echo hello\necho world\n")),
  )
  assert_eq(doc.get("next"), Some(@yaml.Yaml::Int(1)))
}

///|
test "folded block scalar" {
  let doc = @yaml.parse(
    (
      #|desc: >
      #|  this is a long
      #|  sentence folded
      #|
      #|  into paragraphs
    ),
  )
  assert_eq(
    doc.get("desc"),
    Some(@yaml.Yaml::Str("this is a long sentence folded\ninto paragraphs\n")),
  )
}

///|
test "strip chomping" {
  let doc = @yaml.parse(
    (
      #|code: |-
      #|  line1
      #|  line2
    ),
  )
  assert_eq(doc.get("code"), Some(@yaml.Yaml::Str("line1\nline2")))
}

///|
test "comments" {
  let doc = @yaml.parse(
    (
      #|# leading comment
      #|name: app  # inline comment
      #|# another comment
      #|port: 8080
    ),
  )
  assert_eq(doc.get("name"), Some(@yaml.Yaml::Str("app")))
  assert_eq(doc.get("port"), Some(@yaml.Yaml::Int(8080)))
}

///|
test "docker compose shaped document" {
  let doc = @yaml.parse(
    (
      #|version: "3.9"
      #|services:
      #|  web:
      #|    build: .
      #|    ports:
      #|      - "8080:80"
      #|    environment:
      #|      MODE: production
      #|      DEBUG: "false"
      #|    depends_on:
      #|      - db
      #|  db:
      #|    image: postgres:16
      #|    volumes:
      #|      - db-data:/var/lib/postgresql/data
      #|volumes:
      #|  db-data:
    ),
  )
  assert_eq(doc.get("version"), Some(@yaml.Yaml::Str("3.9")))
  assert_eq(
    doc.get_path("services.web.environment.MODE"),
    Some(@yaml.Yaml::Str("production")),
  )
  match doc.get_path("services.web.ports") {
    Some(@yaml.Yaml::Arr(xs)) => assert_eq(xs[0], @yaml.Yaml::Str("8080:80"))
    _ => fail("expected ports array")
  }
  assert_eq(
    doc.get_path("services.db.image"),
    Some(@yaml.Yaml::Str("postgres:16")),
  )
}
