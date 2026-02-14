# rec00n

**TR:** 

Pasif recon otomasyonu: subdomain keşfi (subfinder + crt.sh), canlı doğrulama (httpx-toolkit/httpx), Wayback/CDX URL toplama, riskli parametre skorlama ve tıklanabilir HTML rapor. **Exploit yok, brute-force yok.**

**TR:** 

Subdomain keşfi (Subfinder)
Hedef domain için subfinder çalıştırılır ve bulunan tüm subdomainler subdomains.txt dosyasına yazılır.

crt.sh ile zenginleştirme + dedupe
Aynı hedef için crt.sh üzerinden curl ile sertifika kayıtlarından subdomainler çekilir. Yeni bulunanlar mevcut subdomains.txt dosyasına eklenir ve tüm liste duplicate’lerden arındırılır (tekilleştirilir).

Canlılık doğrulama (httpx-toolkit)
Elde edilen (örnek) 3000 subdomain, httpx-toolkit ile probe edilir. HTTP 200/302 gibi “up” cevap veren canlı originler alive_origins.txt dosyasına yazılır.

Wayback/CDX ile historical URL toplama
Canlı bulunan originler için Wayback Machine / CDX kaynaklarından geçmiş URL’ler toplanır ve wayback_urls_all.txt dosyasında birleştirilir (dedupe edilir).

Historical URL’leri tekrar doğrulama (httpx-toolkit)
Toplanan historical URL’ler yeniden httpx-toolkit ile test edilir. Gerçekten erişilebilen URL’ler alive_wayback_urls.txt dosyasına yazılır.

Risk parametre analizi (A+B+C)
Son URL seti üzerinde parametre analizi yapılır:

Katman A (isim bazlı): Redirect, secrets, file/path, debug, IDOR, SSRF-sinyal gibi kategorilerde parametre adları işaretlenir.

Katman B (değer bazlı): Değerin URL-like olması, internal IP içermesi, traversal pattern, JWT/base64 benzeri, yüksek entropi, hassas uzantı gibi sinyallerle puanlama yapılır.

Katman C (anomali): Nadir ama şüpheli prefix/pattern taşıyan parametreler (x_, dbg_, internal_, admin_, redirect_) ayrıca “anomali” olarak işaretlenir; çok sık görülen tracking parametreler ayrı raporlanır.

HTML rapor üretimi (triage)
Tüm bulgular (top URL’ler, skorlar, parametre detayları, frekans istatistikleri) tıklanabilir bir HTML rapora dökülür. Böylece manuel test için en “öncelikli” URL’ler hızlıca seçilebilir.

**EN:** 

Passive recon automation: subdomain discovery (subfinder + crt.sh), live verification (httpx-toolkit/httpx), Wayback/CDX URL collection, risk-parameter scoring, and a clickable HTML report. **No exploitation, no brute-force.**

**EN** 

Subdomain discovery (Subfinder)
Run subfinder for the target domain and write all discovered subdomains into subdomains.txt.

crt.sh enrichment + deduplication
Query crt.sh via curl to collect additional certificate-based subdomains. Append new entries to subdomains.txt and dedupe the final list.

Live verification (httpx-toolkit)
Probe the full subdomain set (e.g., 3000) with httpx-toolkit. Write reachable “up” origins (e.g., HTTP 200/3xx) into alive_origins.txt.

Wayback/CDX historical URL collection
For each live origin, collect historical URLs from Wayback Machine / CDX sources and merge them into wayback_urls_all.txt (deduped).

Re-verify historical URLs (httpx-toolkit)
Probe the collected historical URLs again with httpx-toolkit. Save reachable URLs into alive_wayback_urls.txt.

Risk parameter analysis (A+B+C)
Analyze the final URL set using a layered scoring model:

Layer A (name-based): categorize risky parameter names (redirect, secrets/auth, file/path, debug, IDOR-ish, SSRF-ish signals).

Layer B (value-based): score risky values (URL-like values, internal IPs, traversal patterns, JWT/base64-like tokens, high entropy, sensitive extensions).

Layer C (anomaly-based): flag rare but suspicious parameters (e.g., x_, dbg_, internal_, admin_, redirect_) and separately report very common tracking params.

HTML report (triage output)
Export findings into a clickable HTML report (top scored URLs, detailed param signals, and frequency stats) to speed up manual review and testing.

## Requirements
- `subfinder`, `curl`, `httpx-toolkit` (or `httpx`)
- Optional: `jq`, `gau`/`waybackurls`, `timeout`

## Usage
./rec00n.sh example.com


<img width="754" height="731" alt="image" src="https://github.com/user-attachments/assets/18da35c1-335a-4d8f-9092-caadc1e2a518" />
