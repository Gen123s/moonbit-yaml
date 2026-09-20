///|
/// Demo: parse a docker-compose shaped YAML document and query it.
fn main {
  let input =
    #|version: "3.9"
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
  let doc : @yaml.Yaml? = try @yaml.parse(input) catch {
    _ => None
  } noraise {
    d => Some(d)
  }
  match doc {
    Some(doc) => {
      println("version   = " + debug_v(doc.get("version")))
      println("web.image = " + debug_v(doc.get_path("services.web.image")))
      println("db.image  = " + debug_v(doc.get_path("services.db.image")))
      match doc.get_path("services.web.depends_on") {
        Some(@yaml.Yaml::Arr(xs)) => {
          let mut s = "["
          for idx, x in xs {
            if idx > 0 {
              s = s + ", "
            }
            s = s + x.to_string()
          }
          println("depends_on = " + s + "]")
        }
        _ => println("depends_on = (none)")
      }
    }
    None => println("parse error")
  }
}

///|
fn debug_v(v : @yaml.Yaml?) -> String {
  match v {
    Some(x) => x.to_string()
    None => "(missing)"
  }
}
