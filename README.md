# CI/CD Reference Layout

Minimal Azure DevOps + Terraform layout for: **3 pipelines (test, dev, prod)**, where **prod deploys the same code to 4 subscriptions** as 4 stages.

Hand this folder to an AI agent and tell it: **"match this layout, don't invent structure not present here."**

## Start here (before you generate any more Terraform)

If you're generating Terraform from a spec and running it manually per environment, **stop and read this section first**. Picking the right TF layout *before* you generate more code saves a regeneration cycle later.

### Which Terraform layout pattern should I use?

There are four common patterns. For your shape (same deployment, 6 environments, values differ between them), the answer is **single root module + var-files** — what this reference uses. Here's why, and what the alternatives buy you:

| Pattern | What it is | When it's right | When it's wrong |
|---|---|---|---|
| **Single root + var-files** ✅ | One set of `.tf` files, one `.tfvars` per env, one state file per env | Same resources in every env, values differ. **Your case.** | Envs genuinely have different *resources* (not just different values) |
| Single root + workspaces | Same code, `terraform.workspace` switches behaviour, state keyed by workspace | You want CLI-level env switching without var-files | You want CI/CD — workspaces add magic agents handle poorly, no upside over var-files |
| Dir-per-env | Separate root module per env | Envs diverge structurally (different resources, not just values) | You'd be copy-pasting 90% of the code — that's a smell, collapse to var-files |
| Terragrunt / stacks | DRY tooling layered on TF | Many envs **and** many components **and** the team has Terragrunt experience | You're still finding your feet — extra dependency, extra learning curve |

**Rule of thumb:** if your 6 envs deploy the *same* resources with *different* values, var-files. If they deploy *different* resources, you have 6 products, not 6 envs.

### Before you generate more Terraform, do this

1. **List your environments** — you already have these: `test`, `dev`, `prod-env-1..4`.
2. **List what differs between them.** Walk through the spec and tag every value with "same everywhere" vs "differs per env." The differing ones become variables; the same-everywhere ones stay hardcoded. Typical "differs" list:
    - Subscription ID, tenant ID
    - Region / location
    - Resource naming prefix
    - SKU / size / capacity
    - Replica counts, autoscale bounds
    - DNS names, custom domains
    - Feature toggles (e.g. "deploy monitoring stack: yes/no")
    - Tag values
3. **Decide your naming convention now** — once, for all envs. Changing it later means renaming resources in state, which is painful. Pick a pattern like `{region}-{env}-{type}-{name}-{nn}` and stick to it.
4. **Pick your state backend now** — one storage account, one container, one blob per env (`<env>.tfstate`). Create it manually before any pipeline runs; bootstrapping state storage from inside a pipeline is a chicken-and-egg problem not worth solving.

Only **after** these four are decided should you generate Terraform.

### How to tell your spec-to-TF generator to emit the right shape

When you prompt your generator (or AI agent doing the generation), include these constraints verbatim:

> "Generate **one root module** under `devops/terraform/main/`. Do not generate per-environment directories or use workspaces.
>
> Every value that differs between environments must be declared as a `variable` in `variables.tf` (no default) and supplied via `.tfvars` files under `devops/terraform/environments/`. Hardcode values that are the same in every environment.
>
> The `provider \"azurerm\"` block must **not** have a hardcoded `subscription_id`. The pipeline's service connection determines the target subscription.
>
> The `terraform { backend \"azurerm\" {} }` block must be empty (partial backend). The pipeline injects the backend config at init time.
>
> For each environment in this list — `test`, `dev`, `prod-env-1`, `prod-env-2`, `prod-env-3`, `prod-env-4` — produce a matching `.tfvars` file with every variable populated.
>
> Do not generate pipeline YAML; that comes from a separate reference layout."

The "do not generate pipeline YAML" line matters — otherwise the generator invents its own CI/CD shape that fights this one.

### Then come back here

Once you have generated TF in the shape above, follow the **"Adapting your existing Terraform"** section below to verify the shape is right, then add the pipeline files from `devops/pipelines/`.

---

## Shape

```
devops/
├── pipelines/
│   ├── test.yml              # pipeline 1: deploys to `test`
│   ├── dev.yml               # pipeline 2: deploys to `dev`
│   ├── prod.yml              # pipeline 3: deploys to prod-env-1..4 (4 stages)
│   └── templates/
│       └── deploy-stage.yml  # shared stage template — used by all 3 pipelines
└── terraform/
    ├── main/                 # the Terraform code (single root module)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── backend.tf        # partial backend — key passed in at init time
    └── environments/
        ├── test.tfvars
        ├── dev.tfvars
        ├── prod-env-1.tfvars
        ├── prod-env-2.tfvars
        ├── prod-env-3.tfvars
        └── prod-env-4.tfvars
```

