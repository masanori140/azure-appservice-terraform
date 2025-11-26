# Terraform/Terragrunt コーディング規約

## 概要

このドキュメントは、Azure リソースを管理するための Terraform/Terragrunt コーディング規約です。3層アーキテクチャパターンに基づいた、再利用可能で保守性の高いインフラストラクチャコードを記述するための標準を定義します。

### 対象読者

- このプロジェクトで Terraform/Terragrunt コードを作成・編集する開発者
- AI コーディングアシスタント（Claude Code, GitHub Copilot など）
- コードレビュアー

### 目的

1. **一貫性**: 全てのコードが同じパターンとスタイルに従う
2. **再利用性**: リソース定義を複数の環境・プロジェクトで再利用可能にする
3. **保守性**: 変更の影響範囲を限定し、コードの理解を容易にする
4. **テスト容易性**: 各層を独立してテスト可能にする

---

## 目次

1. [3層アーキテクチャの原則](#3層アーキテクチャの原則)
2. [ディレクトリ構造](#ディレクトリ構造)
3. [コーディング規約](#コーディング規約)
4. [実践ガイド](#実践ガイド)
   - [新しいリソースを追加する](#新しいリソースを追加する)
   - [新しいモジュールを作成する](#新しいモジュールを作成する)
   - [既存モジュールを更新する](#既存モジュールを更新する)
5. [よくあるパターン](#よくあるパターン)
6. [チェックリスト](#チェックリスト)

---

## 3層アーキテクチャの原則

### アーキテクチャ概要

このプロジェクトは3層アーキテクチャパターンを採用しています。各層には明確な責務があり、それぞれが独立してテスト可能です。

```
terraform/
├── resources/        # 第1層: リソース層
├── modules/          # 第2層: モジュール層
└── environments/     # 第3層: 環境層
```

### 第1層: resources/ - リソース層

**責務**: Terraform公式リソースの薄いラッパーを提供

**特徴**:
- Terraform公式ドキュメントのリソース定義をほぼそのまま使用
- **全てのパラメータを変数として受け取る（ハードコードしない）**
- ビジネスロジックを含まない
- `resource`ブロックのみを使用（`module`は使用しない）
- リソースオブジェクト全体を output として返す

**例**: `resources/network/subnet/`
```hcl
# main.tf
resource "azurerm_subnet" "this" {
  name                 = var.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.address_prefixes
}

# outputs.tf
output "subnet" {
  description = "Subnet object"
  value       = azurerm_subnet.this
}
```

### 第2層: modules/ - モジュール層

**責務**: ビジネスロジックを実装し、複数のリソースを組み合わせる

**特徴**:
- **`module`ブロックのみを使用（`resource`ブロックは使用しない）**
- resources/ 層のモジュールを組み合わせる
- 具体的な値（命名規則、CIDR範囲など）を設定
- Data Sourcesで既存リソースを参照
- 依存関係を`depends_on`で明示

**例**: `modules/vnet/`
```hcl
# vnet.tf
module "vnet" {
  source = "../../resources/network/vnet"

  vnet_name           = "vnet-${var.tags.service}-${var.tags.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location.id
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}
```

### 第3層: environments/ - 環境層

**責務**: 環境固有の設定とデプロイメント管理

**特徴**:
- Terragrunt設定ファイル（`terragrunt.hcl`）を配置
- モジュールのソースパスを指定
- 環境固有の変数を定義（`env.hcl`経由）
- デプロイメントの依存関係を管理

**例**: `environments/dev/vnet/terragrunt.hcl`
```hcl
terraform {
  source = "../../../modules/vnet"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}
```

### 重要な設計原則

#### 1. modules層では`resource`を使用しない

**❌ 悪い例**:
```hcl
# modules/vnet/nsg.tf

module "nsg_appgw" {
  source = "../../resources/network/nsg"
  # ...
}

# ❌ modules層で直接resourceを定義してはいけない
resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = module.snet_appgw.subnet.id
  network_security_group_id = module.nsg_appgw.nsg.id
}
```

**✅ 良い例**:
```hcl
# modules/vnet/nsg.tf

module "nsg_appgw" {
  source = "../../resources/network/nsg"
  # ...
}

# ✅ resources層のモジュールを使用する
module "nsg_association_appgw" {
  source = "../../resources/network/subnet_nsg_association"

  subnet_id                 = module.snet_appgw.subnet.id
  network_security_group_id = module.nsg_appgw.nsg.id
}
```

#### 2. なぜこの原則が重要か

1. **責務の分離**
   - resources層: Terraform公式リソースの薄いラッパー
   - modules層: ビジネスロジックの実装（moduleの組み合わせ）
   - environments層: デプロイ設定

2. **再利用性**
   - resources層のリソースは他のモジュールでも再利用可能
   - modules層で`resource`を使うと、そのリソースは再利用できない

3. **テスト容易性**
   - resources層は単体でテスト可能
   - modules層で`resource`を使うと、テストが複雑になる

4. **保守性**
   - 3層の責務が明確
   - 変更の影響範囲が限定される

#### 3. 対応方法

もし新しい`resource`が必要な場合は、必ず以下の手順に従う:

1. **resources層にリソースを作成**
   ```bash
   mkdir -p terraform/resources/network/subnet_nsg_association
   ```

2. **main.tf, variables.tf, outputs.tfを作成**
   ```hcl
   # resources/network/subnet_nsg_association/main.tf
   resource "azurerm_subnet_network_security_group_association" "this" {
     subnet_id                 = var.subnet_id
     network_security_group_id = var.network_security_group_id
   }
   ```

3. **modules層でそのリソースを使用**
   ```hcl
   # modules/vnet/nsg.tf
   module "nsg_association_appgw" {
     source = "../../resources/network/subnet_nsg_association"

     subnet_id                 = module.snet_appgw.subnet.id
     network_security_group_id = module.nsg_appgw.nsg.id
   }
   ```

---

## ディレクトリ構造

### 標準的なディレクトリレイアウト

```
terraform/
├── resources/                          # 第1層: リソース層
│   ├── compute/
│   │   └── app-service/
│   │       ├── main.tf                # リソース定義
│   │       ├── variables.tf           # 入力変数
│   │       └── outputs.tf             # 出力値
│   ├── network/
│   │   ├── vnet/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── subnet/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── nsg/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── security/
│       └── key-vault/
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── modules/                            # 第2層: モジュール層
│   ├── vnet/
│   │   ├── data.tf                    # Data Sources
│   │   ├── vnet.tf                    # VNet関連のモジュール
│   │   ├── subnet.tf                  # Subnet関連のモジュール
│   │   ├── nsg.tf                     # NSG関連のモジュール
│   │   ├── variables.tf               # モジュール入力変数
│   │   └── outputs.tf                 # モジュール出力値
│   └── app-service/
│       ├── data.tf
│       ├── app-service.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/                       # 第3層: 環境層
    ├── dev/
    │   ├── vnet/
    │   │   └── terragrunt.hcl         # VNetモジュールのデプロイ設定
    │   └── app-service/
    │       └── terragrunt.hcl         # App Serviceモジュールのデプロイ設定
    ├── staging/
    │   ├── vnet/
    │   │   └── terragrunt.hcl
    │   └── app-service/
    │       └── terragrunt.hcl
    └── prod/
        ├── vnet/
        │   └── terragrunt.hcl
        └── app-service/
            └── terragrunt.hcl
```

### ファイル構成の原則

#### resources層のファイル構成

```
resources/<カテゴリ>/<リソース名>/
├── main.tf         # リソース定義（resourceのみ）
├── variables.tf    # 入力変数
└── outputs.tf      # 出力値
```

**必須ファイル**:
- `main.tf`: リソース定義
- `variables.tf`: 全ての入力パラメータ
- `outputs.tf`: リソースオブジェクト全体

**禁止事項**:
- `module`ブロックの使用
- ハードコードされた値
- ビジネスロジック

#### modules層のファイル構成

```
modules/<モジュール名>/
├── data.tf           # Data Sources（既存リソース参照）
├── <リソース名>.tf   # moduleの組み合わせ（resourceは使用しない）
├── variables.tf      # モジュール入力変数
└── outputs.tf        # モジュール出力値
```

**必須ファイル**:
- `data.tf`: 既存リソースの参照（必要な場合）
- `*.tf`: 機能別のモジュール定義ファイル
- `variables.tf`: root.hclから受け取る変数
- `outputs.tf`: 他モジュールに公開する値

**禁止事項**:
- `resource`ブロックの使用

#### environments層のファイル構成

```
environments/<環境名>/<モジュール名>/
└── terragrunt.hcl    # デプロイ設定
```

**設定内容**:
- モジュールのソースパス
- root.hclのインクルード
- 環境固有の変数（env.hcl経由）

---

## コーディング規約

### ファイル命名規則

#### リソース層（resources/）

- ディレクトリ名: リソースのTerraformリソース名に準拠
  - 例: `azurerm_virtual_network` → `vnet/`
  - 例: `azurerm_subnet` → `subnet/`
  - 例: `azurerm_network_security_group` → `nsg/`

- ファイル名: 固定
  - `main.tf`
  - `variables.tf`
  - `outputs.tf`

#### モジュール層（modules/）

- ディレクトリ名: ビジネス機能名
  - 例: `vnet/`, `app-service/`, `database/`

- ファイル名: 機能別に分割
  - `data.tf`: Data Sources
  - `<機能名>.tf`: 例 `vnet.tf`, `subnet.tf`, `nsg.tf`
  - `variables.tf`: 入力変数
  - `outputs.tf`: 出力値

#### 環境層（environments/）

- ディレクトリ名: 環境名とモジュール名
  - 例: `dev/vnet/`, `prod/app-service/`

- ファイル名: 固定
  - `terragrunt.hcl`

### コメントスタイル

#### セクション区切り（必須）

全ての`.tf`ファイルで、セクションの開始時に区切りコメントを使用:

```hcl
# ==============================================================================
# Section Name
# ==============================================================================

code_here
```

#### Terraform公式ドキュメントURL（resources/とmodules/のみ）

resources層とmodules層のファイルには、関連するTerraform公式ドキュメントのURLを記載:

```hcl
# ==============================================================================
# Azure Virtual Network
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network
# ==============================================================================

resource "azurerm_virtual_network" "this" {
  # ...
}
```

#### terragrunt.hcl（URLなし）

environments層の`terragrunt.hcl`では、URLは不要:

```hcl
# ==============================================================================
# Terraform
# ==============================================================================

terraform {
  source = "../../../modules/vnet"
}
```

### 変数命名規則

#### 一般的な命名パターン

| 変数名 | 型 | 説明 | 例 |
|--------|-----|------|-----|
| `<リソース名>_name` | `string` | リソース名 | `vnet_name`, `subnet_name` |
| `resource_group_name` | `string` | リソースグループ名 | `"rg-myapp-dev"` |
| `location` | `string` or `object` | リージョン | `"japaneast"` or `{ id = "japaneast" }` |
| `tags` | `map(string)` | リソースタグ | `{ environment = "dev", service = "myapp" }` |
| `address_space` | `list(string)` | VNetのアドレス空間 | `["10.0.0.0/16"]` |
| `address_prefixes` | `list(string)` | Subnetのアドレスプレフィックス | `["10.0.1.0/24"]` |

#### 複雑なオブジェクト型の命名

リスト/オブジェクト型の変数は、複数形を使用:

```hcl
variable "subnets" {
  description = "List of subnets to create"
  type = list(object({
    name             = string
    address_prefixes = list(string)
  }))
  default = []
}

variable "nsg_rules" {
  description = "List of NSG rules"
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  default = []
}
```

### variables.tfの記述規則

#### 必須項目

全ての変数に以下を含める:

```hcl
variable "example_var" {
  description = "Clear description of the variable"  # 必須
  type        = string                                # 必須
  default     = null                                  # オプション（省略可）
}
```

#### 変数の記述順序

1. `description`: 変数の説明
2. `type`: 変数の型
3. `default`: デフォルト値（オプション）
4. `validation`: バリデーションルール（必要な場合）

#### 変数の並び順

variables.tfの変数は、main.tfの属性の出現順に合わせて並べる:

```hcl
# main.tf
resource "azurerm_linux_web_app" "this" {
  name                          = var.web_app_name           # 1
  resource_group_name           = var.resource_group_name    # 2
  location                      = var.location               # 3
  service_plan_id               = var.service_plan_id        # 4
  https_only                    = var.https_only             # 5
  public_network_access_enabled = var.public_network_access_enabled  # 6
  app_settings                  = var.app_settings           # 7
  tags                          = var.tags                   # 8

  site_config { ... }                                        # 9
}

# variables.tf（main.tfと同じ順序で定義）
variable "web_app_name" { ... }           # 1
variable "resource_group_name" { ... }    # 2
variable "location" { ... }               # 3
variable "service_plan_id" { ... }        # 4
variable "https_only" { ... }             # 5
variable "public_network_access_enabled" { ... }  # 6
variable "app_settings" { ... }           # 7
variable "tags" { ... }                   # 8
variable "site_config" { ... }            # 9
```

**理由**:
- main.tfとvariables.tfの対応関係が明確になる
- コードレビュー時に変数の過不足を確認しやすい
- 一貫性のあるコードベースを維持できる

#### 型の指定

適切な型を使用:

```hcl
# プリミティブ型
variable "name" {
  type = string
}

variable "count" {
  type = number
}

variable "enabled" {
  type = bool
}

# コレクション型
variable "tags" {
  type = map(string)
}

variable "subnets" {
  type = list(string)
}

# オブジェクト型
variable "subnet_config" {
  type = object({
    name             = string
    address_prefixes = list(string)
  })
}
```

### outputs.tfの記述規則

#### resources層のoutputs

**原則**: オブジェクト全体を返す

```hcl
# ✅ 良い例: オブジェクト全体を返す
output "vnet" {
  description = "Virtual Network object"
  value       = azurerm_virtual_network.this
}

output "subnet" {
  description = "Subnet object"
  value       = azurerm_subnet.this
}

# ❌ 悪い例: 個別フィールドを返す
output "vnet_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.this.id
}
```

**理由**:
- 柔軟性: 呼び出し側が必要な属性を選択できる
- 拡張性: 新しい属性が追加されても変更不要
- 一貫性: 全てのresources層で同じパターン

#### modules層のoutputs

**原則**: 必要に応じて個別フィールドを返す

```hcl
# ✅ 良い例: 他モジュールが使う値を明示的に返す
output "vnet_id" {
  description = "Virtual Network ID"
  value       = module.vnet.vnet.id
}

output "vnet_name" {
  description = "Virtual Network name"
  value       = module.vnet.vnet.name
}

output "subnet_ids" {
  description = "Map of subnet names to IDs"
  value       = { for k, v in module.subnets : k => v.subnet.id }
}
```

### dynamicブロックの記述規則

#### 変数名の統一

`dynamic "<name>"`のブロック内で使う変数名は、`<name>`と同じにする:

```hcl
# ✅ 良い例: dynamic "cache" の変数名はcacheを使う
dynamic "cache" {
  for_each = var.cache
  content {
    query_string_caching_behavior = cache.value.query_string_caching_behavior
  }
}

# ❌ 悪い例: dynamic "cache" に対してcache_enabledという異なる変数名を使っている
dynamic "cache" {
  for_each = var.cache_enabled
  content {
    query_string_caching_behavior = cache_enabled.value.query_string_caching_behavior
  }
}
```

#### for_eachの記述

リスト/オブジェクト型の変数を直接渡す。bool変数での条件分岐は避ける:

```hcl
# ✅ 良い例: リスト/オブジェクト型の変数を直接渡す
dynamic "cache" {
  for_each = var.cache  # cache = [{ query_string_caching_behavior = "..." }]
  content {
    query_string_caching_behavior = cache.value.query_string_caching_behavior
  }
}

# ❌ 悪い例: bool変数で条件分岐（特別な理由がない限り使わない）
dynamic "cache" {
  for_each = var.cache_enabled ? [1] : []
  content {
    query_string_caching_behavior = "UseQueryString"
  }
}
```

**理由**:
- 型安全性: オブジェクト型を使うことで、必須パラメータを強制できる
- 可読性: 変数定義を見れば構造が分かる
- 拡張性: 新しいパラメータの追加が容易

### コードフォーマット

#### インデント

- スペース2つを使用
- タブは使用しない

#### ブロック間の空行

セクション間に1行の空行を入れる:

```hcl
# ==============================================================================
# VNet
# ==============================================================================

module "vnet" {
  source = "../../resources/network/vnet"

  vnet_name           = "vnet-${var.tags.service}-${var.tags.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location.id
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# ==============================================================================
# Subnets
# ==============================================================================

module "subnets" {
  source = "../../resources/network/subnet"
  # ...
}
```

#### パラメータの整列

パラメータの`=`を揃える:

```hcl
# ✅ 良い例
module "vnet" {
  source              = "../../resources/network/vnet"
  vnet_name           = "vnet-${var.tags.service}-${var.tags.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location.id
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# ❌ 悪い例
module "vnet" {
  source = "../../resources/network/vnet"
  vnet_name = "vnet-${var.tags.service}-${var.tags.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
  location = var.location.id
  address_space = ["10.0.0.0/16"]
  tags = var.tags
}
```

#### パラメータの記述順序

リソースブロック内のパラメータは以下の順序で記述する:

1. **Required** - 必須パラメータ
2. **Optional** - オプションパラメータ（tags, app_settings など）
3. **Block** - ネストされたブロック（site_config, identity など）
4. **Meta-arguments** - `depends_on`, `lifecycle`, `count`, `for_each`

**空白行のルール**:
- Required と Optional の間: 空白行なし
- Optional と Block の間: 空白行あり
- Block と Meta-arguments の間: 空白行あり

```hcl
# ✅ 良い例
resource "azurerm_linux_web_app" "this" {
  name                          = var.web_app_name           # Required
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = var.service_plan_id
  https_only                    = var.https_only             # Optional
  public_network_access_enabled = var.public_network_access_enabled
  app_settings                  = var.app_settings
  tags                          = var.tags

  site_config {                                              # Block
    always_on = true
  }

  depends_on = [module.service_plan]                         # Meta-arguments
}

# ❌ 悪い例（順序がバラバラ、不要な空白行）
resource "azurerm_linux_web_app" "this" {
  name                = var.web_app_name

  site_config {
    always_on = true
  }

  tags                = var.tags
  resource_group_name = var.resource_group_name
  service_plan_id     = var.service_plan_id
}
```

---

## 実践ガイド

### 新しいリソースを追加する

**例**: Subnet リソースを追加する

### ステップ 1: Terraform 公式ドキュメントを確認

https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet

### ステップ 2: resources 層を作成

```bash
mkdir -p terraform/resources/network/subnet
```

### ステップ 3: main.tf を作成

```hcl
# ==============================================================================
# Azure Subnet
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet
# ==============================================================================

resource "azurerm_subnet" "this" {
  name                 = var.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.address_prefixes
}
```

**ポイント**:

- ✅ 全て変数で受け取る
- ✅ ハードコードしない
- ✅ ビジネスロジックを書かない
- ✅ 公式ドキュメントの URL をコメントに記載

### ステップ 4: variables.tf を作成

```hcl
# ==============================================================================
# Azure Subnet
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet
# ==============================================================================

variable "subnet_name" {
  description = "Subnet name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "virtual_network_name" {
  description = "Virtual Network name"
  type        = string
}

variable "address_prefixes" {
  description = "Subnet address prefixes"
  type        = list(string)
}
```

**ポイント**:

- ✅ 必須パラメータは全て変数化
- ✅ description を必ず書く
- ✅ 適切な型を指定

### ステップ 5: outputs.tf を作成

```hcl
# ==============================================================================
# Azure Subnet
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet
# ==============================================================================

output "subnet" {
  description = "Subnet object"
  value       = azurerm_subnet.this
}
```

**ポイント**:

- ✅ オブジェクト全体を返す
- ✅ 他モジュールから`.id`, `.name`などでアクセス可能

---

## 新しいモジュールを作成する

**例**: VNet モジュールに Subnet を追加する

### ステップ 1: modules層の構成を確認

既存の`modules/vnet/`を拡張する場合:

```bash
# 既に以下が存在
# modules/vnet/data.tf       # Data Sources
# modules/vnet/vnet.tf       # VNet関連のモジュール
# modules/vnet/variables.tf  # モジュール入力変数
# modules/vnet/outputs.tf    # モジュール出力値

# 新しいファイルを作成（またはvnet.tfに追記）
# modules/vnet/subnet.tf
```

### ステップ 2: variables.tfを更新（必要な場合）

モジュールが受け取る変数を追加:

```hcl
# ==============================================================================
# VNet Module Variables
# ==============================================================================

variable "location" {
  description = "Azure region"
  type        = map(string)
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}

# 追加: Subnets定義
variable "subnets" {
  description = "List of subnets to create"
  type = list(object({
    name             = string
    address_prefixes = list(string)
  }))
  default = []
}
```

### ステップ 3: subnet.tf（またはvnet.tf）を更新

resources層のモジュールを組み合わせてビジネスロジックを実装:

```hcl
# ==============================================================================
# Subnets
# ==============================================================================

module "subnets" {
  source = "../../resources/network/subnet"

  for_each = { for s in var.subnets : s.name => s }

  subnet_name          = each.value.name
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = module.vnet.vnet.name
  address_prefixes     = each.value.address_prefixes

  depends_on = [module.vnet]
}
```

**重要なポイント**:
- ✅ `module`ブロックのみを使用（`resource`は使用しない）
- ✅ `for_each`で複数リソースを動的に作成
- ✅ `depends_on`で依存関係を明示
- ✅ 具体的な値（命名規則、CIDR範囲など）をここで設定

### ステップ 4: outputs.tfを更新

他モジュールが使用する値を公開:

```hcl
# ==============================================================================
# VNet Module Outputs
# ==============================================================================

output "vnet_id" {
  description = "Virtual Network ID"
  value       = module.vnet.vnet.id
}

# 追加: Subnet outputs
output "subnet_ids" {
  description = "Map of subnet names to IDs"
  value       = { for k, v in module.subnets : k => v.subnet.id }
}

output "subnet_names" {
  description = "List of subnet names"
  value       = keys(module.subnets)
}
```

**重要なポイント**:
- ✅ 個別フィールドを返す（modules層）
- ✅ 明確なdescriptionを記載
- ✅ 他モジュールが参照しやすい構造

---

## 既存モジュールを更新する

既存のモジュールにリソースを追加したり、設定を変更する場合の手順です。

### ステップ 1: 変更範囲を確認

影響を受けるファイルを特定:

```bash
# モジュール内のファイルを確認
ls -la modules/<モジュール名>/

# 既存の変数定義を確認
cat modules/<モジュール名>/variables.tf

# 既存のoutputsを確認
cat modules/<モジュール名>/outputs.tf
```

### ステップ 2: 後方互換性を考慮

既存の設定を壊さないよう注意:

```hcl
# ✅ 良い例: デフォルト値を設定して後方互換性を保つ
variable "new_feature" {
  description = "Enable new feature"
  type        = bool
  default     = false  # 既存の環境では無効
}

# ❌ 悪い例: デフォルト値なしで必須にすると既存の環境が壊れる
variable "new_feature" {
  description = "Enable new feature"
  type        = bool
  # default値がないため、既存のterragrunt.hclで値を指定する必要がある
}
```

### ステップ 3: 段階的に変更

大きな変更は複数のステップに分割:

1. 新しい変数を追加（デフォルト値あり）
2. 新しいモジュールを追加
3. outputsを追加
4. 環境ごとに有効化

### ステップ 4: 検証

変更後は必ず検証:

```bash
# フォーマットチェック
task format

# バリデーション
task validate env=dev module=<モジュール名>

# プラン確認
task plan env=dev module=<モジュール名>
```

---

## よくあるパターン

### パターン 1: Data Source で既存リソースを参照

```hcl
# modules/xxx/data.tf
data "azurerm_resource_group" "this" {
  name = "rg-${var.tags.service}-${var.tags.environment}"
}

# modules/xxx/xxx.tf
module "xxx" {
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
}
```

### パターン 2: 命名規則を統一

```hcl
vnet_name   = "vnet-${var.tags.service}-${var.tags.environment}"
subnet_name = "snet-${var.tags.service}-${var.tags.environment}-app"
nsg_name    = "nsg-${var.tags.service}-${var.tags.environment}-app"
```

### パターン 3: for_each で複数リソースを作成

```hcl
module "subnets" {
  source = "../../resources/network/subnet"

  for_each = { for s in var.subnets : s.name => s }

  subnet_name          = each.value.name
  address_prefixes     = each.value.address_prefixes
  # ...
}
```

### パターン 4: depends_on で依存関係を明示

```hcl
module "subnets" {
  # ...
  depends_on = [module.vnet]
}
```

### パターン 5: リソースの関連付けも module で行う

```hcl
# ❌ 悪い例: modules層でresourceを使用
resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = module.snet_appgw.subnet.id
  network_security_group_id = module.nsg_appgw.nsg.id
}

# ✅ 良い例: resources層のモジュールを使用
module "nsg_association_appgw" {
  source = "../../resources/network/subnet_nsg_association"

  subnet_id                 = module.snet_appgw.subnet.id
  network_security_group_id = module.nsg_appgw.nsg.id
}
```

---

## チェックリスト

コードを作成・レビューする際の確認項目です。

### resources層を作成するとき

**ファイル構成**:
- [ ] `main.tf`, `variables.tf`, `outputs.tf`の3ファイルを作成
- [ ] ディレクトリ名はリソース種別に基づく（例: `vnet/`, `subnet/`, `nsg/`）

**main.tf**:
- [ ] `resource`ブロックのみを使用（`module`は使用しない）
- [ ] 全てのパラメータを変数として受け取る（ハードコードしない）
- [ ] ビジネスロジックを含めない（条件分岐、計算などは避ける）
- [ ] Terraform公式ドキュメントのURLをコメントに記載
- [ ] セクション区切りコメントを使用

**variables.tf**:
- [ ] 全ての変数に`description`を記載
- [ ] 適切な型（`type`）を指定
- [ ] 必要に応じて`default`値を設定

**outputs.tf**:
- [ ] リソースオブジェクト全体を返す（個別フィールドではなく）
- [ ] 出力名は`<リソース種別>`（例: `vnet`, `subnet`, `nsg`）
- [ ] `description`を必ず記載

### modules層を作成・更新するとき

**ファイル構成**:
- [ ] `data.tf`で既存リソースを参照（必要な場合）
- [ ] 機能別に`.tf`ファイルを分割（例: `vnet.tf`, `subnet.tf`, `nsg.tf`）
- [ ] `variables.tf`でroot.hclから受け取る変数を定義
- [ ] `outputs.tf`で他モジュールに公開する値を定義

**リソース定義ファイル（*.tf）**:
- [ ] **`module`ブロックのみを使用（`resource`ブロックは使用しない）**
- [ ] resources層のモジュールを組み合わせる
- [ ] 具体的な値（命名規則、CIDR範囲など）を設定
- [ ] `depends_on`で依存関係を明示
- [ ] `for_each`で複数リソースを動的に作成（必要な場合）

**variables.tf**:
- [ ] root.hclから受け取る変数のみを定義
- [ ] 全ての変数に`description`を記載
- [ ] 適切な型を指定
- [ ] デフォルト値を設定（後方互換性のため）

**outputs.tf**:
- [ ] 他モジュールが使用する値を個別フィールドとして返す
- [ ] 明確な`description`を記載
- [ ] 適切な命名（例: `vnet_id`, `subnet_ids`）

**コーディングスタイル**:
- [ ] セクション区切りコメントを使用
- [ ] パラメータの`=`を揃える
- [ ] 命名規則に従う（例: `vnet-${var.tags.service}-${var.tags.environment}`）

### environments層を作成するとき

**terragrunt.hcl**:
- [ ] `terraform`ブロックで`source`パスを指定
- [ ] `include "root"`でroot.hclをインクルード
- [ ] 設定はシンプルに保つ（具体的な値はmodules層で設定）
- [ ] セクション区切りコメントを使用（URLは不要）

**環境固有の設定**:
- [ ] env.hclで環境固有の変数を定義（必要な場合）
- [ ] 環境間で共通の設定はroot.hclに集約

### コード変更後の検証

**フォーマットとバリデーション**:
- [ ] `task format`でコードをフォーマット
- [ ] `task validate env=<環境> module=<モジュール>`でバリデーション

**動作確認**:
- [ ] `task plan env=<環境> module=<モジュール>`で変更内容を確認
- [ ] 期待通りのリソースが作成/更新/削除されるか確認
- [ ] 意図しない変更が含まれていないか確認

**セキュリティチェック**:
- [ ] 認証情報やシークレットがハードコードされていないか確認
- [ ] 適切なセキュリティグループルールが設定されているか確認
- [ ] 不要なパブリックアクセスが許可されていないか確認

---

## AIモデル向けの補足

### このコーディング規約を参照する際の注意点

AIコーディングアシスタント（Claude Code, GitHub Copilotなど）は、以下の点に特に注意してください:

1. **3層アーキテクチャの厳守**
   - modules層では**絶対に**`resource`ブロックを使用しない
   - 新しいリソースが必要な場合は、必ずresources層に作成してからmodules層で使用する

2. **コード生成時の原則**
   - 全てのパラメータを変数化（ハードコードしない）
   - 適切な`description`を必ず含める
   - セクション区切りコメントを使用
   - パラメータの`=`を揃える

3. **命名規則の一貫性**
   - リソース名: `<リソース種別>-${var.tags.service}-${var.tags.environment}`
   - 変数名: 一般的なパターンに従う（例: `vnet_name`, `subnet_name`）
   - 出力名: resources層はオブジェクト全体、modules層は個別フィールド

4. **後方互換性**
   - 既存のコードを変更する際は、デフォルト値を設定
   - 破壊的変更を避ける

5. **セキュリティ**
   - 認証情報やシークレットは絶対にハードコードしない
   - 環境変数やKey Vaultを使用する

### よくある間違いと正しい対応

**間違い1**: modules層で`resource`ブロックを使用
```hcl
# ❌ 悪い例
module "nsg" {
  source = "../../resources/network/nsg"
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id = module.subnet.subnet.id
  network_security_group_id = module.nsg.nsg.id
}
```

**正しい対応**: resources層にモジュールを作成してから使用
```hcl
# ✅ 良い例
module "nsg" {
  source = "../../resources/network/nsg"
}

module "nsg_association" {
  source = "../../resources/network/subnet_nsg_association"

  subnet_id                 = module.subnet.subnet.id
  network_security_group_id = module.nsg.nsg.id
}
```

**間違い2**: resources層で個別フィールドを返す
```hcl
# ❌ 悪い例
output "vnet_id" {
  value = azurerm_virtual_network.this.id
}
```

**正しい対応**: オブジェクト全体を返す
```hcl
# ✅ 良い例
output "vnet" {
  description = "Virtual Network object"
  value       = azurerm_virtual_network.this
}
```

**間違い3**: 値のハードコード
```hcl
# ❌ 悪い例
resource "azurerm_subnet" "this" {
  name                 = "subnet-app"
  address_prefixes     = ["10.0.1.0/24"]
}
```

**正しい対応**: 全て変数で受け取る
```hcl
# ✅ 良い例
resource "azurerm_subnet" "this" {
  name                 = var.subnet_name
  address_prefixes     = var.address_prefixes
}
```
