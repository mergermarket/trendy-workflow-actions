# Trendy Workflow Actions

## Approved package repositories

The reusable build and deploy workflows log in to CodeArtifact after Node.js setup and before any caller-supplied commands. Both use
`ION-Analytics/iona-central-package-repository/actions/codeartifact-login@3a00012fbc9b846824b297f1597dd227e1613b52`
with the read-only role `arn:aws:iam::159860816451:role/live-iona-central-package-repository-ci-reader`.
The action configures npm, pnpm, Yarn, pip and uv without replacing the job's AWS build/deploy credentials.

Callers must grant `id-token: write` and `contents: read` to the reusable workflow job. The reader role must trust the calling repository,
and runners need the AWS CLI, curl, python3 and network access to AWS STS and CodeArtifact.

All npm packages, including `@mergermarket` and `@ion-analytics`, use `npm-approved`. Existing default and per-scope registry entries in
the project's `.npmrc` are replaced with the approved registry; other npm settings are preserved. npm is also configured to replace
registry hosts in lockfile URLs. Registry misses fail the install rather than falling back to npmjs, GitHub Packages or JFrog.
Internal packages must be published to `npm-internal`, and third-party versions (including transitive dependencies) must be approved
before callers migrate.

The `create-npmrc`, `create-ion-analytics-npmrc` and `create-jfrog-npmrc` inputs remain accepted for compatibility but no longer select
registries or disable CodeArtifact. Existing secrets are unchanged; `NPM_JFROG_TOKEN` is no longer used for registry configuration.

### Caller responsibilities

The login applies to package managers on the runner. Callers must not override its registry settings in their commands. Yarn-specific
scoped registry settings and lockfiles, pip extra indexes, direct URL/Git dependencies and installs inside containers need migration in
the consuming repository; the login does not rewrite those files or configure container environments.
Regenerate npm lockfiles against CodeArtifact when their resolved URLs use provider-specific paths, such as GitHub Packages download
URLs: changing the registry host alone does not translate those paths to CodeArtifact package endpoints.

For Docker builds, pass the temporary npm user config as a BuildKit secret and pass the approved registry as a build argument:

```sh
docker build --secret id=npmrc,src="$NPM_CONFIG_USERCONFIG" \
  --build-arg NPM_CONFIG_REGISTRY="$NPM_CONFIG_REGISTRY" .
```

In the Dockerfile, copy the normalized project `.npmrc` alongside the package manifests, then use the secret only for the install:

```dockerfile
ARG NPM_CONFIG_REGISTRY
RUN --mount=type=secret,id=npmrc,required=true \
    NPM_CONFIG_USERCONFIG=/run/secrets/npmrc npm ci --replace-registry-host=always
```

Do not copy the temporary user config or put its token in build arguments, image layers or artifacts. Runner-level configuration is
not a network enforcement boundary; runner egress restrictions are needed to prevent arbitrary build commands bypassing CodeArtifact.
