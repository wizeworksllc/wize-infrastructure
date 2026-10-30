# -----------------------------------------------------------------------------
# The id-qualified OIDC subjects of every product repository in wizeworksllc.
#
# The product repositories moved from the brandonkorous user to the wizeworksllc
# org on 2026-10-30 (docs/org-move.md). Each deploy identity trusts an OIDC
# subject that names the repository's OWNER, and Entra matches it exactly, so
# the new subjects were trusted here BEFORE any repository moved.
#
# Every moved repository was read afterwards
#   gh api repos/wizeworksllc/<repo>/actions/oidc/customization/sub
# and every one mints the id-qualified form below:
#
#   repo:wizeworksllc@<org id>/<repo>@<repo id>
#
# That is the subject every product logs in with, and this file is its home.
# The `plain` form (repo:wizeworksllc/<repo>) is trusted too. No repository
# mints it today; it is the form a repository falls back to if its OIDC
# customization is ever reset.
#
# The per-product *_github_subject_prefix defaults still name the old
# brandonkorous subjects, which nothing mints any more. They are dead but
# harmless. Pointing them at a wizeworksllc form collides with a credential
# here (Entra refuses two credentials with one subject on one app), so that
# cleanup deletes credentials and needs a release with
# allow_infrastructure_destroy. A person runs that one.
#
# A NEW product repository: add it to org_move_repos with its numeric id
# (gh api repos/wizeworksllc/<repo> --jq .id).
# -----------------------------------------------------------------------------

locals {
  org_move_owner  = "wizeworksllc"
  org_move_org_id = "350084568"

  org_move_repos = {
    sparx = {
      enabled  = true
      app      = azuread_application.gha.id
      repo     = "sparx"
      repo_id  = "1251494871"
      subjects = ["ref:refs/heads/main", "pull_request", "environment:${var.environment}"]
    }
    kanninja = {
      enabled  = local.kanninja_count > 0
      app      = try(azuread_application.kanninja_gha[0].id, "")
      repo     = "kanninja"
      repo_id  = "1208384367"
      subjects = concat([for b in var.kanninja_github_branches : "ref:refs/heads/${b}"], ["environment:prod"])
    }
    jotacular = {
      enabled  = local.jotacular_count > 0
      app      = try(azuread_application.jotacular_gha[0].id, "")
      repo     = "jotdojo"
      repo_id  = "1341839746"
      subjects = concat([for b in var.jotacular_github_branches : "ref:refs/heads/${b}"], ["environment:prod"])
    }
    rocketease = {
      enabled  = local.rocketease_count > 0
      app      = try(azuread_application.rocketease_gha[0].id, "")
      repo     = "RocketEase"
      repo_id  = "1350407459"
      subjects = concat([for b in var.rocketease_github_branches : "ref:refs/heads/${b}"], ["environment:prod"])
    }
    agconn = {
      enabled  = local.agconn_count > 0
      app      = try(azuread_application.agconn_gha[0].id, "")
      repo     = "AgConnect"
      repo_id  = "1226714101"
      subjects = concat([for b in var.agconn_github_branches : "ref:refs/heads/${b}"], ["environment:prod"])
    }
    wizelens = {
      enabled  = local.wizelens_count > 0
      app      = try(azuread_application.wizelens_gha[0].id, "")
      repo     = "wizelens"
      repo_id  = "1421677864"
      subjects = ["ref:refs/heads/main", "environment:prod"]
    }
    wizeworks = {
      enabled  = local.wizeworks_count > 0
      app      = try(azuread_application.wizeworks_gha[0].id, "")
      repo     = "wizeworks"
      repo_id  = "1349021052"
      subjects = concat([for b in var.wizeworks_github_branches : "ref:refs/heads/${b}"], ["environment:prod"])
    }
  }

  org_move_credentials = merge([
    for product, r in local.org_move_repos : merge([
      for form, prefix in {
        plain = "repo:${local.org_move_owner}/${r.repo}"
        id    = "repo:${local.org_move_owner}@${local.org_move_org_id}/${r.repo}@${r.repo_id}"
        } : {
        for s in r.subjects : "${product}/${form}/${s}" => {
          app     = r.app
          repo    = r.repo
          form    = form
          scope   = s
          subject = "${prefix}:${s}"
        }
      }
    ]...) if r.enabled
  ]...)
}

resource "azuread_application_federated_identity_credential" "org_move" {
  for_each = local.org_move_credentials

  application_id = each.value.app
  display_name   = "wizeworksllc-${each.value.form}-${replace(each.value.scope, "/[^A-Za-z0-9-]/", "-")}"
  description    = "${each.value.scope} in ${local.org_move_owner}/${each.value.repo} (${each.value.form} subject form), trusted ahead of the org move."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value.subject
}
