# moonbit-yaml

YAML 1.2 parser and emitter for MoonBit.

**Status: early development** (MoonBit 黑客松 2026 参赛项目)

`moonbit-yaml` aims to provide the MoonBit ecosystem with a complete, pure
MoonBit implementation of YAML — the most widely used human-written
configuration format (docker-compose, Kubernetes, GitHub Actions, CI/CD,
OpenAPI...). Today the ecosystem has TOML (bobzhang/toml), XML (Milky2018/xml)
and built-in JSON, but no YAML parser. This project fills that gap.

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
- [ ] yaml-test-suite conformance harness
- [ ] Streaming/event API

## Usage

```moonbit
let doc = @yaml.parse("name: MoonBit\nfeatures:\n  - wasm\n  - native\n")
inspect(doc.get("name"), content="Some(Str(MoonBit))")
```

Query nested paths, round-trip back to text:

```moonbit
let image = doc.get_path("services.web.image")  // dotted path lookup
let text = @yaml.to_yaml_string(doc)            // emit back to YAML
```

Run the demo CLI:

```bash
moon run cmd/main
```

## Development

```bash
moon check   # type check
moon test    # run tests
moon fmt     # format
```

## References

This is a port-style reimplementation informed by mature YAML
implementations in other ecosystems:

- **PyYAML** (https://github.com/yaml/pyyaml, MIT) — scanner/parser architecture
- **libyaml** (https://github.com/yaml/libyaml, MIT) — event-based design
- **YAML 1.2 spec** (https://yaml.org/spec/1.2.2/)
- **yaml-test-suite** (https://github.com/yaml/yaml-test-suite, MIT) — conformance tests

## License

Apache-2.0 (see LICENSE). This project is a contest entry of the
2026 MoonBit 黑客松 (September round).
