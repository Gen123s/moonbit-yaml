# moonbit-yaml

[English](README.md) | 简体中文

MoonBit 的 YAML 1.2 解析与序列化库。

**状态：早期开发中**（2026 MoonBit 九月黑客松参赛项目）

## 这个项目有什么用？

一句话：**让 MoonBit 程序能够读写 YAML**——当今使用最广的人类可读配置格式。

你每天接触的这些文件几乎全是 YAML：

- `docker-compose.yml`（容器编排）
- Kubernetes manifests（云原生部署）
- `.github/workflows/*.yml`（GitHub Actions / CI/CD 流水线）
- OpenAPI / Swagger（API 描述）
- 各类应用的 `config.yaml`

MoonBit 生态已有 TOML（bobzhang/toml）、XML（Milky2018/xml）和内置 JSON，
但 YAML 的解析能力只有
[moonbit-community/yaml](https://mooncakes.io/docs/moonbit-community/yaml)
覆盖的"简化子集"。本项目的定位是**规范兼容路线**：完整支持 YAML 1.2
core schema，并以官方 yaml-test-suite 一致性测试为验收基准（见下文
"与 moonbit-community/yaml 的差异"）。

典型用途：

1. **CI/CD 工具链**：用 MoonBit 写的 DevOps 工具需要解析、校验、生成
   GitHub Actions 工作流文件。
2. **云原生运维**：读写 docker-compose / Kubernetes manifest，做配置审计。
3. **应用配置**：MoonBit 服务端 / CLI 应用从 `config.yaml` 加载结构化配置。
4. **文档处理**：静态站点生成器解析 Markdown 的 YAML Front Matter。

仓库里自带一个真实用例 **compose-doctor**（见下文），它就是一个
"用这个库写出来的" docker-compose 配置体检工具。

## 功能特性（已完成 / 计划中）

- [x] YAML 值模型（`Yaml` 枚举：null / bool / int / float / string / array / map）
- [x] 块式映射的无 scanner 递归下降解析
- [x] 块序列（`- item`）
- [x] 流式集合（`{a: 1}`、`[1, 2]`），支持嵌套与跨行
- [x] 单/双引号标量及转义（`\n`、`\uXXXX` 等）
- [x] 多行标量（literal `|`、folded `>`，`-` / `+` chomping）
- [x] Core schema 标量解析（`true/false/null/0x1F/0o17/1_000/1.5e3/.inf/.nan`）
- [x] 锚点与别名（`&a`、`*a`），含流式集合内的锚点
- [x] 合并键（`<<: *base`、`<<: [*a, *b]`）
- [x] 多文档流（`---` / `...`）
- [x] 序列化器（`to_yaml_string`），往返（round-trip）保证与安全引号策略
- [ ] yaml-test-suite 一致性测试框架
- [ ] 流式 / 事件级 API

## 与 moonbit-community/yaml 的差异

[moonbit-community/yaml](https://mooncakes.io/docs/moonbit-community/yaml)
面向"简化的 YAML 子集 + 转换为 JSON"。本项目的差异点：

- 原生 `Yaml` 值模型（不被 JSON 扁平化、不丢结构）
- 往返序列化（`parse -> to_yaml_string`），注释保留（规划中）
- 带位置的错误报告（`ParseError` 携带行/列与上下文片段）
- 以官方 yaml-test-suite 为一致性验证基准

与上游实际行为的逐项对比，将随实测结果在此处更新。

## 使用方法

### 安装

```bash
# 在你的 MoonBit 项目目录中（包发布后）：
moon add Gen123s/yaml
```

然后在 `moon.pkg` 中添加 `import "Gen123s/yaml"`（别名 `@yaml`）。

### 解析 YAML 文档

```moonbit
let doc = @yaml.parse("name: MoonBit\nfeatures:\n  - wasm\n  - native\n")
inspect(doc.get("name"), content="Some(Str(MoonBit))")
```

### 按路径查询嵌套字段

```moonbit
let image = doc.get_path("services.web.image")  // 点号路径查找
```

### 序列化回 YAML（往返）

```moonbit
let text = @yaml.to_yaml_string(doc)            // Yaml -> YAML 文本
```

### 锚点、合并键、多文档流

```moonbit
// 已支持：&anchor / *alias、`<<:` 合并键、`---` 多文档流 ——
// 示例见 yaml_test.mbt / features_test.mbt 测试套件。
```

### 演示 CLI

在命令行解析一个真实的 docker-compose 文件：

```bash
moon run cmd/main
```

### 示例应用：compose-doctor

`cmd/compose-check` 是一个**基于本库构建**的 docker-compose.yml 体检器
——展示 `Yaml` 值模型的真实消费方式：

```bash
moon run cmd/compose-check
```

它对一份健康的 compose 文档输出 PASS，对一份损坏的文档报告：
缺失 `image`/`build`、端口映射格式错误、端口超出范围、`depends_on`
引用不存在的服务、未知顶层键。

## 开发

```bash
moon check          # 类型检查
moon test           # 运行测试
moon fmt --check    # 格式检查
moon run cmd/main   # 演示 CLI
moon run cmd/compose-check   # compose 体检器示例
```

CI 在每次 push 到 `main` 和所有 PR 上以 `--deny-warn` 运行以上全部命令
（见 `.github/workflows/ci.yml`）。

## 参考资料

本项目属于参考成熟实现的移植型重写：

- **PyYAML**（https://github.com/yaml/pyyaml，MIT）— scanner/parser 架构
- **libyaml**（https://github.com/yaml/libyaml，MIT）— 事件驱动设计
- **YAML 1.2 规范**（https://yaml.org/spec/1.2.2/）
- **yaml-test-suite**（https://github.com/yaml/yaml-test-suite，MIT）— 一致性测试

## 许可证

Apache-2.0（见 LICENSE）。本项目为 2026 MoonBit 九月黑客松参赛作品。
