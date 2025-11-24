# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

Azure App Service リソースを管理するための Terragrunt ベースの Infrastructure as Code プロジェクトです。Terraform、Terragrunt、Azure CLI を含む一貫した開発環境を提供するために Docker コンテナを使用しています。

## アーキテクチャ

### 3層アーキテクチャ

このプロジェクトは3層アーキテクチャパターンを採用しています：

```
terraform/
  resources/      # 第1層: Terraform公式リソースの薄いラッパー
  modules/        # 第2層: ビジネスロジック（moduleの組み合わせ）
  environments/   # 第3層: 環境固有の設定
```

**重要な原則**:
- **resources層**: `resource`ブロックのみ、全て変数化
- **modules層**: `module`ブロックのみ（`resource`ブロックは使用禁止）
- **environments層**: Terragrunt設定のみ

詳細なコーディング規約は `TERRAFORM_GUIDE.md` を参照してください。

### コンテナ化されたワークフロー

すべての Terraform/Terragrunt 操作は Docker コンテナ内で実行され、ツールのバージョンを統一します：
- Terraform: v1.13.4
- Terragrunt: v0.91.4
- Azure CLI: latest

Docker セットアップにはセキュリティのためのチェックサム検証が含まれています（サプライチェーン攻撃対策）。

### ディレクトリ構造

想定される構造（`./terraform/` 配下に作成）：
```
terraform/
  resources/
    <category>/
      <resource>/       # 例: network/vnet, compute/app-service
        main.tf
        variables.tf
        outputs.tf
  modules/
    <module>/           # 例: vnet, app-service
      data.tf
      *.tf
      variables.tf
      outputs.tf
  environments/
    {env}/              # 環境名（例: dev, staging, prod）
      {module}/         # モジュール名（例: app-service, database）
        terragrunt.hcl  # モジュール固有の設定
```

### 認証

Azure 認証はサービスプリンシパルの認証情報を環境変数経由で使用します：
- `ARM_CLIENT_ID`
- `ARM_CLIENT_SECRET`
- `ARM_SUBSCRIPTION_ID`
- `ARM_TENANT_ID`

Task コマンドを実行する前に、これらをシェル環境に設定する必要があります。

## よく使うコマンド

すべてのコマンドは Docker Compose をラップする [Task](https://taskfile.dev/) を使用します。コマンドには特定の設定をターゲットとするために `env` と `module` 変数が必要です。

### 基本的なワークフロー

```bash
# モジュールの初期化
task init env=dev module=app-service

# 変更の計画
task plan env=dev module=app-service

# 変更の適用（確認が必要）
task apply env=dev module=app-service

# 自動承認で適用
task apply env=dev module=app-service auto_approve=true

# リソースの削除（確認が必要）
task destroy env=dev module=app-service

# 自動承認で削除
task destroy env=dev module=app-service auto_approve=true
```

### 複数モジュールの操作

```bash
# 環境内のすべてのモジュールを初期化
task init-all env=dev

# すべてのモジュールの計画
task plan-all env=dev

# すべてのモジュールの適用（各モジュールで確認が必要）
task apply-all env=dev

# 確認なしですべてのモジュールを適用
task apply-all env=dev auto_approve=true

# すべてのモジュールを削除
task destroy-all env=dev auto_approve=true
```

### バリデーションとフォーマット

```bash
# Terraform 設定の検証
task validate env=dev module=app-service

# すべての terragrunt.hcl ファイルをフォーマット
task format
```

### ステート管理

```bash
# モジュールのステート内のリソースをリスト表示
task state-list env=dev module=app-service

# すべてのモジュールのリソースをリスト表示
task state-list-all env=dev
```

### 開発ユーティリティ

```bash
# コンテナで対話型シェルを開く
task shell

# 利用可能なすべてのタスクをリスト表示
task
```

### ログ出力

`log_level` 変数を設定して Terraform のログ詳細度を調整：
```bash
task plan env=dev module=app-service log_level=debug
```

有効なレベル: trace, debug, info, warn, error

## 重要な注意事項

- プロジェクトは環境固有の設定を持つ `./terraform/` ディレクトリが存在することを想定しています
- すべての Terraform/Terragrunt 操作はコンテナ化された環境を使用するために Task コマンド経由で実行する必要があります
- サービスプリンシパルの認証情報は絶対にコミットしないでください（`sp-credentials*.json` として gitignore されています）
- ロックファイルの競合を避けるために `.terraform.lock.hcl` ファイルは gitignore されています
- セキュリティのため、Docker コンテナは非 root ユーザー（uid 10001）として実行されます
