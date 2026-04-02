# SEO Audit Action

Run automated SEO audits on your website as part of your CI/CD pipeline. Catch SEO regressions before they ship to production.

Powered by [SEO Score API](https://seoscoreapi.com) — 28 checks across meta, technical, social, performance, and accessibility.

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

## Outputs

| Output | Description |
|--------|-------------|
| `score` | SEO score (0-100) |
| `grade` | Letter grade (A+ to F) |
| `issues` | Number of issues found |
| `report-url` | Link to full report |

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

28 checks across 5 categories:

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
- [Blog: GitHub Actions SEO Guide](https://seoscoreapi.com/blog/github-actions-seo-audit)

## License

MIT
