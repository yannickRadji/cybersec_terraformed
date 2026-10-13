# Cybersecurity Exercise on Azure — Infrastructure as Code Edition (Windows 11)
## Provisioning, Hardening, and Telemetry Integration with Terraform (Azure Function + Azure SQL Database)

---

## 0. Architecture, Scope, and Conventions

You will build and then harden a small cloud ingestion service: an Azure Linux Function App (Python 3.11) that stores data in an Azure SQL Database (serverless). All infrastructure is declared with Terraform; the Azure Portal is used only to **observe** results. Monitoring (Application Insights) is part of the infrastructure from the very first `terraform apply`, because on this hosting plan it is your **only** way to see what the Function does: the command-line log stream is not available on Linux Consumption.

- **Phase 1 – Functional baseline:** provision (with monitoring), run the code locally against the real database, publish it, test it with curl and Postman.
- **Phase 2 – Hardening:** authentication, input validation, secret management, least-privilege database roles.
- **Troubleshooting reference:** a guide to reading the logs. It is **not a step** of the exercise: use it only when something fails.

```
 Client / Edge device (Postman, curl.exe, Raspberry Pi, ESP32)
            |  HTTPS (TLS 1.2+)  POST /api/http_trigger {"name": "..."}
            v
 Azure (francecentral)
   Linux Function App (Python 3.11, Y1 plan, Managed Identity) ----> Application Insights ----> Log Analytics workspace
            |  TDS / TCP 1433 (TLS 1.2, TDE at rest)                    (logs, exceptions, requests)
            v
   Azure SQL Server + serverless database NameCounterDB
            ^
   Azure Key Vault (Phase 2: connection string via Managed Identity)
```

**Conventions for Windows 11**
- Every command is written for **Windows PowerShell 5.1 or PowerShell 7** (Windows Terminal recommended). Do not use Git Bash syntax such as `\` line continuation or `export`.
- In PowerShell, `curl` is an alias for `Invoke-WebRequest` with different options. Always type **`curl.exe`** to call the real curl shipped with Windows 11.
- Line continuation in PowerShell is the backtick `` ` `` (last character on the line, no trailing space).
- **Quote Terraform's `-chdir` argument:** write `-chdir="..\infra"`. Without the quotes, PowerShell mangles the argument and Terraform answers *"Invalid -chdir option: must include an equals sign"*.
- **PowerShell variables live only in the terminal where you set them.** A new terminal, or a restart, loses `$FuncName`, `$Body`, `$ApiHost`... If a command complains about an empty value, check the variable with `echo $VariableName` and set it again in that terminal.
- **Local = `http://`, Azure = `https://`.** The Function running on your PC listens on plain HTTP (`http://localhost:7071`). Using `https://localhost` fails with a TLS error such as `SEC_E_INVALID_TOKEN`.
- Keep the project path short and free of spaces (e.g. `C:\Dev\...`).

---

## 1. Prerequisites (install with Chocolatey)

### 1.1 What you need and why

| Tool | Purpose | Chocolatey package |
|---|---|---|
| Git | Version control of your `.tf` files | `git` |
| Python 3.11 | Local Function runtime and tests (must match `python_version = "3.11"` in Terraform) | `python311` |
| Terraform CLI | Infrastructure as Code | `terraform` |
| Azure CLI | Authentication (`az login`) and bootstrap commands | `azure-cli` |
| Azure Functions Core Tools v4 | `func` command to run and publish the Function | `azure-functions-core-tools` |
| Visual Studio Code | Editor (used for every file in this exercise) | `vscode` |
| Postman | Manual API calls | `postman` |
| sqlcmd | Run SQL scripts from the terminal | `sqlcmd` |

> **Why `python311` and not `python`?** On Chocolatey, `python` is a metapackage that installs the latest Python 3. The Function App in this lab runs Python 3.11 and the version you run locally should match what you deploy. `python311` pins the minor version. Your PC may already have other Pythons (3.9, 3.12...): Step 4 of Phase 1 shows how to select 3.11 explicitly.

### 1.2 Install Chocolatey

1. Open **Windows Terminal → PowerShell as Administrator** (right-click → *Run as administrator*).
2. Install Chocolatey using the **current official command from https://chocolatey.org/install** (copy it from that page, not from a copy of this document). Read what a script does before you run it: piping a downloaded script into `iex` is exactly the kind of action this course teaches you to treat with caution.
3. Close and reopen the Administrator terminal, then verify:

```powershell
choco --version
```

### 1.3 Install the tools

In an **Administrator** PowerShell:

```powershell
choco install git python311 terraform azure-cli azure-functions-core-tools vscode postman sqlcmd -y
```

Close **all** terminals and open a new normal (non-admin) PowerShell so the updated `PATH` is loaded. Verify:

```powershell
git --version
py -0p                    # lists every installed Python with its path; 3.11 must appear
pip --version
terraform version         # expect >= 1.9.0
az version
func --version            # expect 4.x
code --version
sqlcmd -?
curl.exe --version
```

