# 开源许可说明

本页归集 ForgePlay 自身的许可证，以及仓库和构建产物中包含的第三方组件的许可证。本页只作索引，不改变各组件原许可条款；条款以各组件随附的许可文本为准。

最近一次逐项核对：2026-11-10，依据当时的 `go.mod` 与 Go 模块缓存中各模块随附的许可文件。依赖升级后以对应模块的许可文件为准。

## ForgePlay 自身

ForgePlay 以 [Apache License 2.0](../../LICENSE) 发布，版权声明与第三方归属见仓库根目录的 [NOTICE](../../NOTICE)。向本项目提交的贡献按同一许可证授权，见 [CONTRIBUTING](../../CONTRIBUTING.md)。

## 随仓库分发的第三方内容

| 路径 | 内容 | 来源 | 许可 |
|---|---|---|---|
| `apps/client/vendor/qrcode/` | QR 码生成器，只保留三个运行时类，本地改动见该目录 README | [Greaby/godot-qrcode-generator](https://github.com/Greaby/godot-qrcode-generator) | MIT，Copyright (c) 2022 Greaby，全文见 [`apps/client/vendor/qrcode/LICENSE`](../../apps/client/vendor/qrcode/LICENSE) |
| `apps/client/icon.svg` | Godot 新建工程的默认图标，即 Godot 引擎 logo，未修改 | Godot Engine | CC BY 4.0，Copyright (c) 2017 Andrea Calabró |
| `apps/client/assets/covers/*.png`，以及官网原样复制的其中 4 张 `apps/web/src/assets/covers/{ashfall,ember,foundry,volt}.png` | 9 张游戏封面（640×400）；官网首页的 Fork Tree 示意图使用其中 4 张 | 项目设计原型包，见 [19-design-system](../19-design-system.md) | 仓库内没有单独的作者与许可记录；在维护者补充说明之前，不要假定可以在本项目之外复用 |

仓库不包含字体文件和音频文件：界面使用 Godot 引擎自带字体，Shooter 的 BGM 由 `apps/client/runtime/shooter/procedural_bgm.gd` 在运行时合成。

## 构建产物中包含的组件

### Godot Engine（客户端）

客户端基于 Godot 4.6.3。导出的客户端内含 Godot 引擎，引擎本体为 MIT（Expat）许可，Copyright (c) 2014-present Godot Engine contributors、Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur。引擎自身还包含若干第三方组件，完整清单与许可文本以 Godot 源码仓库的 `COPYRIGHT.txt` 为准，也可在运行时通过 `Engine.get_copyright_info()` 与 `Engine.get_license_info()` 取得。对外分发客户端时需要随附 Godot 的许可文本。

### Go 模块

各 Go 模块的依赖以各自的 `go.mod` 为准：`apps/server`、`apps/cli`、`apps/mcp`、`packages/dsl`、`packages/sdk`。仓库内模块之间（`forgeplay/dsl`、`forgeplay/sdk`）通过相对路径 `replace` 引用，同属本项目、同为 Apache-2.0。

直接依赖：

| 模块 | 使用方 | 许可 |
|---|---|---|
| `github.com/anthropics/anthropic-sdk-go` | `apps/server` | MIT |
| `github.com/gin-gonic/gin` | `apps/server` | MIT |
| `github.com/ncruces/go-sqlite3/gormlite` | `apps/server` | MIT |
| `github.com/swaggo/files` | `apps/server` | MIT |
| `github.com/swaggo/gin-swagger` | `apps/server` | MIT |
| `github.com/swaggo/swag` | `apps/server` | MIT |
| `gorm.io/gorm` | `apps/server` | MIT |
| `golang.org/x/crypto` | `apps/server` | BSD-3-Clause，另附 PATENTS 专利授权 |
| `golang.org/x/text` | `apps/server` | BSD-3-Clause，另附 PATENTS 专利授权 |
| `github.com/santhosh-tekuri/jsonschema/v6` | `packages/dsl`、`apps/cli`、`apps/mcp` | Apache-2.0 |
| `github.com/spf13/cobra` | `apps/cli` | Apache-2.0 |
| `golang.org/x/text` | `apps/cli` | BSD-3-Clause，另附 PATENTS 专利授权 |
| `github.com/modelcontextprotocol/go-sdk` | `apps/mcp` | Apache-2.0；按该模块 LICENSE 的说明，上游把许可证由 MIT 改为 Apache-2.0，未取得重新授权同意的历史贡献仍按 MIT，文档类贡献按 CC BY 4.0 |
| `github.com/google/jsonschema-go` | `apps/mcp` | MIT |

`packages/sdk` 只使用 Go 标准库，没有第三方依赖。`packages/dsl` 除 `jsonschema/v6` 外只有间接依赖 `golang.org/x/text`。

`apps/cli/go.mod` 与 `apps/mcp/go.mod` 列出的间接依赖：

| 模块 | 使用方 | 许可 |
|---|---|---|
| `github.com/inconshreveable/mousetrap` | `apps/cli` | Apache-2.0 |
| `github.com/spf13/pflag` | `apps/cli` | BSD-3-Clause |
| `github.com/segmentio/asm` | `apps/mcp` | MIT |
| `github.com/segmentio/encoding` | `apps/mcp` | MIT |
| `github.com/yosida95/uritemplate/v3` | `apps/mcp` | BSD-3-Clause |
| `golang.org/x/oauth2` | `apps/mcp` | BSD-3-Clause |
| `golang.org/x/sync`、`golang.org/x/sys`、`golang.org/x/text`、`golang.org/x/time` | `apps/mcp` | BSD-3-Clause，另附 PATENTS 专利授权 |

`apps/server/go.mod` 列出的全部 65 个第三方模块（含间接依赖）按许可证归类如下：

| 许可 | 数量 | 模块 |
|---|---|---|
| MIT | 36 | `github.com/anthropics/anthropic-sdk-go`、`github.com/buger/jsonparser`、`github.com/gabriel-vasile/mimetype`、`github.com/gin-contrib/sse`、`github.com/gin-gonic/gin`、`github.com/go-playground/locales`、`github.com/go-playground/universal-translator`、`github.com/go-playground/validator/v10`、`github.com/goccy/go-json`、`github.com/goccy/go-yaml`、`github.com/invopop/jsonschema`、`github.com/jinzhu/inflection`、`github.com/jinzhu/now`、`github.com/josharian/intern`、`github.com/json-iterator/go`、`github.com/klauspost/cpuid/v2`、`github.com/KyleBanks/depth`、`github.com/leodido/go-urn`、`github.com/mailru/easyjson`、`github.com/mattn/go-isatty`、`github.com/ncruces/go-sqlite3`、`github.com/ncruces/go-sqlite3/gormlite`、`github.com/ncruces/julianday`、`github.com/pelletier/go-toml/v2`、`github.com/quic-go/qpack`、`github.com/quic-go/quic-go`、`github.com/standard-webhooks/standard-webhooks/libraries`、`github.com/swaggo/files`、`github.com/swaggo/gin-swagger`、`github.com/swaggo/swag`、`github.com/tidwall/gjson`、`github.com/tidwall/match`、`github.com/tidwall/pretty`、`github.com/tidwall/sjson`、`github.com/ugorji/go/codec`、`gorm.io/gorm` |
| MIT-0 | 1 | `github.com/ncruces/go-sqlite3-wasm/v2` |
| Apache-2.0 | 13 | `github.com/bytedance/gopkg`、`github.com/bytedance/sonic`、`github.com/bytedance/sonic/loader`、`github.com/cloudwego/base64x`、`github.com/go-openapi/jsonpointer`、`github.com/go-openapi/jsonreference`、`github.com/go-openapi/spec`、`github.com/go-openapi/swag`、`github.com/modern-go/concurrent`、`github.com/modern-go/reflect2`、`github.com/pb33f/ordered-map/v2`、`github.com/santhosh-tekuri/jsonschema/v6`、`go.mongodb.org/mongo-driver/v2` |
| Apache-2.0，部分文件为 MIT | 2 | `go.yaml.in/yaml/v4`、`gopkg.in/yaml.v2` |
| BSD-3-Clause | 4 | `github.com/bahlo/generic-list-go`、`github.com/PuerkitoBio/purell`、`github.com/PuerkitoBio/urlesc`、`github.com/twitchyliquid64/golang-asm` |
| BSD-3-Clause，另附 PATENTS 专利授权 | 9 | `golang.org/x/arch`、`golang.org/x/crypto`、`golang.org/x/mod`、`golang.org/x/net`、`golang.org/x/sync`、`golang.org/x/sys`、`golang.org/x/text`、`golang.org/x/tools`、`google.golang.org/protobuf` |

以上各表（含 `apps/cli` 与 `apps/mcp` 的依赖）中没有 GPL、AGPL、LGPL、MPL 或许可不明的模块，这些许可证都可以与 Apache-2.0 的项目一同分发。

需要留意的几项：

- `github.com/ncruces/go-sqlite3-wasm/v2` 的主体是由 SQLite 及其配套库机器翻译得到的 Go 代码。按该模块 README，原作者保留版权、原许可继续有效；SQLite 上游声明其代码属于公有领域，模块内 `parser/` 目录为 MIT（Copyright (c) 2016 Marco Bambini），其余部分为 MIT-0。
- `gopkg.in/yaml.v2` 与 `go.yaml.in/yaml/v4` 以 Apache-2.0 为主，由 libyaml 移植的文件沿用 MIT。两者都带有 NOTICE 文件（Copyright 2011-2016 Canonical Ltd.），分发包含它们的二进制时需要一并保留。
- `github.com/swaggo/files` 以 Go 源码形式内嵌了 Swagger UI 的发行文件。Swagger UI 上游以 Apache-2.0 发布，但该模块内没有随附 Swagger UI 的许可文本。
- `github.com/quic-go/quic-go` 的 `assets/` 目录（logo 等品牌素材）不适用其 MIT 许可，本项目不使用也不分发这些素材。
- MIT、BSD 与 Apache-2.0 都要求在分发时保留版权声明与许可文本。对外发布服务端、CLI 或 MCP 的二进制时，需要随附上述模块的许可文本。

### 官网（`apps/web`）

官网基于 Astro 与 Starlight 构建，npm 依赖以仓库根目录的 `pnpm-lock.yaml` 为准，可用 `pnpm licenses list` 列出，本页不逐项归集。核对时依赖树中绝大多数包为 MIT、ISC、BSD 或 Apache-2.0，另有少量 BlueOak-1.0.0、CC0-1.0 与 0BSD。有两类包的许可证较严格：`lightningcss`（MPL-2.0）与 `@img/sharp-libvips-*`（LGPL-3.0-or-later，sharp 使用的预编译 libvips）。二者都是构建期工具，由 pnpm 安装，不进入本仓库；站点以静态方式构建时，它们也不进入生成的站点文件。
