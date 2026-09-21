# moonbit-yaml

YAML 1.2 parser and emitter for MoonBit.

**Status: early development** (MoonBit 黑客松 2026 参赛项目)

`moonbit-yaml` provides a YAML 1.2 conformance-oriented implementation for
the MoonBit ecosystem — pure MoonBit, with round-trip emission and located
errors, targeting configuration toolchains (docker-compose, Kubernetes,
GitHub Actions, CI/CD, OpenAPI...). The ecosystem already has TOML
(bobzhang/toml), XML (Milky2018/xml) and built-in JSON;
[moonbit-community/yaml](https://mooncakes.io/docs/moonbit-community/yaml)
covers a simplified YAML subset with JSON output. This project takes the
conformance track: full YAML 1.2 core-schema support validated against the
official yaml-test-suite (see "Differences from moonbit-community/yaml" below).

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

## Differences from moonbit-community/yaml

[moonbit-community/yaml](https://mooncakes.io/docs/moonbit-community/yaml)
targets a simplified YAML subset with JSON conversion. This project
differentiates on:

- Native `Yaml` value model (no JSON-flattening loss of structure)
- Round-trip emission (`parse -> to_yaml_string`) with comment preservation (planned)
- Located errors (`ParseError` with line/column and snippet)
- Conformance validated against the official yaml-test-suite

A per-feature comparison against actual upstream behavior will be published
here as measured results come in.

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
