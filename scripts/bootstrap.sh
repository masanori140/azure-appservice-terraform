#!/bin/bash

set -euo pipefail

# ==============================================================================
# Color Definitions
# ==============================================================================
readonly COLOR_INFO='\033[0;36m'
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARNING='\033[0;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_RESET='\033[0m'

# ==============================================================================
# Helper Functions
# ==============================================================================
info() {
  echo -e "${COLOR_INFO}ℹ️  $1${COLOR_RESET}"
}

success() {
  echo -e "${COLOR_SUCCESS}✅ $1${COLOR_RESET}"
}

warning() {
  echo -e "${COLOR_WARNING}⚠️  $1${COLOR_RESET}"
}

error() {
  echo -e "${COLOR_ERROR}❌ $1${COLOR_RESET}"
}

separator() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_command() {
  if ! command -v "$1" &> /dev/null; then
    error "$1 が見つかりません。インストールしてください。"
    exit 1
  fi
}

# ==============================================================================
# Prerequisite Check
# ==============================================================================
info "必要なツールを確認中..."
check_command az
check_command jq
success "必要なツール確認完了 (az, jq)"

# ==============================================================================
# Azure CLI Login Check
# ==============================================================================
info "Azure CLIログイン状態を確認中..."
if ! az account show &> /dev/null; then
  error "Azure CLIにログインしていません。'az login' を実行してください。"
  exit 1
fi

# ==============================================================================
# Interactive Input
# ==============================================================================
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
CURRENT_SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)

echo ""
info "現在のサブスクリプション: $CURRENT_SUBSCRIPTION"

# Environment
read -p "環境名 (dev/stg/prod) [dev]: " ENVIRONMENT
ENVIRONMENT=${ENVIRONMENT:-dev}

# Validate environment
case $ENVIRONMENT in
  poc|dev|stg|prod)
    ;;
  *)
    error "環境名は dev, stg, prod のいずれかを指定してください"
    exit 1
    ;;
esac

# Subscription
read -p "Subscription ID [$CURRENT_SUBSCRIPTION_ID]: " SUBSCRIPTION_ID
SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-$CURRENT_SUBSCRIPTION_ID}

# Location
read -p "Location [japaneast]: " LOCATION
LOCATION=${LOCATION:-japaneast}

# Terraform State Resource Group
DEFAULT_STATE_RG="rg-tfstate-${ENVIRONMENT}"
read -p "Terraform State用 Resource Group名 [$DEFAULT_STATE_RG]: " STATE_RESOURCE_GROUP_NAME
STATE_RESOURCE_GROUP_NAME=${STATE_RESOURCE_GROUP_NAME:-$DEFAULT_STATE_RG}

# Storage Account (動的生成)
SUBSCRIPTION_PREFIX=$(echo "$SUBSCRIPTION_ID" | cut -d'-' -f1)
DEFAULT_STORAGE_ACCOUNT_NAME="satfstate${ENVIRONMENT}${SUBSCRIPTION_PREFIX}"
read -p "Storage Account名 [$DEFAULT_STORAGE_ACCOUNT_NAME]: " STORAGE_ACCOUNT_NAME
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME:-$DEFAULT_STORAGE_ACCOUNT_NAME}

# Validate Storage Account name
if [[ ! "$STORAGE_ACCOUNT_NAME" =~ ^[a-z0-9]{3,24}$ ]]; then
  error "Storage Account名は3-24文字の小文字英数字のみ使用できます"
  exit 1
fi

# Container
read -p "Container名 [tfstate]: " CONTAINER_NAME
CONTAINER_NAME=${CONTAINER_NAME:-tfstate}

# Infrastructure Resource Group
INFRA_RESOURCE_GROUP_NAME="rg-appservice-test-${ENVIRONMENT}"

# Service Principal
DEFAULT_SP_NAME="sp-terraform-deploy-${ENVIRONMENT}"
read -p "サービスプリンシパル名 [$DEFAULT_SP_NAME]: " SERVICE_PRINCIPAL_NAME
SERVICE_PRINCIPAL_NAME=${SERVICE_PRINCIPAL_NAME:-$DEFAULT_SP_NAME}

