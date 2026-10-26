# platform

Central shared repository for every repository on the personal account `jrhimself`. The repository is [`jrhimself/platform`](https://github.com/jrhimself/platform). Today it holds reusable GitHub Actions workflows and Dependabot defaults. It may hold more shared things later.

A caller invokes a workflow with a few lines. This repository holds no secrets, no hostnames, and no application details. Callers pass those at runtime, if they need them at all.

The account has no GitHub Pro and no GitHub Advanced Security. Private repositories cannot use CodeQL or GitHub secret scanning. Public repositories can.

## Pinning

Pin a caller to a release tag:

```yaml
uses: jrhimself/platform/.github/workflows/security.yml@v1
```

`v1` does not exist until the owner tags the merge commit of the first version. This repository does not create tags or releases.

A tag can move. After a release is trusted, a caller can pin that tag's commit SHA instead. Third-party actions inside these workflows are already pinned to a full commit SHA, with the release in a trailing comment. The Semgrep image and the ZAP image are pinned by digest.

Dependabot groups minor and patch updates for npm (`deps`) and GitHub Actions (`ci`). See [`templates/dependabot.yml`](templates/dependabot.yml). Hash pins stay valid only when the version comment matches the commit, which is the comment format Dependabot updates.

## security.yml

[`.github/workflows/security.yml`](.github/workflows/security.yml) runs on `workflow_call`.

| Input | Default | Role |
| --- | --- | --- |
| `visibility` | required | `public` or `private`. Checked against the event payload when GitHub sends one. |
| `node-version` | `22` | Node.js used by the CodeQL job. |
| `working-directory` | `.` | Lockfile and Semgrep root. `.` covers a whole monorepo. |
| `codeql` | `true` | CodeQL when `visibility` is `public`. Ignored for `private`. |
| `codeql-languages` | `javascript-typescript` | CodeQL language ids. |
| `scorecard` | `true` | OpenSSF Scorecard when `visibility` is `public`. Ignored for `private`. |
| `semgrep-config` | `p/javascript p/typescript` | Semgrep registry configs. |

Optional secrets, both safe to omit:

| Secret | When it matters |
| --- | --- |
| `gitleaks_license` | Organization accounts, where upstream gitleaks-action requires a license. Personal accounts leave it empty. |
| `scorecard_token` | A PAT with extra read scope. Without it, Scorecard uses the workflow token and the Branch-Protection check is inconclusive. |

Jobs:

| Job | Always | Failure |
| --- | --- | --- |
| gitleaks | Yes | A secret in the commits of a `pull_request` or `push`. `workflow_dispatch` and `schedule` scan the tree the action checks out. |
| dependencies | Yes | OSV finds a high or critical vulnerability, or it does not write a results file. Medium, low, and unscored findings are printed and do not fail the job. |
| semgrep | Yes | Any finding from the configured JavaScript and TypeScript packs. Metrics are off, and no Semgrep token is set. |
| actionlint | Yes | Invalid workflow syntax. |
| zizmor | Yes | A workflow audit finding. Annotations are on. Code scanning upload is off, so private repositories and Dependabot do not need Advanced Security. |
| codeql | `visibility: public` and `codeql: true` | The analysis itself errors. Findings are uploaded to code scanning and do not fail the job by themselves. |
| scorecard | `visibility: public` and `scorecard: true` | The Scorecard run errors. The numeric score does not fail the job. Results are published to the OpenSSF API only on a push to the default branch. |

`working-directory` does not apply to gitleaks, CodeQL, Scorecard, actionlint, or zizmor. Those read the whole repository.

Call this workflow from `pull_request`, `push`, `workflow_dispatch`, or `schedule`. gitleaks-action rejects other event names.

### Public and private

`visibility: public` adds CodeQL (`github/codeql-action`) and OpenSSF Scorecard (`ossf/scorecard-action`). `visibility: private` skips both. Passing `public` for a private repository fails the preflight job before CodeQL starts, because a free private repository cannot upload CodeQL results.

For a public repository, turn on **Secret scanning** and **Push protection** under Settings → Code security. Those are repository settings, not workflows, and they are not available on a private repository without GitHub Advanced Security. gitleaks covers committed secrets on both kinds of repository.

### Dependabot

Dependabot pull requests do not receive repository secrets. Every secret in these workflows is optional and `required: false`. An empty license or an empty Scorecard token does not fail the run.

Dependabot's token is read-only. CodeQL still analyzes the code and skips the SARIF upload. Scorecard still runs and skips the SARIF upload. gitleaks does not try to comment on the pull request. ZAP does not open an issue.

### Permissions

A caller that sets `permissions` puts a ceiling on the called workflow. Grant every scope the jobs you run declare:

- Every caller: `contents: read`, and `pull-requests: read` for gitleaks on pull requests.
- Public CodeQL: also `actions: read` and `security-events: write`.
- Public Scorecard: also `id-token: write` (publish) and `security-events: write` (SARIF upload).

A caller that omits `permissions` uses the permissions declared on each job in the reusable workflow.

### Caller

A public Node monorepo, from [`examples/public-caller.yml`](examples/public-caller.yml):

```yaml
jobs:
  security:
    uses: jrhimself/platform/.github/workflows/security.yml@v1
    with:
      visibility: public
      node-version: "22"
      working-directory: .
    secrets:
      gitleaks_license: ${{ secrets.GITLEAKS_LICENSE }}
      scorecard_token: ${{ secrets.SCORECARD_TOKEN }}
```

A private repository uses the same job with `visibility: private` and can omit both secrets. The full private caller is [`examples/private-caller.yml`](examples/private-caller.yml).

## e2e.yml

[`.github/workflows/e2e.yml`](.github/workflows/e2e.yml) installs dependencies, installs Playwright browsers, runs a command, and uploads the HTML report even when the tests fail.

| Input | Default |
| --- | --- |
| `node-version` | `22` |
| `working-directory` | `.` |
| `install-command` | `npm ci` |
| `command` | `npx playwright test` |
| `playwright-install-args` | `--with-deps` |
| `report-path` | `playwright-report` |
| `artifact-name` | `playwright-report` |

`working-directory` is the directory of `package.json`. Use `e2e` when that folder is its own package. When the lockfile is at the repository root and the tests live in `e2e/`, keep `working-directory` as `.` and set `command` to `npx playwright test --config e2e/playwright.config.ts`.

The HTML report is uploaded only when Playwright writes it. In `playwright.config`, use an HTML reporter that does not open a browser, or CI will wait on that server:

```ts
reporter: [["html", { open: "never" }], ["list"]],
```

There is no npm cache. `npm ci` runs on every job, which keeps fork and Dependabot runs from depending on a cache write. The workflow reads no secrets. A test that needs a token of its own has to be started by a caller job that has that token; this workflow cannot see it.

## zap-baseline.yml

[`.github/workflows/zap-baseline.yml`](.github/workflows/zap-baseline.yml) runs `zaproxy/action-baseline` against `target-url`.

| Input | Default | Role |
| --- | --- | --- |
| `target-url` | required | Absolute `http` or `https` URL. |
| `fail-on-high` | `false` | Report-only unless this is `true`, in which case a High alert fails the job. |
| `artifact-name` | `zap-baseline` | Artifact holding the HTML, Markdown, and JSON reports. |

Medium, low, and informational alerts do not fail the job. The URL is an input so nothing about a deployed application is stored here. Dispatch it with a URL, or pass a preview URL from a deploy job. Do not commit the URL.

## Dependabot template

Copy [`templates/dependabot.yml`](templates/dependabot.yml) to `.github/dependabot.yml`.

- npm and `github-actions`
- weekly, Monday, 06:00, `Europe/Amsterdam`
- minor and patch updates grouped into one pull request per ecosystem
- major updates left ungrouped
- commit prefixes `deps` and `ci`

Duplicate the npm block with another `directory` when a repository has more than one lockfile root. This repository does not install that file: there is no package manifest here, and a live npm entry would fail.

## What stays in the application repository

These workflows do not replace an application acceptance suite. A Node test job that builds and runs the suite stays next to the code.

A denylist that must fail when its secret is absent stays in the application repository as well. This repository cannot hold that secret, and a reusable job that failed closed without it would be red on every fork and every Dependabot pull request.

## This repository

Shared files for `jrhimself` repositories live here. [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs actionlint and zizmor on the workflows in this repository. It does not call `security.yml`. There is no lockfile for OSV and no language for CodeQL to extract.

## First version

After this change is merged, tag that commit `v1` and publish the release from the GitHub UI or the `gh` CLI. Callers pinned to `@v1` stay dark until that tag exists. Do not tag from the pull request that adds the workflows.

## Limitations

- Private consumer repositories were not readable while these workflows were written. The end-to-end workflow matches a conventional npm Playwright layout, including a package in `e2e/`, and the command is overridable.
- `visibility` is an input. Preflight rejects it when the event payload disagrees. A caller that lies, and whose event has no visibility field, can still request the public jobs.
- CodeQL findings do not fail the workflow. They show up in code scanning on public repositories, except on Dependabot pull requests, where the upload is skipped because the token cannot write security events.
- Scorecard does not fail on a low score. SARIF upload is best-effort so a repository with code scanning still turned off does not go red. Publishing to the OpenSSF API happens on a push to the default branch.
- OSV fails the job for high and critical CVSS scores (7.0 and above), and for a GitHub advisory severity of high or critical when the score is missing. Unscored advisories are listed and do not fail the job. The upstream action turns a missing lockfile into a warning and exit 0; this workflow still fails that case, because the results file is absent.
- Semgrep fails on any finding from the packs you configure, not only high severity. The registry has to be reachable. No application token is sent to Semgrep.
- gitleaks comments are disabled. A leak still fails the job and is in the log, with redaction. If the action cannot tell a personal account from an organization, upstream requires `gitleaks_license` and the job fails closed. That lookup uses the workflow token against the public user API.
- The ZAP action's own `fail_action` input fails on any alert, including warnings. This workflow leaves it false and fails only for High (`riskcode` 3) when `fail-on-high` is true. A scan that cannot reach the URL still fails.
- zizmor in `security.yml` allows `jrhimself/platform/*` to be pinned by tag. Every other action must be pinned by commit SHA. `ref-confusion` can still flag a tag that shares its name with a branch, so do not create a branch named `v1`.
- actionlint in a caller resolves `@v1` over the network. Until the tag exists, that job fails.
- Playwright's HTML report is not created by the default `list` reporter. The upload warns instead of failing when the directory is missing, so a green run with the wrong reporter does not leave a report artifact.
