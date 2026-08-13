# Deploying

Build your site and publish it to a static host.


## Overview

Saga generates a pure static website: HTML files, and the images, stylesheets and scripts that go with them. There is no server-side component and no runtime requirement — Swift is needed to build your site, not to serve it. That means you can host the result anywhere: GitHub Pages, Netlify, Cloudflare Pages, Vercel, or any plain web server.


## Building your site locally

From your website folder, run:

```shell-session
$ saga build
```

This runs your pipeline once and writes the result to your output folder (`deploy` by default). Everything in there is a static file, so publishing your site is a matter of uploading that folder to your web host.

> Important: ``Saga/run()`` deletes the output folder at the start of every build. Everything you want published has to be produced by your pipeline, or live in your input folder as a static file (as those are copied over automatically). Never keep hand-made files in your output folder; they won't survive the next build.

### Committing your built site

GitHub Pages can serve straight from a branch, which makes committing your output folder a complete publishing setup on its own. It can only serve from the repository root or from a folder named `docs`, so point Saga's output at the latter:

```swift
try await Saga(input: "content", output: "docs")
```

Make sure the `docs` folder isn't in your `.gitignore`, then go to **Settings → Pages → Build and deployment**, set **Source** to **Deploy from a branch**, and pick your branch with the `/docs` folder. From then on, publishing is `saga build` followed by a commit and a push. The tradeoff is that your repository now carries generated files.

Instead of manually building your site on your own computer, it's more convenient to automatically build and deploy your website whenever you commit changes. Examples for GitHub Pages and Cloudflare Pages are given below.


## Deploying to GitHub Pages

GitHub Pages can serve your output folder straight from a workflow.

First, a one-time repository setting: go to **Settings → Pages → Build and deployment**, and set **Source** to **GitHub Actions**. Without this, the deploy step fails.

Then create `.github/workflows/deploy.yml`:

```yaml
name: Deploy site

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build site
        run: swift run

      - name: Setup Pages
        uses: actions/configure-pages@v4

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: "./deploy"

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

> Note: You don't need to install `saga` CLI on a build server: `saga build` is a convenience wrapper that runs `swift run`.

The `path` of the upload step has to match the `output` folder you passed to `Saga(input:output:)`.

All three permissions are required: `contents: read` for the checkout, `pages: write` to publish, and `id-token: write` for the deploy action's OIDC token. The `concurrency` group keeps two pushes in quick succession from racing each other to publish.


## Deploying to Cloudflare Pages

Cloudflare publishes a site by uploading a directory with wrangler, its command line tool. There's an official GitHub action that wraps it, so deploying is one step on the end of the build.

First, create a Pages project in the Cloudflare dashboard, choosing **Direct Upload** rather than a Git connection, since the build already happens in Actions. Then store your Cloudflare API token and account ID as repository secrets, and create `.github/workflows/deploy.yml`:

```yaml
name: Deploy site

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build site
        run: swift run

      - name: Deploy to Cloudflare Pages
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: pages deploy deploy --project-name=my-site
```

> Note: The second `deploy` in the command is Saga's output folder. If you renamed your output folder, change the command as well.


## Other hosts

Since the output folder is nothing but static files, any host will do.

Some hosts can skip building with GitHub Actions entirely since they build your site for you. For example Netlify's build image includes a Swift toolchain, so you can point it at your repository directly. Set the build command to `swift run` and the publish directory to `deploy`, and it'll build and deploy the site when you push your changes.