# ==============================================================================
# Confirmation
# ==============================================================================
echo ""
separator
info "以下の設定でAzureリソースを作成します:"
separator
echo "  Subscription:        $CURRENT_SUBSCRIPTION"
echo "  Subscription ID:     $SUBSCRIPTION_ID"
echo "  Environment:         $ENVIRONMENT"
echo "  Location:            $LOCATION"
echo "  Terraform State RG:  $STATE_RESOURCE_GROUP_NAME"
echo "  Infrastructure RG:   $INFRA_RESOURCE_GROUP_NAME"
echo "  Storage Account:     $STORAGE_ACCOUNT_NAME"
echo "  Container:           $CONTAINER_NAME"
echo "  Service Principal:   $SERVICE_PRINCIPAL_NAME"
separator
echo ""

read -p "続行しますか？ (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  warning "処理を中止しました"
  exit 0
fi

# ==============================================================================
# Set Subscription
# ==============================================================================
info "サブスクリプションを設定中..."
az account set --subscription "$SUBSCRIPTION_ID"
success "サブスクリプション設定完了"

# ==============================================================================
# Create Terraform State Resource Group
# ==============================================================================
info "Terraform State用 Resource Groupを作成中..."
if az group show --name "$STATE_RESOURCE_GROUP_NAME" &> /dev/null; then
  warning "Resource Group '$STATE_RESOURCE_GROUP_NAME' は既に存在します"
else
  az group create \
    --name "$STATE_RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --output none
  success "Resource Group '$STATE_RESOURCE_GROUP_NAME' 作成完了"
fi

# ==============================================================================
# Create Infrastructure Resource Group
# ==============================================================================
info "インフラ用 Resource Groupを作成中..."
if az group show --name "$INFRA_RESOURCE_GROUP_NAME" &> /dev/null; then
  warning "Resource Group '$INFRA_RESOURCE_GROUP_NAME' は既に存在します"
else
  az group create \
    --name "$INFRA_RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --output none
  success "Resource Group '$INFRA_RESOURCE_GROUP_NAME' 作成完了"
fi

# ==============================================================================
# Create Storage Account
# ==============================================================================
info "Storage Accountを作成中..."
if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$STATE_RESOURCE_GROUP_NAME" &> /dev/null; then
  warning "Storage Account '$STORAGE_ACCOUNT_NAME' は既に存在します"
else
  az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$STATE_RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --encryption-services blob \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
  success "Storage Account '$STORAGE_ACCOUNT_NAME' 作成完了"
fi

# ==============================================================================
# Create Blob Container
# ==============================================================================
info "Blobコンテナを作成中..."
if az storage container show \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --auth-mode login &> /dev/null; then
  warning "Blobコンテナ '$CONTAINER_NAME' は既に存在します"
else
  az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --auth-mode login \
    --output none
  success "Blobコンテナ '$CONTAINER_NAME' 作成完了"
fi

# ==============================================================================
# Create Service Principal
# ==============================================================================
info "サービスプリンシパルを作成中..."

# Check if Service Principal already exists
EXISTING_SP=$(az ad sp list --display-name "$SERVICE_PRINCIPAL_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [ -n "$EXISTING_SP" ]; then
  warning "サービスプリンシパル '$SERVICE_PRINCIPAL_NAME' は既に存在します"
  SP_APP_ID="$EXISTING_SP"
  SP_TENANT_ID=$(az account show --query tenantId -o tsv)
  info "既存のサービスプリンシパルを使用します (App ID: $SP_APP_ID)"

  # 認証情報はリセットしない
  SKIP_CREDENTIAL_SAVE=true
else
  # Create new Service Principal
  SP_CREDENTIALS=$(az ad sp create-for-rbac \
    --name "$SERVICE_PRINCIPAL_NAME" \
    --skip-assignment \
    --output json)

  SP_APP_ID=$(echo "$SP_CREDENTIALS" | jq -r '.appId')
  SP_PASSWORD=$(echo "$SP_CREDENTIALS" | jq -r '.password')
  SP_TENANT_ID=$(echo "$SP_CREDENTIALS" | jq -r '.tenant')
  success "サービスプリンシパル '$SERVICE_PRINCIPAL_NAME' 作成完了"
  SKIP_CREDENTIAL_SAVE=false
fi

# Get Service Principal Object ID
SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id -o tsv)

