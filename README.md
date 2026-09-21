# moonbit-yaml

English | [简体中文](README.zh-CN.md)

YAML 1.2 parser and emitter for MoonBit.

**Status: early development**

`moonbit-yaml` provides a YAML 1.2 conformance-oriented implementation
the MoonBit ecosystem — pure MoonBit, with round-trip emission and located
errors, targeting configuration toolchains (docker-compose, Kubernetes,
GitHub Actions, CI/CD, OpenAPI...). The ecosystem already has TOML
(bobzhang/toml), XML (Milky2018/xml) and built-in JSON; a simplified YAML
subset is also covered by
[moonbit-community/yaml](https://mooncakes.io/docs/moonbit-community/yaml).
This project takes the conformance track: full YAML 1.2 core-schema support
validated against the official yaml-test-suite.

## Features (planned / in progress)

- [x] YAML value model (`Yaml` enum: null / bool / int / float / string / array / map)
- [x] Scanner-free recursive descent parser for block style mappings
- [x] Block sequences (`- item`)
- [x] Flow style collections (`{a: 1}`, `[1, 2]`), nested and multi-line
- [x] Single / double quoted scalars with escapes (`\n`, `\uXXXX`, ...)
- [x] Multi-line scalars (literal `|`, folded `>`, chomping `-` / `+`)
- [x] Core schema scalar resolution (`true/false/null/0x1F/0o17/1_000/1.5e3/.inf/.nan`)
- [x] Anchors & aliases (`&a`, `*a`), including inside flow collections
- [x] Merge keys (`<<: *base`, `<<: [*a, *b]`)
- [x] Multi-document streams (`---` / `...`)
- [x] Emitter (`to_yaml_string`) with round-trip guarantee and safe quoting
- [x] **Comment-preserving parse/emit** (`parse_commented` / `CNode`):
  edit a value, write the file back, every comment and blank line survives
- [ ] yaml-test-suite conformance harness
- [ ] Streaming/event API

## The highlight: edit YAML without destroying it

Standard parse → modify → serialize loses all comments. `parse_commented`
keeps them attached to the tree, so round-tripping a config file after an
edit preserves every comment, blank line, anchor and merge key:

```moonbit
let doc = @yaml.parse_commented(source)
doc.root.set_path("services.web.image", Str("caddy:2"))
print(doc.to_yaml_string()) // comments intact, only the value changed
```

## Usage

### Install

```bash
# In your MoonBit project directory (after the package is published):
moon add Gen123s/yaml
```

Then add `import "Gen123s/yaml"` (as `@yaml`) to your `moon.pkg`.

### Parse a YAML document

```moonbit
let doc = @yaml.parse("name: MoonBit\nfeatures:\n  - wasm\n  - native\n")
inspect(doc.get("name"), content="Some(Str(MoonBit))")
```

### Query nested paths

```moonbit
let image = doc.get_path("services.web.image")  // dotted path lookup
```

### Emit back to YAML (round-trip)

```moonbit
let text = @yaml.to_yaml_string(doc)            // Yaml -> YAML text
```

### Anchors, merge keys, multi-document streams

```moonbit
// Supported: &anchor / *alias, `<<:` merge keys, `---` document streams —
// see the test suites under yaml_test.mbt / features_test.mbt for examples.
```

### Demo CLI

Parse a real docker-compose file from the command line:

```bash
moon run cmd/main
```

### Example app: compose-doctor

`cmd/compose-check` is a small docker-compose.yml health checker built **on
top of this library** — a live example of consuming the `Yaml` value model:

```bash
moon run cmd/compose-check
```

It checks a healthy compose document (PASS) and a broken one, reporting
missing `image`/`build`, malformed port mappings, port range violations,
dangling `depends_on` references, and unknown top-level keys.

## Development

```bash
moon check          # type check
moon test           # run tests
moon fmt --check    # format check
moon run cmd/main   # demo CLI
```

CI runs all of the above with `--deny-warn` on every push to `main` and on
pull requests (see `.github/workflows/ci.yml`).

## References

This is a port-style reimplementation informed by mature YAML
implementations in other ecosystems:

- **PyYAML** (https://github.com/yaml/pyyaml, MIT) — scanner/parser architecture
- **libyaml** (https://github.com/yaml/libyaml, MIT) — event-based design
- **YAML 1.2 spec** (https://yaml.org/spec/1.2.2/)
- **yaml-test-suite** (https://github.com/yaml/yaml-test-suite, MIT) — conformance tests

## License

Apache-2.0 (see LICENSE).
