# SEO Audit Action

Run automated SEO audits on your website as part of your CI/CD pipeline. Catch SEO regressions before they ship to production.

Powered by [SEO Score API](https://seoscoreapi.com): 80+ checks across meta, technical, social, performance, accessibility and AI readability, plus an optional **Deep Site Audit**.

## Usage

```yaml
- name: SEO Audit
  uses: SeoScoreAPI/seo-audit-action@v1
  with:
    url: "https://your-site.com"
    api-key: ${{ secrets.SEO_SCORE_API_KEY }}
    threshold: 85
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `url` | Yes | — | URL to audit |
| `api-key` | Yes | — | API key from [seoscoreapi.com](https://seoscoreapi.com) |
| `threshold` | No | `80` | Minimum score to pass (0-100) |
| `fail-on-threshold` | No | `true` | Fail build if below threshold |
| `deep-audit` | No | `false` | Also run a Deep Site Audit (Pro/Ultra, or a Deep Audit credit) |
| `deep-audit-business-type` | No | — | `saas` \| `local_service` \| `ecommerce` \| `storefront` \| `blog` \| `publisher` |
| `deep-audit-timeout` | No | `600` | Seconds to wait for the Deep Site Audit |
| `deep-audit-fail-on-high` | No | `false` | Fail the build on any high/critical Deep Site Audit finding |
| `deep-audit-base-url` | No | `https://seoscoreapi.com` | Deep Site Audit host override (proxy, or the legacy `https://engine.seoscoreapi.com`) |

## Outputs

| Output | Description |
|--------|-------------|
| `score` | SEO score (0-100) |
| `grade` | Letter grade (A+ to F) |
| `issues` | Number of issues found |
| `report-url` | Link to full report |
| `deep-audit-score` | Deep Site Audit score (`lai_score`) |
| `deep-audit-grade` | Deep Site Audit grade (`lai_grade`) |
| `deep-audit-high-findings` | Number of high/critical findings |
| `deep-audit-job-id` | Job ID, for `GET https://seoscoreapi.com/site-audit/{job_id}` |

## Deep Site Audit

Set `deep-audit: true` to also run a Deep Site Audit: thousands of catalog checks across
9 dimensions plus an AI analysis pass. It starts `POST /site-audit` on
`https://seoscoreapi.com`, polls `GET /site-audit/{job_id}` until it completes (about 90
seconds once it starts; retries on queue backpressure), then adds the score and the top
findings to the job summary. Included on Pro (20/month) and Ultra (100/month); other keys
spend a purchased Deep Audit credit. Check what's left with
`curl -H "X-API-Key: $KEY" https://seoscoreapi.com/deep-audit/usage`.

```yaml
- name: SEO + Deep Site Audit
  id: seo
  uses: SeoScoreAPI/seo-audit-action@v1
  with:
    url: "https://your-site.com"
    api-key: ${{ secrets.SEO_SCORE_API_KEY }}
    threshold: 85
    deep-audit: true
    deep-audit-business-type: saas
    deep-audit-fail-on-high: true

- run: echo "Deep audit ${{ steps.seo.outputs.deep-audit-score }} (${{ steps.seo.outputs.deep-audit-high-findings }} high findings)"
```

Deep audits cost quota, so run them on pushes to `main` or on a schedule rather than on
every pull request.

## Example: Full Workflow with PR Comments

```yaml
name: SEO Check
on:
  push:
    branches: [main]
  pull_request:

jobs:
  seo:
    runs-on: ubuntu-latest
    steps:
      - name: SEO Audit
        id: seo
        uses: SeoScoreAPI/seo-audit-action@v1
        with:
          url: "https://your-site.com"
          api-key: ${{ secrets.SEO_SCORE_API_KEY }}
          threshold: 85

      - name: Comment on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `## SEO Audit\n\nScore: **${{ steps.seo.outputs.score }}/100** (${{ steps.seo.outputs.grade }})\n\n[Full Report](${{ steps.seo.outputs.report-url }})`
            })
```

## What Gets Checked

The standard audit covers, among others:

- **Meta & Content** — title, description, headings, readability, alt text
- **Technical** — HTTPS, SSL, canonical, structured data, sitemap
- **Social** — Open Graph, Twitter Cards, favicon
- **Performance** — page size, DOM complexity, compression
- **Accessibility** — lang attribute, ARIA landmarks

## Getting an API Key

1. Visit [seoscoreapi.com](https://seoscoreapi.com)
2. Sign up for a free key (5 audits/day) or a paid plan
3. Add as `SEO_SCORE_API_KEY` in your repo secrets

## Pricing

| Plan | Price | Audits |
|------|-------|--------|
| Free | $0 | 5/day |
| Starter | $5/mo | 200/mo |
| Basic | $15/mo | 1,000/mo |
| Pro | $39/mo | 5,000/mo |
| Ultra | $99/mo | 25,000/mo |

## Links

- [Website](https://seoscoreapi.com)
- [API Docs](https://seoscoreapi.com/docs)
- [Changelog](CHANGELOG.md)
- [Blog: GitHub Actions SEO Guide](https://seoscoreapi.com/blog/github-actions-seo-audit)

## License

MIT