# ==============================================================================
# Assign Contributor Role to Infrastructure Resource Group
# ==============================================================================
info "インフラ用RGにContributorロールを付与中..."
az role assignment create \
  --assignee "$SP_APP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${INFRA_RESOURCE_GROUP_NAME}" \
  --output none 2>/dev/null || warning "ロール割り当ては既に存在する可能性があります"
success "Contributorロール付与完了"

# ==============================================================================
# Assign Storage Blob Data Contributor Role (Terraform State)
# ==============================================================================
info "Terraform State用Storage AccountにStorage Blob Data Contributorロールを付与中..."
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${STATE_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}" \
  --output none 2>/dev/null || warning "ロール割り当ては既に存在する可能性があります"
success "Terraform State用Storage Blob Data Contributorロール付与完了"

# ==============================================================================
# Create Resource Lock
# ==============================================================================
info "Resource Lockを作成中..."
if az lock show \
  --name "DoNotDelete" \
  --resource-group "$STATE_RESOURCE_GROUP_NAME" &> /dev/null; then
  warning "Resource Lock 'DoNotDelete' は既に存在します"
else
  az lock create \
    --name "DoNotDelete" \
    --resource-group "$STATE_RESOURCE_GROUP_NAME" \
    --lock-type CanNotDelete \
    --notes "Prevent accidental deletion of Terraform state resources" \
    --output none
  success "Resource Lock 'DoNotDelete' 作成完了"
fi

# ==============================================================================
# Save Credentials
# ==============================================================================
if [ "$SKIP_CREDENTIAL_SAVE" = true ]; then
  warning "既存のサービスプリンシパルを使用しているため、認証情報ファイルは作成しません"
  info "既存の認証情報は sp-credentials-${ENVIRONMENT}.json を参照してください"
else
  CREDENTIALS_FILE="sp-credentials-${ENVIRONMENT}.json"

  info "認証情報を保存中..."
  cat > "$CREDENTIALS_FILE" << EOF
{
  "appId": "$SP_APP_ID",
  "password": "$SP_PASSWORD",
  "tenant": "$SP_TENANT_ID",
  "subscriptionId": "$SUBSCRIPTION_ID"
}
EOF

  chmod 600 "$CREDENTIALS_FILE"
  success "認証情報を保存しました: $CREDENTIALS_FILE"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
separator
success "セットアップ完了！"
separator
echo ""
if [ "$SKIP_CREDENTIAL_SAVE" = true ]; then
  echo "既存のサービスプリンシパルを使用しています"
  echo ""
  echo "認証情報は sp-credentials-${ENVIRONMENT}.json を参照してください"
  echo ""
  echo "ファイルが存在しない場合は、以下のコマンドで確認できます："
  echo "  - Application ID: az ad sp show --id $SP_APP_ID --query appId -o tsv"
  echo "  - Tenant ID: az account show --query tenantId -o tsv"
  echo ""
  warning "パスワード（Client Secret）は再取得できません"
  warning "紛失した場合は、Azure Portal で新しいシークレットを作成してください"
else
  echo "以下の情報を .env ファイルに設定してください："
  echo ""
  echo "ARM_CLIENT_ID=$SP_APP_ID"
  echo "ARM_CLIENT_SECRET=$SP_PASSWORD"
  echo "ARM_TENANT_ID=$SP_TENANT_ID"
  echo "ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
fi
echo ""
separator
echo ""
info "次のステップ:"
echo "  1. infrastructure/.env ファイルを作成"
echo "  2. 上記の環境変数を .env に記述"
echo "  3. terraform/environments/${ENVIRONMENT}/env.hcl を作成"
echo "  4. docker compose run --rm terraform bash でコンテナ起動"
echo ""
