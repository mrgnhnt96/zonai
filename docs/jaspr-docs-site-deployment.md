# Deploying a Jaspr docs site to a custom domain on GitHub Pages

Companion to [`jaspr-docs-site-playbook.md`](./jaspr-docs-site-playbook.md).
This is the deployment half, written from actually doing it for
`docs.zonai.dev`.

---

## The constraint that shapes everything

**A GitHub Pages site can carry exactly one custom domain, and a repository has
exactly one Pages site.**

So a monorepo that wants `example.com` for a marketing site *and*
`docs.example.com` for docs cannot serve both from its own Pages. You need a
second repository.

This is easy to discover the hard way. In our case the `zonai` repo's Pages
custom domain was `example.com` (apex) and it was serving the docs. Adding
`apps/docs/web/CNAME` containing `docs.example.com` and deploying would have
*reassigned* the repo's Pages domain to the subdomain — taking the live apex
down, with no other repo ready to claim it.

Check before you deploy:

```sh
gh api repos/OWNER/REPO/pages \
  -q '{cname:.cname, status:.status, cert:.https_certificate.state}'
curl -sI https://your-domain/ | head -3
curl -s https://your-domain/ | grep -o '<title>[^<]*</title>'   # what is actually there?
```

If `cname` is already something you care about, do **not** publish an artifact
containing a different `CNAME` file.

---

## The pattern: build here, publish there

The monorepo builds; a small artifact repository holds the built output and
owns the domain.

```
mrgnhnt96/zonai          source monorepo. Pages -> zonai.dev
  apps/docs/                 the Jaspr site
  .github/workflows/
    deploy-docs.yml          builds apps/docs, force-pushes output ->
                                                                    │
mrgnhnt96/zonai-docs     artifact repo. Pages -> docs.zonai.dev  <──┘
  (single orphan commit, replaced every deploy)
```

Why an artifact repo rather than `peaceiris/actions-gh-pages` on a `gh-pages`
branch in the same repo: the branch still shares the *repo's* single Pages
site, so it does not solve the one-domain problem. A separate repo does.

The target repo's history carries no information — it is derived output — so
each deploy is a fresh orphan commit, force-pushed. That keeps it from growing
unboundedly with binary diffs of compiled JS.

---

## One-time setup

### 1. Create the artifact repo

```sh
gh repo create OWNER/PROJECT-docs --public \
  --description "Published output of the docs site (apps/docs in OWNER/PROJECT). Do not edit by hand."
```

Public matters: Pages on private repos requires a paid plan, and there is
nothing secret in a published docs site.

### 2. Put `CNAME` in `web/`

`apps/docs/web/CNAME`, containing exactly the hostname:

```
docs.example.com
```

Jaspr copies everything in `web/` to `build/jaspr/`, so it lands at the root of
the published artifact, which is where Pages reads it. **If this file ever goes
missing from a deploy, the custom domain is silently unset** — hence the
verification step in the workflow below.

### 3. DNS

```
docs.example.com.   CNAME   OWNER.github.io.
```

Point at `OWNER.github.io` even for a project page; GitHub routes by the
custom-domain setting, not the hostname. Verify with `dig +short docs.example.com CNAME`
before deploying — Pages will not issue a certificate until DNS resolves.

### 4. First publish, then enable Pages

Push content *before* enabling Pages, or the first build has nothing to build.

```sh
cd apps/docs && dart run tool/build_search_index.dart && dart run jaspr_cli:jaspr build

rm -rf /tmp/publish && mkdir -p /tmp/publish
rsync -a --exclude '.dart_tool' --exclude '.build.manifest' build/jaspr/ /tmp/publish/
cd /tmp/publish
test -s index.html && grep -qx 'docs.example.com' CNAME
touch .nojekyll
git init -q -b main && git add -A && git commit -q -m "Initial deploy"
git push -q --force "https://x-access-token:${GITHUB_TOKEN}@github.com/OWNER/PROJECT-docs.git" main
```

