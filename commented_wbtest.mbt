///|
/// Round-trip a comment-rich document and edit one value: every comment
/// must survive and the edit must be visible.
test "comment-preserving round-trip: comments survive an edit" {
  let input =
    #|# top-level doc
    #|version: "3.9"
    #|services:
    #|  web:
    #|    image: nginx:1.27  # main image
    #|    ports:
    #|      - "8080:80"
    #|  db:
    #|    image: postgres:16
    #|
  let doc = parse_commented(input)
  // edit web.image -> caddy:2
  assert_true(doc.root.set_path("services.web.image", Str("caddy:2")))
  let out = doc.to_yaml_string()
  // every comment survived
  assert_true(out.contains("top-level doc"))
  assert_true(out.contains("# main image"))
  // the edit landed
  let reparsed = parse(out)
  assert_eq(reparsed.get_path("services.web.image"), Some(Yaml::Str("caddy:2")))
  // unedited values are untouched
  assert_eq(
    reparsed.get_path("services.db.image"),
    Some(Yaml::Str("postgres:16")),
  )
}

///|
test "parse_commented agrees with parse on values" {
  let input =
    #|# anchored config
    #|base: &b
    #|  retries: 3
    #|service:
    #|  timeout: 30
    #|merged:
    #|  <<: *b
    #|
  let c = parse_commented(input)
  let plain = parse(input)
  assert_true(c.to_yaml() == plain)
}

///|
test "get_path navigates the commented tree" {
  let input =
    #|a:
    #|  b:
    #|    c: hello  # note
    #|
  let doc = parse_commented(input)
  match doc.root.get_path("a.b.c") {
    Some(node) =>
      match node.val {
        Leaf(Str(s)) => assert_eq(s, "hello")
        _ => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "blank lines and structure comments are preserved" {
  let input =
    #|# header comment
    #|one: 1
    #|
    #|# between sections
    #|two: 2  # inline note
    #|three: 3
    #|# trailing comment
    #|
  let out = parse_commented(input).to_yaml_string()
  assert_true(out.contains("# header comment"))
  assert_true(out.contains("# between sections"))
  assert_true(out.contains("# inline note"))
  assert_true(out.contains("# trailing comment"))
  // semantic equality survives the round trip
  let reparsed = parse(out)
  assert_eq(reparsed.get("one"), Some(Yaml::Int(1L)))
  assert_eq(reparsed.get("two"), Some(Yaml::Int(2L)))
  assert_eq(reparsed.get("three"), Some(Yaml::Int(3L)))
}
