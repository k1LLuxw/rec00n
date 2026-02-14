# rec00n

**TR:** Pasif recon otomasyonu: subdomain keşfi (subfinder + crt.sh), canlı doğrulama (httpx-toolkit/httpx), Wayback/CDX URL toplama, riskli parametre skorlama ve tıklanabilir HTML rapor. **Exploit yok, brute-force yok.**

**EN:** Passive recon automation: subdomain discovery (subfinder + crt.sh), live verification (httpx-toolkit/httpx), Wayback/CDX URL collection, risk-parameter scoring, and a clickable HTML report. **No exploitation, no brute-force.**

## Requirements
- `subfinder`, `curl`, `httpx-toolkit` (or `httpx`)
- Optional: `jq`, `gau`/`waybackurls`, `timeout`

## Usage
./rec00n.sh example.com