`.nojekyll` matters: Pages runs Jekyll by default, which drops any path segment
starting with `_`. Jaspr does not currently emit such paths, but the file costs
nothing and the failure mode is a confusing 404.

Then:

```sh
gh api -X POST repos/OWNER/PROJECT-docs/pages -f 'source[branch]=main' -f 'source[path]=/'
```

It reads the `CNAME` file from the pushed content and sets the custom domain
itself — no separate call needed.

### 5. Wait for the certificate, then force HTTPS

```sh
gh api repos/OWNER/PROJECT-docs/pages \
  -q '{status:.status, cert:.https_certificate.state, domain:.protected_domain_state}'
```

Ours went `building/authorized` → `building/approved` → `built/approved` in
about 30 seconds; a few minutes is normal.

`https_enforced` must be sent as a real boolean — `-f` stringifies and the API
rejects it with `"true" is not of type boolean`:

```sh
gh api -X PUT repos/OWNER/PROJECT-docs/pages --input - <<'JSON'
{"https_enforced": true}
JSON
```

### 6. Deploy credential — use a deploy key, not a PAT

The workflow in the source repo needs write access to the artifact repo.

**Do not reuse a classic PAT.** Anything carrying `repo`, `admin:org` or
`delete_repo` becomes a full-account credential sitting in CI, readable by
every workflow the repo runs. A fine-grained PAT scoped to the one repo is
acceptable — but **it cannot be created programmatically**: GitHub has no API
for minting personal access tokens, and the old OAuth Authorizations API was
removed. It is a UI-only flow.

A **write deploy key** is scoped to a single repository by construction, is
strictly narrower than any PAT, and *is* creatable from the API:

```sh
ssh-keygen -t ed25519 -N "" -C "PROJECT-docs deploy key" -f /tmp/docs_deploy_key -q

gh api -X POST repos/OWNER/PROJECT-docs/keys \
  -f title="CI deploy (deploy-docs.yml)" \
  -f key="$(cat /tmp/docs_deploy_key.pub)" \
  -F read_only=false

gh secret set DOCS_DEPLOY_KEY --repo OWNER/PROJECT < /tmp/docs_deploy_key

shred -u /tmp/docs_deploy_key /tmp/docs_deploy_key.pub 2>/dev/null \
  || rm -f /tmp/docs_deploy_key /tmp/docs_deploy_key.pub
```

`-F read_only=false` (not `-f`) — `-f` sends the string `"false"`, which is
truthy, and you get a read-only key that fails at push time.

Prove it can write before trusting CI to it. A successful `git push` that
reports `Everything up-to-date` only proves *authentication*; force-push a real
commit to prove *authorization*:

```sh
GIT_SSH_COMMAND="ssh -i /tmp/docs_deploy_key -o IdentitiesOnly=yes" \
  git push --force git@github.com:OWNER/PROJECT-docs.git main
```

Rotate by deleting the key under the artifact repo's *Settings → Deploy keys*
and repeating the above.

---

## The workflow

Living version: `.github/workflows/deploy-docs.yml`. Structure and the reasons
for each guard:

```yaml
on:
  push:
    branches: [main]
    paths: ["apps/docs/**", "pubspec.yaml", "pubspec.lock",
            "pubspec_overrides.yaml", ".github/workflows/deploy-docs.yml"]
  workflow_dispatch:

permissions:
  contents: read          # the deploy uses DOCS_DEPLOY_KEY, not GITHUB_TOKEN

concurrency:
  group: docs
  cancel-in-progress: true
```

Steps:

1. **Checkout** — with `submodules: recursive` and a PAT if any submodule is
   private; `GITHUB_TOKEN` cannot read them.
2. **Set up Dart**, resolve deps.
3. **`dart analyze --fatal-infos`**.
4. **Regenerate the search index.** Do not trust the committed copy, even
   though a test also checks it — a deploy should never ship a stale index.