**Troubleshooting `python`**
- `python --version` may show another version than 3.11 if several Pythons are installed. That is expected; use `py -3.11` and a virtual environment (Phase 1, Step 4).
- If `python --version` opens the Microsoft Store or prints nothing, Windows 11 *App execution aliases* are intercepting it. Open *Settings → Apps → Advanced app settings → App execution aliases*, turn off `python.exe` and `python3.exe`, and reopen the terminal.
- `Get-Command python -All` shows which `python` wins on `PATH`.
- To pin a Terraform version: `choco install terraform --version <x.y.z> -y`.

### 1.4 VS Code extensions

```powershell
code --install-extension HashiCorp.terraform
code --install-extension ms-azuretools.vscode-azurefunctions
code --install-extension ms-python.python
code --install-extension ms-mssql.mssql
code --install-extension Azurite.azurite
```

`Azurite` is a local emulator of Azure Storage. The Functions host wants a storage connection even for local runs; Azurite provides one on your PC so you do not need (or touch) a real storage account. See Step 4.3.

### 1.5 Microsoft ODBC Driver 18 for SQL Server (required for the local run)

`pyodbc` needs the **ODBC Driver 18 for SQL Server** on your PC to run the Function locally (Phase 1, Step 4.3). Download the driver from Microsoft's "Download ODBC Driver for SQL Server" documentation page and install it. Check it:

```powershell
Get-OdbcDriver | Where-Object Name -like "*SQL Server*" | Select-Object Name
```

`ODBC Driver 18 for SQL Server` must be in the list. (No Chocolatey package was verified for this driver, so the Microsoft installer is the documented route.) Whether the Function running *in Azure* also has the driver is something you will see if a call fails: see the troubleshooting reference "Read the logs".

### 1.6 Preparatory reading (before Step 1)

