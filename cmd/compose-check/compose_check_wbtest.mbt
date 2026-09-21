///|
test "compose-doctor passes a healthy compose file" {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let doc = @yaml.parse(GOOD)
  check(doc, errors, warnings)
  assert_eq(errors.length(), 0)
  assert_eq(warnings.length(), 0)
}

///|
test "compose-doctor finds every planted defect in the broken file" {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let doc = @yaml.parse(BAD)
  check(doc, errors, warnings)
  // web: no image, bad port "8080:nginx", port 99999, dangling depends_on
  // db: no image; cache: no image
  assert_eq(errors.length(), 5)
  // unknown top-level key 'workers'
  assert_eq(warnings.length(), 1)
}

///|
test "port_ok accepts only numeric HOST:CONTAINER pairs" {
  assert_true(port_ok("8080:80"))
  assert_true(port_ok("80:443"))
  assert_false(port_ok("8080:nginx"))
  assert_false(port_ok(":80"))
  assert_false(port_ok("8080:"))
  assert_false(port_ok("8080"))
}
