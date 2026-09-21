///|
/// compose-doctor: a docker-compose.yml health checker built on Gen123s/yaml.
/// Demonstrates the library being used by a real application: parse a
/// docker-compose document, then run structural checks over the value tree.
///
/// Usage: moon run cmd/compose-check [good|bad]

///|
/// A healthy compose file.
const GOOD : String =
  (#|version: "3.9"
  #|services:
  #|  web:
  #|    image: nginx:1.27
  #|    ports:
  #|      - "8080:80"
  #|    depends_on:
  #|      - db
  #|  db:
  #|    image: postgres:16
  #|
  )

///|
/// A broken compose file: missing image, bad port, dangling depends_on.
const BAD : String =
  (#|version: "3.9"
  #|services:
  #|  web:
  #|    ports:
  #|      - "8080:nginx"
  #|      - 99999
  #|    depends_on:
  #|      - cache
  #|  db:
  #|    command: postgres
  #|  cache: {}
  #|workers:
  #|  - x
  #|
  )

///|
fn main {
  // Check both bundled documents: a healthy one and a broken one.
  println("compose-doctor — docker-compose.yml health checker")
  println("===================================================")
  println("")
  run_check("docker-compose.good.yml", GOOD)
  println("")
  run_check("docker-compose.broken.yml", BAD)
}

///|
fn run_check(label : String, source : String) -> Unit {
  println("checking \{label} ...")
  println("")
  let doc : @yaml.Yaml? = try @yaml.parse(source) catch {
    err => {
      println("parse error: \{err}")
      return
    }
  } noraise {
    d => Some(d)
  }
  match doc {
    Some(doc) => {
      let errors : Array[String] = []
      let warnings : Array[String] = []
      check(doc, errors, warnings)
      if warnings.is_empty() && errors.is_empty() {
        println("PASS: docker-compose file looks healthy.")
      } else {
        for w in warnings {
          println("WARN : \{w}")
        }
        for e in errors {
          println("ERROR: \{e}")
        }
        println("")
        println("FAIL: \{errors.length()} error(s), \{warnings.length()} warning(s).")
      }
    }
    None => println("parse error")
  }
}

///|
fn check(
  doc : @yaml.Yaml,
  errors : Array[String],
  warnings : Array[String]
) -> Unit {
  // top-level must be a mapping
  let services : @yaml.Yaml? = match doc {
    @yaml.Yaml::Map(_) => doc.get("services")
    _ => {
      errors.push("top level of the file must be a mapping")
      return
    }
  }
  // warn about unknown top-level keys
  match doc {
    @yaml.Yaml::Map(kvs) =>
      for (k, _) in kvs {
        match k {
          @yaml.Yaml::Str("version") |
          @yaml.Yaml::Str("services") |
          @yaml.Yaml::Str("volumes") |
          @yaml.Yaml::Str("networks") |
          @yaml.Yaml::Str("configs") |
          @yaml.Yaml::Str("secrets") |
          @yaml.Yaml::Str("name") => ()
          @yaml.Yaml::Str(other) =>
            warnings.push("unknown top-level key '\{other}'")
          _ => ()
        }
      }
    _ => ()
  }
  // services must be a non-empty mapping
  let kvs : Array[(@yaml.Yaml, @yaml.Yaml)] = match services {
    None => {
      errors.push("missing top-level 'services' section")
      return
    }
    Some(@yaml.Yaml::Map(kvs)) => kvs
    Some(_) => {
      errors.push("'services' must be a mapping of service name -> config")
      return
    }
  }
  if kvs.is_empty() {
    errors.push("'services' section is empty")
    return
  }
  // first pass: collect service names
  let names : Array[String] = []
  for (k, _) in kvs {
    match k {
      @yaml.Yaml::Str(name) => names.push(name)
      _ => errors.push("service name must be a string")
    }
  }
  // second pass: check each service
  for (k, v) in kvs {
    match k {
      @yaml.Yaml::Str(name) => check_service(name, v, names, errors, warnings)
      _ => ()
    }
  }
}

///|
fn check_service(
  name : String,
  svc : @yaml.Yaml,
  names : Array[String],
  errors : Array[String],
  warnings : Array[String]
) -> Unit {
  // service config must be a mapping
  match svc {
    @yaml.Yaml::Map(_) => ()
    _ => {
      errors.push("service '\{name}': config must be a mapping")
      return
    }
  }
  // must specify image or build
  match (svc.get("image"), svc.get("build")) {
    (None, None) =>
      errors.push(
        "service '\{name}': neither 'image' nor 'build' is specified",
      )
    (Some(v), None) =>
      if v is (@yaml.Yaml::Null | @yaml.Yaml::Str("")) {
        warnings.push("service '\{name}': 'image' is empty")
      }
    _ => ()
  }
  // ports format
  match svc.get("ports") {
    Some(@yaml.Yaml::Arr(items)) =>
      for item in items {
        match item {
          @yaml.Yaml::Str(p) =>
            if !port_ok(p) {
              errors.push(
                "service '\{name}': bad port mapping \"\{p}\" (expected \"HOST:CONTAINER\")",
              )
            }
          @yaml.Yaml::Int(n) =>
            if n < 0L || n > 65535L {
              errors.push(
                "service '\{name}': port \{n} out of range (0-65535)",
              )
            }
          _ =>
            errors.push("service '\{name}': port entry must be a string or int")
        }
      }
    Some(_) => errors.push("service '\{name}': 'ports' must be a list")
    None => ()
  }
  // depends_on references must exist
  match svc.get("depends_on") {
    Some(@yaml.Yaml::Arr(items)) =>
      for item in items {
        match item {
          @yaml.Yaml::Str(dep) =>
            if !names.contains(dep) {
              errors.push(
                "service '\{name}': depends_on '\{dep}' is not defined",
              )
            }
          _ =>
            errors.push(
              "service '\{name}': depends_on entries must be service names",
            )
        }
      }
    Some(_) => errors.push("service '\{name}': 'depends_on' must be a list")
    None => ()
  }
}

///|
fn port_ok(p : String) -> Bool {
  // "HOST:CONTAINER" with both parts non-empty and numeric
  let parts = p.split(":").collect()
  if parts.length() != 2 {
    return false
  }
  match (parts[0], parts[1]) {
    (h, c) => is_port_num(h) && is_port_num(c)
  }
}

///|
fn is_port_num(s : StringView) -> Bool {
  if s.is_empty() {
    return false
  }
  for ch in s {
    if ch < '0' || ch > '9' {
      return false
    }
  }
  true
}