1. **API calls:** [Postman – Sending your first request](https://learning.postman.com/docs/getting-started/first-steps/sending-the-first-request/). You must be able to send a POST with a JSON body and read the status code.
2. **Terraform on Azure:** [Terraform – Get Started with Azure](https://developer.hashicorp.com/terraform/tutorials/azure-get-started).

> **What to skip in the HashiCorp tutorial**
> - **"Store remote state"** migrates state to HCP Terraform. We do **not** use HCP; we use Terraform Community with an Azure Blob Storage backend (Section 2).
> - Any step that changes resources by hand in the Azure Portal: this creates *drift* between reality and your code.

### 1.7 Azure sign-in

```powershell
az login
az account show --query "{name:name, id:id}" -o table
az account set --subscription "<your subscription id>"
```

With an Azure for Students subscription, make sure the subscription shown is the student one.

---

## 2. Remote State Bootstrap (PowerShell)

Terraform state contains secrets (admin passwords, connection strings). Store it remotely in an encrypted, private Azure Storage Account, not on your laptop. Terraform cannot create its own state container before the first `init`, so create it **once** with the CLI.

> **Naming:** globally unique, 3–24 characters, lowercase letters and digits only, e.g. `tfstatergyr` (use your own initials). Resource group: `rg-tfstate-prod`.

```powershell
$Location   = "francecentral"
$StateRg    = "rg-tfstate-prod"
$Initials   = "yr"                      # <-- your lowercase initials
$StateSa    = "tfstaterg$Initials"
$Container  = "tfstate"

az group create --name $StateRg --location $Location

az storage account create `
  --resource-group $StateRg `
  --name $StateSa `
  --location $Location `
  --sku Standard_LRS `
  --min-tls-version TLS1_2 `
  --allow-blob-public-access false
```

### 2.1 Give yourself data access (mandatory)

Creating a storage account does **not** give you access to its data through Entra ID, and the Owner/Contributor roles do not include blob data actions. The Terraform backend (`use_azuread_auth = true`) reads and writes the state blob as *you*, so assign yourself **Storage Blob Data Contributor** on this account:

```powershell
$UserId = az ad signed-in-user show --query id -o tsv
$Scope  = az storage account show --name $StateSa --resource-group $StateRg --query id -o tsv

az role assignment create `
  --assignee-object-id $UserId `
  --assignee-principal-type User `
  --role "Storage Blob Data Contributor" `
  --scope $Scope

az logout
az login
```

The `az logout` / `az login` forces a fresh token; role assignments can take a few minutes to propagate. Then create the container:

```powershell
az storage container create `
  --name $Container `
  --account-name $StateSa `
  --auth-mode login
```

Symptom if you skip this: `terraform init` fails with *403 ... AuthorizationPermissionMismatch*. Verify the account settings:

```powershell
az storage account show --name $StateSa --resource-group $StateRg --query "{name:name, tls:minimumTlsVersion, publicBlob:allowBlobPublicAccess}" -o table
```

---

## 3. Project Layout and Terraform Practices

```powershell
mkdir C:\Dev\cybersec_terraformed\infra
mkdir C:\Dev\cybersec_terraformed\src
cd C:\Dev\cybersec_terraformed
git init
code .
```

```
cybersec_terraformed/
├── .gitignore             # .venv/, src/local.settings.json, __pycache__/
├── .venv/                 # Python 3.11 virtual environment (never committed)
├── infra/
│   ├── versions.tf        # Terraform/provider versions + remote backend
│   ├── variables.tf       # Typed variables with validation
│   ├── main.tf            # Resource group, random suffix, tags
│   ├── monitoring.tf      # Log Analytics workspace + Application Insights
│   ├── sql.tf             # SQL server, database, firewall rules
│   ├── functions.tf       # Storage account, service plan, Function App
│   ├── outputs.tf         # Names and endpoints needed later
│   ├── terraform.tfvars   # YOUR values (never committed)
│   └── .gitignore
└── src/
    ├── function_app.py
    ├── host.json
    ├── local.settings.json   # local only, never committed
    ├── .funcignore
    └── requirements.txt
```

**Practices applied**
- **Split files by concern** instead of one large `main.tf`.
- **Implicit dependencies:** reference attributes (`azurerm_mssql_server.sql.id`) instead of `depends_on`. Terraform builds a dependency graph from references and creates independent resources in parallel. Example in this lab: the Function App uses `azurerm_application_insights.appi.connection_string`, so Terraform creates the workspace, then Application Insights, then the Function App, without any `depends_on`. Use explicit `depends_on` only for a dependency Terraform cannot see (e.g. waiting for a role assignment).
- **Validated variables:** invalid input is rejected at `plan` time, before any call to Azure.
- **Remote state** in Azure Blob Storage.
- **Observability from day one:** infrastructure you cannot observe cannot be debugged or defended.
- **Commit `.terraform.lock.hcl`** (it pins provider checksums). Do **not** commit `*.tfvars`, state, `.terraform/`, `.venv/` or `local.settings.json`.

---

## 4. Terraform Code

> Versions: Terraform `>= 1.9.0`, AzureRM `~> 5.5.0`, Random `~> 3.7`. AzureRM 5.x is a major release; if `terraform validate` reports an argument as deprecated, removed or renamed, read the message and the AzureRM documentation for your installed version, then adjust. This is a normal part of working with IaC.

### `infra/versions.tf`

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "tfstatergyr" # <-- your state storage account
    container_name       = "tfstate"
    key                  = "namecounter.prod.tfstate"
    use_azuread_auth     = true          # authenticate with your az login identity
  }
}

provider "azurerm" {
  resource_provider_registrations = "core"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
```

> The backend block cannot use variables: replace `tfstatergyr` by your own account name. `use_azuread_auth = true` requires the *Storage Blob Data Contributor* role from Section 2.1.
>
> Application Insights uses the resource providers `Microsoft.Insights` and `Microsoft.OperationalInsights`. If `apply` complains that a provider is not registered, run `az provider register --namespace Microsoft.Insights` and `az provider register --namespace Microsoft.OperationalInsights`, wait until `az provider show --namespace Microsoft.Insights --query registrationState -o tsv` prints `Registered`, then retry.

### `infra/variables.tf`

```hcl
variable "environment" {
  type        = string
  description = "Environment name used in resource names."
  default     = "lab"

  validation {
    condition     = contains(["lab", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: lab, dev, staging, prod."
  }
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "francecentral"

  validation {
    condition     = can(regex("^[a-z]+[0-9]*$", var.location))
    error_message = "location must be a lowercase Azure region name such as francecentral."
  }
}

variable "sql_admin_login" {
  type        = string
  description = "SQL Server administrator login."
  default     = "secopsadmin"

  validation {
    condition     = length(var.sql_admin_login) >= 5 && !contains(["admin", "administrator", "root", "sa"], lower(var.sql_admin_login))
    error_message = "Login must be at least 5 characters and not a reserved name (admin, administrator, root, sa)."
  }
}

variable "sql_admin_password" {
  type        = string
  description = "SQL Server administrator password."
  sensitive   = true

  validation {
    condition = (
      length(var.sql_admin_password) >= 14 &&
      can(regex("[A-Z]", var.sql_admin_password)) &&
      can(regex("[a-z]", var.sql_admin_password)) &&
      can(regex("[0-9]", var.sql_admin_password)) &&
      can(regex("[^A-Za-z0-9]", var.sql_admin_password))
    )
    error_message = "Password: at least 14 characters with upper case, lower case, digit and special character."
  }
}

variable "client_ip_address" {
  type        = string
  description = "Your public IPv4 address (no CIDR) allowed through the SQL firewall."

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$", var.client_ip_address))
    error_message = "client_ip_address must be a valid IPv4 address such as 203.0.113.45."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Days to keep logs in the Log Analytics workspace (cost control)."
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}
```

### `infra/main.tf`

```hcl
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-namecounter-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = {
    Project     = "Cybersecurity-Lab"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

### `infra/monitoring.tf`

```hcl
resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_application_insights" "appi" {
  name                = "appi-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  workspace_id        = azurerm_log_analytics_workspace.law.id # workspace-based Application Insights
  application_type    = "web"

  tags = azurerm_resource_group.rg.tags
}
```

> Application Insights stores its data in the Log Analytics workspace, which is why both resources exist. Both bill by data volume; the lab produces very little, and `terraform destroy` removes them.

### `infra/sql.tf`

```hcl
resource "azurerm_mssql_server" "sql" {
  name                         = "sql-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_mssql_database" "db" {
  name                        = "NameCounterDB"
  server_id                   = azurerm_mssql_server.sql.id
  sku_name                    = "GP_S_Gen5_1"
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 60
  zone_redundant              = false

  tags = azurerm_resource_group.rg.tags
}

# Phase 1 only: lets Azure-hosted services reach the server (see Phase 2, section 6.5).
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "allow_student_ip" {
  name             = "AllowStudentWorkstation"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = var.client_ip_address
  end_ip_address   = var.client_ip_address
}
```

### `infra/functions.tf`

```hcl
resource "azurerm_storage_account" "func_sa" {
  name                     = "stfunc${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_service_plan" "asp" {
  name                = "asp-namecounter-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption (serverless)

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_linux_function_app" "app" {
  name                = "func-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  storage_account_name       = azurerm_storage_account.func_sa.name
  storage_account_access_key = azurerm_storage_account.func_sa.primary_access_key

  https_only = true

  site_config {
    application_insights_connection_string = azurerm_application_insights.appi.connection_string

    application_stack {
      python_version = "3.11"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD"              = "true"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing" # Python v2 programming model
    "SQL_CONNECTION_STRING" = join("", [
      "Driver={ODBC Driver 18 for SQL Server};",
      "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;",
      "Database=${azurerm_mssql_database.db.name};",
      "Uid=${var.sql_admin_login};Pwd=${var.sql_admin_password};",
      "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    ])
  }

  tags = azurerm_resource_group.rg.tags
}
```

> `FUNCTIONS_WORKER_RUNTIME` and the extension version are set by the provider for this resource; do not duplicate them unless `terraform plan` asks for it. Microsoft's quickstarts require `AzureWebJobsFeatureFlags=EnableWorkerIndexing` for the Python v2 model, while other guides say recent runtimes no longer need it. Keeping it is harmless.
>
> The Application Insights connection string is set through `site_config` (Terraform then creates the `APPLICATIONINSIGHTS_CONNECTION_STRING` setting for you). Do not also add it to `app_settings`, or `plan` may show a permanent difference. If `validate` rejects the argument name in your provider version, check the `azurerm_linux_function_app` documentation for your installed version.

### `infra/outputs.tf`

```hcl
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "database_name" {
  value = azurerm_mssql_database.db.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.app.name
}

output "function_app_default_hostname" {
  value = azurerm_linux_function_app.app.default_hostname
}

output "app_insights_name" {
  value = azurerm_application_insights.appi.name
}
```

### `infra/terraform.tfvars` (never committed)

Get your public IPv4 address:

```powershell
curl.exe -s https://api.ipify.org
```

```hcl
environment        = "lab"
location           = "francecentral"
sql_admin_login    = "secopsadmin"
sql_admin_password = "Choose-A-Long-Unique-Passw0rd!"   # your own; do not reuse this one
client_ip_address  = "203.0.113.45"                      # your IPv4 from the command above
```

### `infra/.gitignore`

```
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars
*.tfvars.json
tfplan
override.tf
override.tf.json
*_override.tf
*_override.tf.json
```

Create it with VS Code: `code .gitignore` opens a new empty file in the editor; paste the content and save it (Ctrl+S). Create `infra\terraform.tfvars` the same way (`code terraform.tfvars`).

---

## 5. Phase 1 — Build and Test

### Step 1: Provision (including monitoring)

```powershell
cd C:\Dev\cybersec_terraformed\infra
terraform init -upgrade
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
git add .terraform.lock.hcl
```

Read the plan before applying: check the number of resources, names and region. The plan must include a Log Analytics workspace and an Application Insights component.

### Step 2: Create the table

```powershell
$Server = terraform output -raw sql_server_fqdn
$Query  = "CREATE TABLE dbo.Names (id INT IDENTITY(1,1) PRIMARY KEY, name VARCHAR(100) NOT NULL, count INT NOT NULL DEFAULT 0);"
sqlcmd -S $Server -d NameCounterDB -U secopsadmin -P "<your password>" -N -Q $Query
```

`-N` forces an encrypted connection. If the serverless database is paused, the first attempt can time out: wait a minute and retry. You can use the VS Code *SQL Server (mssql)* extension instead. If your campus network filters outbound port 1433, use another network.

### Step 3: Write the application

Create these files in `src` (open each with `code <filename>` from the `src` folder). **`local.settings.json` is mandatory**: without it (or an explicit `--python` flag) `func` stops with *"Can't determine project language from files"* and *"Worker runtime cannot be 'None'"*.

`src\local.settings.json` (local only; it may contain secrets, so it must never be committed). The `SQL_CONNECTION_STRING` placeholder is filled in at Step 4.3. `UseDevelopmentStorage=true` points the Functions host to the Azurite emulator (Step 4.3):

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "SQL_CONNECTION_STRING": "<filled in at Step 4.3>"
  }
}
```

`src\.funcignore` (files that must not be uploaded):

```
.venv
__pycache__
local.settings.json
.git*
tests
```

Create a `.gitignore` in the project root `C:\Dev\cybersec_terraformed` containing at least:

```
.venv/
src/local.settings.json
__pycache__/
```

`src\requirements.txt`:

```
azure-functions
pyodbc
```

`src\host.json` (sends logs to Application Insights and keeps request telemetry unsampled, so no failing call is dropped):

```json
{
  "version": "2.0",
  "logging": {
    "logLevel": { "default": "Information" },
    "applicationInsights": {
      "samplingSettings": { "isEnabled": true, "excludedTypes": "Request;Exception" }
    }
  }
}
```

`src\function_app.py` (the server logs the full technical error; the client only gets a generic message, which is deliberate: logs are for you, responses are for callers):

```python
import json
import logging
import os

import azure.functions as func
import pyodbc

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
logger = logging.getLogger("namecounter")


def json_response(body: dict, status: int) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(body), status_code=status, mimetype="application/json")


@app.route(route="http_trigger", methods=["POST"])
def http_trigger(req: func.HttpRequest) -> func.HttpResponse:
    try:
        name = req.get_json().get("name")
    except ValueError:
        logger.warning("Rejected request: body is not valid JSON")
        return json_response({"error": "Body must be valid JSON."}, 400)

    if not name:
        logger.warning("Rejected request: field 'name' missing")
        return json_response({"error": "Field 'name' is required."}, 400)

    conn_str = os.environ.get("SQL_CONNECTION_STRING")
    if not conn_str:
        logger.error("SQL_CONNECTION_STRING is not configured")
        return json_response({"error": "Internal error."}, 500)

    try:
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT count FROM dbo.Names WHERE name = ?", (name,))
            row = cursor.fetchone()
            if row:
                count = row[0] + 1
                cursor.execute("UPDATE dbo.Names SET count = ? WHERE name = ?", (count, name))
            else:
                count = 1
                cursor.execute("INSERT INTO dbo.Names (name, count) VALUES (?, ?)", (name, count))
            conn.commit()
    except pyodbc.Error:
        # Full stack trace and driver message go to Application Insights, never to the caller.
        logger.exception("Database error while updating the counter")
        return json_response({"error": "Internal error."}, 500)

    logger.info("Counter updated, count=%s", count)
    return func.HttpResponse(f"hello {name} this is your {count}th call")
```

> Do not log the raw `name` value or secrets in production: logs are data too (privacy, log injection). Here the counter value is logged, not the user input.
>
> Known limitation to discuss in Phase 2: the read-then-write sequence is not atomic. Two simultaneous calls with the same name can read the same count. A single `UPDATE ... SET count = count + 1` statement (or a `MERGE` with locking hints) fixes it. Why does this matter when many devices call in parallel?

### Step 4: Select Python, run locally, publish

**4.1 PowerShell and `-chdir`.** The argument must be quoted. Check that the variable is filled, and spelled the same way every time (`$FuncName`, not `$FunName`):

```powershell
cd C:\Dev\cybersec_terraformed\src
$FuncName = terraform -chdir="..\infra" output -raw function_app_name
echo $FuncName
```

**4.2 Make `func` use Python 3.11.** Core Tools compares your local Python with the version of the deployed Function App (`PYTHON|3.11`) and warns when they differ ("Local python version '3.9.13' is different..."). A PC often has several Pythons, and the one found first is used, which may not be the one `python --version` suggests. List them:

```powershell
py -0p                        # all installed versions and their paths
Get-Command python -All       # which "python" wins on PATH
python --version
```

If 3.11 is missing, install it (`choco install python311 -y`) and open a new terminal. Then create a virtual environment from 3.11, **outside `src`**, and activate it:

```powershell
cd C:\Dev\cybersec_terraformed
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python --version              # must print 3.11.x, and the prompt starts with (.venv)
pip install -r src\requirements.txt
```

If activation is blocked ("running scripts is disabled on this system"), run once `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` and retry.

With the environment activated, `python` resolves to the venv's 3.11, which is the interpreter Core Tools should then use. Microsoft's CLI quickstart likewise tells you to create and activate a `.venv` with a supported Python version before publishing. Leave the environment with `deactivate` when you are done.

**4.3 Run locally, connected to the Azure SQL database, then test.** Before publishing, check that your code works on your own PC against the real database. The Function runs locally, the data lives in Azure SQL.

Prerequisites: the ODBC Driver 18 is installed (Section 1.5), the Azurite extension is installed (Section 1.4), the virtual environment is active (4.2), and your public IP is allowed by the SQL firewall (Terraform rule `AllowStudentWorkstation`; if your IP changed, update `client_ip_address` and run `terraform apply` again).

1. **Fill in the connection string** in `src\local.settings.json` (`code src\local.settings.json`). Get the server name with `terraform -chdir="..\infra" output -raw sql_server_fqdn` and use the login and password from your `terraform.tfvars`. Avoid `"` and `\` in the password, they must be escaped in JSON:

```json
"SQL_CONNECTION_STRING": "Driver={ODBC Driver 18 for SQL Server};Server=tcp:<server-fqdn>,1433;Database=NameCounterDB;Uid=secopsadmin;Pwd=<your password>;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
```

2. **Start the storage emulator (Azurite).** In VS Code press `F1` (or `Ctrl+Shift+P`), type `Azurite: Start` and run it. The status bar shows the Azurite services running. The Functions host needs a storage connection even for an HTTP-triggered function; an empty `AzureWebJobsStorage` makes it report `Unable to create client for AzureWebJobsStorage`. Azurite must be running every time you start the Function locally.

3. **Start the Function locally** in a first terminal (venv active):

```powershell
cd C:\Dev\cybersec_terraformed\src
func start
```

Wait until the output lists `http_trigger: [POST] http://localhost:7071/api/http_trigger`. Leave this terminal running.

4. **Open a second terminal** and create the request file *in that terminal* (PowerShell variables do not carry over between terminals). `-Encoding ascii` avoids a hidden byte-order mark that would make the JSON invalid. Check the file before using it:

```powershell
$Body = "$env:TEMP\alice.json"
'{"name": "Alice"}' | Set-Content -Path $Body -Encoding ascii
Test-Path $Body        # must print True
Get-Content $Body      # must print {"name": "Alice"}
```

5. **Call the local Function.** Note `http://`, not `https://`: the local host does not speak TLS.

```powershell
curl.exe -X POST "http://localhost:7071/api/http_trigger" -H "Content-Type: application/json" --data "@$Body"
```

Expected: `hello Alice this is your 1th call`. If `Alice` already exists from an earlier test, the number continues from the stored value: what matters is that it goes up by one. Note the number. For a clean start, delete the row first: `sqlcmd -S <server-fqdn> -d NameCounterDB -U secopsadmin -P "<password>" -N -Q "DELETE FROM dbo.Names WHERE name = 'Alice';"`.

If something fails here, the first terminal prints the full error:

| Symptom | Cause | Fix |
|---|---|---|
| `curl: Failed to open` (empty file name) | `$Body` is not set in this terminal | Redo step 4 in this terminal |
| `SEC_E_INVALID_TOKEN` / `schannel` error | You used `https://` locally | Use `http://localhost:7071/...` |
| Connection refused | `func start` is not running or still starting | Check the first terminal |
| `Unable to create client for AzureWebJobsStorage` | Azurite not started, or empty `AzureWebJobsStorage` | Step 2; check `UseDevelopmentStorage=true` |
| `{"error": "Internal error."}` (500) | Database connection or SQL problem | Read the error in the first terminal; see the triage table in the troubleshooting reference |

6. **Stop the local Function:** press `Ctrl+C` in the first terminal. You can stop Azurite from the VS Code command palette (`Azurite: Close`).

**4.4 Publish to Azure.**

```powershell
cd C:\Dev\cybersec_terraformed\src
func azure functionapp publish $FuncName
```

Re-read the first lines of the output: the *"Local python version ... is different"* warning must be gone. Publishing does not upload `local.settings.json`; the deployed Function uses the settings that Terraform defined.

**4.5 Verify that the function was registered.** The end of the publish output must list your function (for example `http_trigger - [httpTrigger]` with its URL). If the list after `Functions in <name>:` is empty, the code was uploaded but not indexed:

```powershell
func azure functionapp list-functions $FuncName
```

Wait one or two minutes and list again (trigger sync can lag). If it stays empty, use the troubleshooting reference "Read the logs" at the end of this section: look for an import error in `function_app.py` or a failed package installation. Test the imports locally first, with the environment active: `python -c "import azure.functions, pyodbc"` must not fail (pyodbc needs the ODBC driver only when connecting, not at import).

> `func azure functionapp logstream` does **not** work for this plan: Core Tools answers *"Log stream is not currently supported in Linux Consumption and Flex Apps"*. That is exactly why Application Insights is provisioned from the start. Use `func azure functionapp logstream $FuncName --browser` to open **Live Metrics** in the portal.

### Step 5: Test the deployed Function (Alice again)

Call the Function running in Azure with the same name as in the local test. Because both the local and the deployed Function use the **same Azure SQL database**, the counter must continue where the local run stopped: if the local call returned `1th`, this call must return `2th`. In the terminal where you create it, set the variables again (`$Body` as in 4.3 step 4), then:

```powershell
cd C:\Dev\cybersec_terraformed\src
$ApiHost = terraform -chdir="..\infra" output -raw function_app_default_hostname
echo $ApiHost
curl.exe -X POST "https://$ApiHost/api/http_trigger" -H "Content-Type: application/json" --data "@$Body"
```

Call it a second time: the number goes up again. With Postman: **POST** `https://<hostname>/api/http_trigger`, *Body → raw → JSON*:

```json
{ "name": "Alice" }
```

Check the stored value directly in the database (set `$Server` again if needed: `$Server = terraform -chdir="..\infra" output -raw sql_server_fqdn`):

```powershell
sqlcmd -S $Server -d NameCounterDB -U secopsadmin -P "<your password>" -N -Q "SELECT name, count FROM dbo.Names;"
```

**Why does the counter increment across the local run and the cloud run?** The Function itself is stateless (each call can be served by a different instance, or by your PC); the state lives in the database. Explain in two sentences what would happen if the counter were kept in a Python variable instead.

If you receive `{"error": "Internal error."}` (HTTP 500), the application deliberately hides the cause from the caller. Use the troubleshooting reference below.

### Troubleshooting reference: read the logs (Application Insights)

> **This is not a step of the exercise. Do not run it in sequence.** Use it only when a call fails (HTTP 500), when nothing happens, or when the function list is empty after publishing.

Telemetry reaches Application Insights with a delay of a few minutes. Live Metrics is near real time. Generate a few calls first, then:

**Portal route.** Azure Portal → your Function App → *Application Insights* → *View Application Insights data* → **Logs**. Application Insights tables use lowercase names (`requests`, `traces`, `exceptions`); the same data in the Log Analytics workspace blade uses `AppRequests`, `AppTraces`, `AppExceptions`. Run:

```kusto
requests
| where timestamp > ago(30m)
| project timestamp, name, resultCode, success, duration
| order by timestamp desc
```

```kusto
exceptions
| where timestamp > ago(30m)
| project timestamp, type, outerMessage, innermostMessage
| order by timestamp desc
```

```kusto
traces
| where timestamp > ago(30m) and severityLevel >= 2
| project timestamp, severityLevel, message
| order by timestamp desc
```

Other useful views: *Failures* (grouped errors), *Live Metrics* (real time), *Transaction search* (one request with its trace and exception).

**Command-line route** (the first run may offer to install the `application-insights` CLI extension):

```powershell
$Rg  = terraform -chdir="..\infra" output -raw resource_group_name
$Appi = terraform -chdir="..\infra" output -raw app_insights_name
az monitor app-insights query --app $Appi --resource-group $Rg --analytics-query "exceptions | where timestamp > ago(30m) | project timestamp, outerMessage, innermostMessage | order by timestamp desc | take 5" -o table
```

**Triage table: what the message tells you** (typical patterns; read the exact text in your logs)

| Message contains | Likely cause | What to check |
|---|---|---|
| `Can't open lib 'ODBC Driver 18 for SQL Server'` or `file not found` | ODBC driver not available on the host (local PC: not installed; Azure: not present on the Function host) | Locally: Section 1.5. In Azure: report it to your teacher; this needs a different hosting approach or driver installation |
| `Login timeout expired`, `database ... is not currently available` | Serverless database paused or still waking up | Wait a minute and call again |
| `Cannot open server ... requested by the login. Client with IP address ... is not allowed` | SQL firewall | `AllowAzureServices` rule present (cloud)? `AllowStudentWorkstation` matches your current IP (local)? |
| `Invalid object name 'dbo.Names'` | Table not created | Redo Step 2 |
| `Login failed for user` | Wrong credentials in the connection string | Compare with `terraform.tfvars` (apply again after any change) |
| `SQL_CONNECTION_STRING is not configured` | App setting missing | Function App → *Environment variables* (cloud) or `local.settings.json` (local) |
| `Unable to create client for AzureWebJobsStorage` (local only) | Azurite not running or storage setting empty | Step 4.3, item 2 |
| Nothing at all in `requests` | Function not registered or telemetry not connected | Step 4.5; check `APPLICATIONINSIGHTS_CONNECTION_STRING` exists in *Environment variables* |

Fix the cause, republish only if code changed (`func azure functionapp publish $FuncName`), and call the API again.

---

## 6. Phase 2 — Harden

Do these one at a time and re-test with curl after each change. After each change, confirm in Application Insights (see the troubleshooting reference) that the call you expect to be rejected shows up as a handled 4xx and not as an unexpected exception.

### 6.1 Require authentication on the endpoint
Change `AuthLevel.ANONYMOUS` to `AuthLevel.FUNCTION` and republish. Calls now need the function key (`x-functions-key` header or `?code=`).

```powershell
$Rg = terraform -chdir="..\infra" output -raw resource_group_name
az functionapp keys list --name $FuncName --resource-group $Rg --query functionKeys -o json
```

Treat the key as a secret: never paste it in chat, Git or screenshots. Why is one shared function key weaker than a per-device identity? Call the endpoint without the key and find the resulting 401 in the `requests` table.

### 6.2 Validate input

```python
import re

NAME_PATTERN = re.compile(r"^[A-Za-z0-9 \-]{1,100}$")


def validate_name(raw: object) -> str:
    if not isinstance(raw, str):
        raise ValueError("name must be a string.")
    cleaned = raw.strip()
    if not NAME_PATTERN.fullmatch(cleaned):
        raise ValueError("name: 1-100 characters, letters, digits, space or hyphen only.")
    return cleaned
```

Call it before touching the database and return HTTP 400 on `ValueError`. Parameterised queries (`?`) already prevent SQL injection; validation adds a second layer and bounds accepted data. Test with a request file whose content is `{"name": "x'; DROP TABLE dbo.Names;--"}` and explain why it fails safely.

### 6.3 Move the secret to Key Vault and use Managed Identity

Add `infra\keyvault.tf`:

```hcl
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-nc-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false # lab only; enable in production
  soft_delete_retention_days = 7

  tags = azurerm_resource_group.rg.tags
}

# You (the deployer) need to write the secret.
resource "azurerm_role_assignment" "me_kv_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The Function App only needs to read secrets.
resource "azurerm_role_assignment" "func_kv_reader" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.app.identity[0].principal_id
}

resource "azurerm_key_vault_secret" "sql_conn" {
  name         = "SqlConnString"
  key_vault_id = azurerm_key_vault.kv.id
  value = join("", [
    "Driver={ODBC Driver 18 for SQL Server};",
    "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;",
    "Database=${azurerm_mssql_database.db.name};",
    "Uid=${var.sql_admin_login};Pwd=${var.sql_admin_password};",
    "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
  ])

  depends_on = [azurerm_role_assignment.me_kv_officer] # role propagation is invisible to Terraform
}
```

In `functions.tf`, replace the `SQL_CONNECTION_STRING` value with a Key Vault reference:

```hcl
"SQL_CONNECTION_STRING" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.sql_conn.versionless_id})"
```

Apply, then check in the Portal (*Function App → Environment variables*) that the reference shows as resolved. Role assignments can take a few minutes to propagate. If the reference is not resolved, the value the code receives is the literal reference text: the `traces` and `exceptions` tables will show it. Your local run is unaffected: it still uses the connection string in `local.settings.json`.

**Critical thinking:** the password is still in Terraform *state* and still a SQL login. State is protected by the private backend, but this design only moves the secret, it does not remove it. What would a passwordless design (Microsoft Entra authentication, Function Managed Identity as a SQL user) change, and what would you configure in Azure SQL to try it?

### 6.4 Least-privilege database roles

```sql
CREATE ROLE name_reader;
CREATE ROLE name_editor;

GRANT SELECT ON dbo.Names TO name_reader;
GRANT SELECT, INSERT, UPDATE ON dbo.Names TO name_editor;

CREATE USER app_reader_user WITH PASSWORD = '<generate a strong one>';
CREATE USER app_editor_user WITH PASSWORD = '<generate a strong one>';

ALTER ROLE name_reader ADD MEMBER app_reader_user;
ALTER ROLE name_editor ADD MEMBER app_editor_user;
```

Generate unique passwords (a password manager helps); never copy example passwords from documents. Store each connection string as its own Key Vault secret: the POST function gets the *editor* login, a new GET function gets the *reader* login. Then deliberately point POST at the reader login and find the permission error (`The UPDATE permission was denied` or similar) in the `exceptions` table. In 5–10 lines, explain why two narrow roles are safer than one `db_owner` account.

### 6.5 Tighten the network (discussion, optional implementation)
The `AllowAzureServices` rule (0.0.0.0) lets resources of *any* Azure customer attempt to reach your server. List the controls that reduce exposure (private endpoint, disabling public network access, VNet integration, access restrictions on the Function) and note which need a hosting plan other than Y1.

### 6.6 Monitoring as a security control (discussion)
Use the `requests` table to answer: how many calls per hour? how many rejected (4xx)? from which IPs (`client_IP`)? Which of your Phase 2 controls produces a visible signal, and which one would an attacker be able to exploit without leaving any trace? Which alert would you create first (for example a spike of 401/403 responses)? Detection and response (identify, protect, detect, respond, recover) depend on logs existing before the incident.

---

## 7. Teardown (protect your credits)

```powershell
cd C:\Dev\cybersec_terraformed\infra
terraform destroy
az group list --query "[?starts_with(name, 'rg-namecounter')].name" -o tsv
```

The second command should print nothing (the workspace and Application Insights are deleted with the resource group). The state resource group `rg-tfstate-prod` is intentionally **not** managed by this project and stays (negligible cost); delete it at the end of the course with `az group delete --name rg-tfstate-prod`.

---

## 8. Reflection (in your own words)

For each control you implemented: which attack does it stop, which property of the data does it protect (can it be read, changed, or made unavailable?), and which attack does it **not** stop? There is no answer key: the goal is to reason about a system you have never seen.

---

## 9. Beyond the Exercise: Physical Devices

A Raspberry Pi, an ESP32 or an Arduino with a network module can call the same endpoint. The device reads a sensor (temperature, speed, voltage) and sends it as JSON over HTTPS:

```python
import time
import requests

ENDPOINT = "https://<your-function-host>/api/http_trigger"
HEADERS = {"Content-Type": "application/json", "x-functions-key": "<load from a local file, never hard-code>"}


def read_speed_kmh() -> float:
    return 62.4  # replace with a real sensor reading


payload = {"name": "device-042", "reading": read_speed_kmh(), "timestamp": int(time.time())}
try:
    r = requests.post(ENDPOINT, json=payload, headers=HEADERS, timeout=5)
    print(r.status_code, r.text)
except requests.RequestException as exc:
    print("network error:", exc)
```

The same controls apply: TLS in transit, authentication, input validation, secrets outside source code, least-privilege storage, and logs you can read. Devices with little memory and compute do the minimum locally (sample, filter, summarise) and let the stateless cloud function persist the result in a database; with many devices of unpredictable activity, the serverless layer scales on demand.