## Rules the agent must follow

1. **One template, many callers.** `deploy-stage.yml` is the only place that knows how to run terraform. The 3 pipelines just invoke it with different parameters.
2. **One tfvars per environment.** Environment differences live in `.tfvars` only — never in pipeline YAML.
3. **One state file per environment.** Backend `key` is set per-stage at `terraform init` time. Never share state.
4. **One service connection per subscription.** Naming convention: `sc-<env>` (e.g. `sc-prod-env-1`). The stage template picks the connection by parameter.
5. **Approvals live in ADO Environments**, not in pipeline YAML. Create an Environment per env name; gate prod-env-1..4 with approvers in the ADO UI.
6. **Secrets come from a variable group or Key Vault**, never from tfvars. Each env has its own variable group named `vg-<env>`.

## Adapting your existing Terraform

This repo does **not** ship Terraform for you to deploy. The `main.tf` here is a placeholder (one resource group) purely to show the wiring works. You bring your own Terraform; the steps below convert it to fit this layout.

**Do these in order. Don't skip steps — each one assumes the previous is done.**

### 1. Locate your root module

The root module is the directory you run `terraform init` from — it has `*.tf` files and (after init) a `.terraform/` directory. **Everything below applies to this directory only.** Modules it calls under `modules/` are fine as-is.

If you currently have **one directory per environment** (e.g. `terraform/dev/`, `terraform/prod/`) or use **workspaces**, stop and read the "Migration shapes" section at the bottom — those are real migrations, not renames.

### 2. Convert the backend to partial config

Find your `terraform { backend "azurerm" { ... } }` block. Replace the contents with an **empty** block:

```hcl
terraform {
  backend "azurerm" {}
}
```

The pipeline passes `storage_account_name`, `container_name`, `resource_group_name`, and `key` via `-backend-config` flags at init time. Hardcoded values fight the pipeline.

If state already exists, run `terraform init -migrate-state` **once locally** against the new partial config before the pipeline ever runs. Skipping this loses state.

### 3. Find every env-specific value

This is the bit agents under-do. Walk every `.tf` file in the root module and list every value that **differs between environments**. Common culprits:

- Subscription ID, tenant ID
- Region / location
- Resource name prefixes (`dev-app-rg` vs `prod-app-rg`)
- SKU sizes (`Standard_B2s` in dev, `Standard_D4s_v5` in prod)
- Replica counts, capacity, autoscale min/max
- DNS names, custom domains
- Toggles (whether to deploy monitoring, whether public access is allowed)
- Tag values (`environment = "dev"`)

Hardcoded subscription IDs in `provider` blocks are the #1 cause of "why did prod deploy to dev." Find them all.

### 4. Promote each one to a variable

For every value on the list:

1. Add a `variable "x" { type = ... }` block in `variables.tf`.
2. Replace the hardcoded value in the resource with `var.x`.
3. Add `x = "..."` to **every** tfvars file with the right per-env value.

Rule of thumb: if a value is the same in all 6 environments, leave it hardcoded. If it differs in even one, promote it.

### 5. Verify tfvars completeness

Every variable declared in `variables.tf` without a `default` must appear in **every** tfvars file. Missing entries silently fall through to whatever the agent guessed, which is rarely what you want.

Quick check: `grep '^variable' *.tf` should produce the same set of names as the keys in each `.tfvars`.

### 6. Do not touch

- Module definitions under `modules/`.
- Resource bodies beyond swapping literals for `var.x`.
- Provider versions, lock files, or `required_version`.
- Any `*.tfstate*` file — ever. State moves happen via `terraform state mv`, not file edits.

### Migration shapes that need extra care

If your current layout is **one dir per env**, you're collapsing N root modules into 1. Each old dir's state needs to be migrated into a new per-env state file under the unified backend. This is `terraform state pull` from the old + `terraform state push` to the new, per env. Do it once, locally, with backups. Do not let an agent run this unsupervised.

If your current layout uses **workspaces**, you're moving from `terraform.workspace`-based logic to var-files. Every reference to `terraform.workspace` in code becomes `var.env_name`. State migrates with `terraform workspace select <name>` + `state pull/push` into the new keyed backend.

If your current layout has **hardcoded subscription IDs in `provider` blocks**, remove them. The pipeline's service connection determines the target subscription; a hardcoded `subscription_id` in the provider will override it and deploy to the wrong place.

## What's intentionally NOT here

- No app code, no modules, no real resources. The point is the **wiring**, not the workload.
- No multi-repo, no separate plan/apply pipelines, no drift detection. Add those later if needed.