5. **Build.**
6. **Run tests after the build**, so the anchor test can check every search
   result's deep link against the HTML that is about to be published.
7. **Verify the build output** (below).
8. **Publish** as an orphan commit, force-pushed.

### The verification step earns its place

A silently-empty or partial build otherwise publishes a blank site over a
working one, and a missing `CNAME` un-sets the custom domain:

```yaml
- name: Verify build output
  working-directory: apps/docs/build/jaspr
  run: |
    test -s index.html || { echo "::error::index.html missing or empty"; exit 1; }
    grep -qx "$DOCS_DOMAIN" CNAME || {
      echo "::error::CNAME missing or wrong: $(cat CNAME 2>/dev/null)"; exit 1; }
    test -s search-index.json || {
      echo "::error::search-index.json was not published"; exit 1; }
    pages=$(find . -name index.html | wc -l)
    [ "$pages" -ge 70 ] || {
      echo "::error::only $pages pages rendered; expected the full site"; exit 1; }
```

Tune the page count to your site. A content-shaped assertion
(`grep -q 'Your schema' index.html`) is worth adding too — it catches a build
that renders the shell but not the content.

---

## Serving from a subpath instead

If you keep the docs on `OWNER.github.io/REPO/` rather than a custom domain,
two extra things apply. Both were verified working before the domain move.

Append a base path to `site.yaml` at build time:

```yaml
- run: printf '\nbase: /%s/\n' "${{ github.event.repository.name }}" >> apps/docs/content/_data/site.yaml
```

Jaspr emits `<base href="/REPO/">`, but root-absolute `href="/…"` in rendered
markdown still needs rewriting:

```bash
repo="${BASE_PATH#/}"
find build/jaspr -name '*.html' -print0 |
  xargs -0 perl -pi -e 's#(href|src)="/(?!'"${repo}"'/)#${1}="'"${BASE_PATH}"'/#g'
```

The negative lookahead matters — a naive `s|href="/|href="/repo/|` doubles
already-prefixed paths into `/repo/repo/`.

**Client-rendered links are not covered by that rewrite**, since they do not
exist at build time. Resolve them against the base at runtime:

```dart no-analyze
Uri.parse(web.document.baseURI).resolve(path)
```

This is why the search component stores root-absolute hrefs and resolves on
click: identical code works at a domain root and under a subpath.

Fragments survive the trailing-slash redirect. Navigating to
`/operations/streaming#prefer-zonai_client` 301s to
`…/streaming/#prefer-zonai_client` and still scrolls to the heading — browsers
carry the fragment across a redirect whose target has none.

---

## Verifying a deploy

Status codes are not enough — they were all `200` while the search dialog was
2 pixels tall.

```sh
for u in / /search-index.json /operations/streaming/ /llms.txt; do
  printf "%-26s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' "https://docs.example.com$u")"
done
curl -s https://docs.example.com/ | grep -o '<title>[^<]*</title>'
curl -sI http://docs.example.com/ | head -2          # expect 301 -> https
```

Then run the CDP browser check (playbook §7) against the **production URL**.
Ours asserts hydration, ⌘K, index fetch, result count, highlighting, arrow
keys, Enter-navigates, Esc-closes, and the sidebar's open-group count. And take
a screenshot.

Finally, confirm you did not disturb anything else:

```sh
gh api repos/OWNER/PROJECT/pages -q .cname       # the source repo's domain
curl -s https://example.com/ | grep -o '<title>[^<]*</title>'
```

---

## Rollback

The artifact repo holds one commit, so rollback is a rebuild-and-republish of a
known-good source commit, or a force-push of the previous artifact if you kept
it. If a bad deploy removed `CNAME`, the custom domain is unset: republish with
the file present, then re-check `gh api repos/OWNER/PROJECT-docs/pages -q .cname`
and re-enable `https_enforced`.
