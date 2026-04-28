# Stock Research Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a nanobot Skill that automates A-share market research via a 4-agent pipeline: macro scan → sector screen → parallel stock deep-dives → report.

**Architecture:** Multi-agent pipeline coordinated by a main `stock-research` Skill. Four specialist sub-agents handle discrete pipeline stages. All agents are Markdown instruction documents, not code. Data comes from AKShare (free), Tushare Pro (optional paid), and DuckDuckGo web search.

**Tech Stack:** nanobot Skill/Agent Markdown docs, AKShare Python library, Tushare Pro API, nanobot built-in `web_search` tool (DuckDuckGo), nanobot `subagent` tool for parallel execution.

---

## Task 1: Create Directory Structure

**Files:**
- Create: `~/.claude/skills/stock-research/` (directory)
- Create: `~/.claude/agents/` (directory)
- Create: `~/docs/research/` (report output directory, inside nanobot workspace)

**Step 1: Create directories**

```bash
mkdir -p ~/.claude/skills/stock-research
mkdir -p ~/.claude/agents
mkdir -p ~/.nanobot/workspace/research
```

**Step 2: Verify**

```bash
ls ~/.claude/skills/ | grep stock-research
ls ~/.claude/agents/
ls ~/.nanobot/workspace/research
```

Expected: All three directories exist with no errors.

**Step 3: Commit**

```bash
# No files to commit yet — directories are empty. Skip.
```

---

## Task 2: Write macro-scanner Agent

**Context:** This agent is invoked first in the pipeline. It fetches real A-share market data using AKShare Python calls via nanobot's shell tool, scores market sentiment, and decides whether to continue the pipeline or abort with a risk warning.

**AKShare calls to use:**
- `ak.stock_zh_index_spot()` — index prices (filter: 上证指数, 深证成指, 创业板指)
- `ak.stock_hsgt_north_net_flow_in_hist_em()` — northbound capital flow (today's net)
- `ak.stock_market_activity_legu()` — market breadth (gainers/losers/limit-up/limit-down)
- `ak.stock_margin_sse()` — margin balance (latest date)

**Sentiment score rules (output as integer 1–10):**
- 8–10: Bullish (northbound inflow > 30亿, limit-up > 80, gainers > 60%)
- 5–7: Neutral
- 1–4: Bearish (northbound outflow > 30亿, limit-down > 60, gainers < 40%)
- Score ≤ 3 triggers pipeline abort

**Files:**
- Create: `~/.claude/agents/macro-scanner.md`

**Step 1: Write the agent**

Write `~/.claude/agents/macro-scanner.md` with this exact content:

```markdown
---
name: macro-scanner
description: A-share macro market scanner. Fetches index data, northbound capital flow, market breadth, and margin balance via AKShare. Outputs a sentiment score (1-10) and brief verdict. Score ≤ 3 triggers pipeline abort.
---

# Macro Market Scanner

You are a specialized A-share market macro analyst. Your job is to fetch real market data and produce a structured sentiment assessment.

## What You Must Do

1. Run each AKShare call below using the `shell` tool with `uv run python -c "..."` or `python3 -c "..."`.
2. Parse the output and fill in the structured JSON result.
3. Compute a sentiment score from 1 (extreme fear) to 10 (extreme greed).
4. If score ≤ 3, set `abort: true` and write a risk warning.

## Data Fetching Commands

### Index Prices
```python
import akshare as ak, json
df = ak.stock_zh_index_spot()
indices = df[df['代码'].isin(['000001', '399001', '399006'])][['名称','最新价','涨跌幅']].to_dict('records')
print(json.dumps(indices, ensure_ascii=False))
```

### Northbound Capital Flow (today's net, unit: 亿元)
```python
import akshare as ak, json
df = ak.stock_hsgt_north_net_flow_in_hist_em(symbol="北向资金")
today = df.iloc[-1]
print(json.dumps({"date": str(today['日期']), "net_flow": float(today['当日净流入'])}, ensure_ascii=False))
```

### Market Breadth
```python
import akshare as ak, json
df = ak.stock_market_activity_legu()
row = df.iloc[0].to_dict()
print(json.dumps({k: str(v) for k, v in row.items()}, ensure_ascii=False))
```

### Margin Balance (latest)
```python
import akshare as ak, json
df = ak.stock_margin_sse()
latest = df.iloc[-1]
print(json.dumps({"date": str(latest['日期']), "balance": float(latest['融资余额'])}, ensure_ascii=False))
```

## Sentiment Scoring Rules

| Score | Condition |
|-------|-----------|
| 9–10 | Northbound net inflow > 50亿 AND limit-up > 100 AND gainers > 65% |
| 7–8  | Northbound net inflow > 20亿 AND limit-up > 60 AND gainers > 55% |
| 5–6  | Neutral conditions |
| 3–4  | Northbound net outflow > 10亿 OR gainers < 45% |
| 1–2  | Northbound net outflow > 30亿 AND limit-down > 60 AND gainers < 40% |

## Output Format

Return **only** this JSON structure (no prose):

```json
{
  "date": "YYYY-MM-DD",
  "score": 7,
  "verdict": "偏多",
  "abort": false,
  "indices": [
    {"name": "上证指数", "price": 3312.5, "change_pct": 0.82},
    {"name": "深证成指", "price": 10234.1, "change_pct": 1.15},
    {"name": "创业板指", "price": 2108.3, "change_pct": 1.43}
  ],
  "northbound_flow_yi": 52.3,
  "limit_up_count": 87,
  "limit_down_count": 12,
  "gainers_pct": 61.2,
  "margin_balance_yi": 15234.5,
  "risk_warning": null
}
```

If `abort: true`, set `risk_warning` to a 1-sentence Chinese explanation, e.g.:
`"市场极度恐慌，涨跌比仅38%，北向资金大幅流出，建议观望。"`

## Error Handling

If any AKShare call fails (network error, data not available):
- Use the last known value from a previous call if available
- If no fallback, mark that field as `null` and note it in `risk_warning`
- Never abort the pipeline due to a single data fetch failure unless ALL calls fail
```

**Step 2: Verify file was written**

```bash
head -5 ~/.claude/agents/macro-scanner.md
```

Expected: Shows `---` frontmatter header.

**Step 3: Commit**

```bash
git -C ~/.claude add agents/macro-scanner.md
git -C ~/.claude commit -m "feat: add macro-scanner agent for A-share market sentiment"
```

---

## Task 3: Write sector-screener Agent

**Context:** Receives macro-scanner JSON output. Identifies the top 3 hot sectors by capital flow and sector momentum. Selects 1–2 candidate stocks per sector (max 5 total) to pass to stock-researcher agents.

**AKShare calls to use:**
- `ak.stock_sector_spot(symbol="行业板块")` — sector performance ranking
- `ak.stock_fund_flow_industry(symbol="行业")` — sector capital flow (net inflow)
- `ak.stock_hot_concept_spot(symbol="概念板块")` — trending concept themes

**Files:**
- Create: `~/.claude/agents/sector-screener.md`

**Step 1: Write the agent**

Write `~/.claude/agents/sector-screener.md`:

```markdown
---
name: sector-screener
description: A-share sector screener. Takes macro-scanner JSON as input. Identifies top 3 hot sectors by capital flow + momentum, then selects 1-2 candidate stocks per sector (max 5 total) for deep research.
---

# Sector Screener

You are a specialized A-share sector analyst. You receive macro market data and identify the best sectors and candidate stocks for today's research.

## Input

You receive the macro-scanner JSON output as your starting context.

## What You Must Do

1. Fetch sector data via AKShare shell commands below.
2. Score each sector by combining: capital inflow rank + price gain rank.
3. Pick the top 3 sectors.
4. For each top sector, fetch its constituent stocks and pick the top 1–2 by capital inflow (龙头股).
5. Return at most 5 candidate stocks total.

## Data Fetching Commands

### Sector Performance Ranking
```python
import akshare as ak, json
df = ak.stock_sector_spot(symbol="行业板块")
top = df.nlargest(10, '涨跌幅')[['板块名称','涨跌幅','主力净流入']].to_dict('records')
print(json.dumps(top, ensure_ascii=False))
```

### Sector Capital Flow
```python
import akshare as ak, json
df = ak.stock_fund_flow_industry(symbol="行业")
top = df.nlargest(10, '今日主力净流入')[['行业','今日主力净流入','今日涨跌幅']].to_dict('records')
print(json.dumps(top, ensure_ascii=False))
```

### Trending Concepts
```python
import akshare as ak, json
df = ak.stock_hot_concept_spot(symbol="概念板块")
top = df.nlargest(5, '涨跌幅')[['板块名称','涨跌幅']].to_dict('records')
print(json.dumps(top, ensure_ascii=False))
```

### Top Stocks in a Sector (replace SECTOR_NAME)
```python
import akshare as ak, json
df = ak.stock_sector_detail_em(sector="SECTOR_NAME")
top = df.nlargest(3, '主力净流入')[['名称','代码','涨跌幅','主力净流入']].to_dict('records')
print(json.dumps(top, ensure_ascii=False))
```

## Sector Scoring

Combine two rankings (lower rank = better):
- `capital_rank`: rank by capital inflow (1 = highest inflow)
- `gain_rank`: rank by % gain (1 = highest gain)
- `combined_score = capital_rank + gain_rank` (lower = better)

Pick the 3 sectors with the lowest combined_score.

## Stock Selection Rules

From each top-3 sector, pick the top 1–2 stocks by `主力净流入`. Apply filters:
- Exclude ST stocks (name contains "ST")
- Exclude stocks with price < 3元 (penny stocks)
- Prefer market cap > 50亿

Cap total candidates at 5 stocks.

## Output Format

Return **only** this JSON (no prose):

```json
{
  "date": "YYYY-MM-DD",
  "top_sectors": [
    {"name": "半导体", "gain_pct": 2.3, "net_inflow_yi": 45.2},
    {"name": "新能源车", "gain_pct": 1.8, "net_inflow_yi": 38.1},
    {"name": "创新药", "gain_pct": 1.5, "net_inflow_yi": 22.6}
  ],
  "hot_concepts": ["AI算力", "固态电池", "减重药"],
  "candidate_stocks": [
    {"name": "中芯国际", "code": "688981", "sector": "半导体", "gain_pct": 3.1, "net_inflow_yi": 12.3},
    {"name": "比亚迪", "code": "002594", "sector": "新能源车", "gain_pct": 2.0, "net_inflow_yi": 9.8},
    {"name": "恒瑞医药", "code": "600276", "sector": "创新药", "gain_pct": 1.9, "net_inflow_yi": 6.5}
  ]
}
```

## Error Handling

If a sector detail call fails, skip that sector's stock selection and note it. Never return fewer than 1 candidate stock (use index-level fallback if needed).
```

**Step 2: Verify**

```bash
head -5 ~/.claude/agents/sector-screener.md
```

**Step 3: Commit**

```bash
git -C ~/.claude add agents/sector-screener.md
git -C ~/.claude commit -m "feat: add sector-screener agent for A-share sector analysis"
```

---

## Task 4: Write stock-researcher Agent

**Context:** Receives a single stock (name + code) and produces a comprehensive deep-dive. This agent runs in parallel for each candidate stock. Uses Tushare Pro for financials (with AKShare fallback) and DuckDuckGo for news.

**Data strategy:**
- Try Tushare Pro first (`TUSHARE_TOKEN` env var)
- If token not set or call fails → use AKShare equivalents
- Always fetch K-line from AKShare (free, reliable)
- Always search news via `web_search` tool

**Files:**
- Create: `~/.claude/agents/stock-researcher.md`

**Step 1: Write the agent**

Write `~/.claude/agents/stock-researcher.md`:

```markdown
---
name: stock-researcher
description: A-share individual stock deep researcher. Given a stock name and code, fetches fundamentals (Tushare Pro with AKShare fallback), technicals (AKShare K-line), and news (web search). Returns structured JSON for report-writer.
---

# Stock Researcher

You are a specialized A-share individual stock analyst. You receive one stock to research and produce a comprehensive assessment.

## Input

You receive: `{"name": "股票名称", "code": "XXXXXX", "sector": "板块名"}` as your task.

## Research Steps (Run in Order)

### Step 1: Fundamental Data

**Try Tushare Pro first:**
```python
import os, tushare as ts, json
token = os.environ.get('TUSHARE_TOKEN', '')
if not token:
    print(json.dumps({"source": "no_token"}))
else:
    ts.set_token(token)
    pro = ts.pro_api()
    # Financial indicators
    df = pro.fina_indicator(ts_code='XXXXXX.SH', period='20241231', fields='pe,pb,roe,grossprofit_margin,netprofit_yoy,revenue_yoy')
    # Income statement
    income = pro.income(ts_code='XXXXXX.SH', period='20241231', fields='total_revenue,n_income')
    # Top holders
    holders = pro.top10_floatholders(ts_code='XXXXXX.SH', period='20241231')
    print(json.dumps({
        "source": "tushare",
        "pe": float(df.iloc[0]['pe']) if len(df) else None,
        "pb": float(df.iloc[0]['pb']) if len(df) else None,
        "roe": float(df.iloc[0]['roe']) if len(df) else None,
        "gross_margin": float(df.iloc[0]['grossprofit_margin']) if len(df) else None,
        "revenue_yoy": float(df.iloc[0]['revenue_yoy']) if len(df) else None,
        "net_profit_yoy": float(df.iloc[0]['netprofit_yoy']) if len(df) else None,
        "top_holders": holders[['holder_name','hold_ratio']].head(3).to_dict('records') if len(holders) else []
    }, ensure_ascii=False))
```

**If Tushare fails, use AKShare fallback:**
```python
import akshare as ak, json
# Replace XXXXXX with stock code, exchange suffix with SH or SZ
df = ak.stock_financial_abstract_ths(symbol='XXXXXX', indicator='按年度')
print(json.dumps(df.head(2).to_dict('records'), ensure_ascii=False))
```

Replace `XXXXXX` with the actual stock code. Use `.SH` suffix for Shanghai (6xxxxx), `.SZ` for Shenzhen (0xxxxx or 3xxxxx).

### Step 2: Technical Data (K-line, last 60 trading days)
```python
import akshare as ak, json
df = ak.stock_zh_a_hist(symbol='XXXXXX', period='daily', start_date='20250101', adjust='qfq')
recent = df.tail(20)[['日期','开盘','收盘','最高','最低','成交量','涨跌幅']].to_dict('records')
# Compute simple signals
closes = df['收盘'].values
ma5 = closes[-5:].mean()
ma20 = closes[-20:].mean()
ma60 = closes[-60:].mean() if len(closes) >= 60 else None
current = closes[-1]
print(json.dumps({
    "current_price": float(current),
    "ma5": float(ma5),
    "ma20": float(ma20),
    "ma60": float(ma60) if ma60 else None,
    "above_ma20": bool(current > ma20),
    "above_ma60": bool(current > ma60) if ma60 else None,
    "recent_bars": recent[-5:]  # last 5 days for the report
}, ensure_ascii=False))
```

### Step 3: News and Announcements (use web_search tool)

Search for: `"股票名称 股票代码 最新公告 研报 2026"`
Search for: `"股票名称 风险 负面 2026"`

Extract the 3 most relevant recent items per search.

## Technical Signal Interpretation

| Signal | Rule |
|--------|------|
| 多头排列 | current > MA5 > MA20 > MA60 |
| 短期偏强 | current > MA20 |
| 短期偏弱 | current < MA20 |
| 空头排列 | current < MA5 < MA20 < MA60 |

## Valuation Quick Guide

| Metric | Attractive | Neutral | Expensive |
|--------|-----------|---------|-----------|
| PE | < 20x | 20–40x | > 40x |
| PB | < 1.5x | 1.5–3x | > 3x |
| ROE | > 15% | 10–15% | < 10% |

## Output Format

Return **only** this JSON (no prose):

```json
{
  "name": "中芯国际",
  "code": "688981",
  "sector": "半导体",
  "data_source": "tushare",
  "fundamentals": {
    "pe": 28.5,
    "pb": 2.1,
    "roe": 12.3,
    "gross_margin": 18.5,
    "revenue_yoy": 18.2,
    "net_profit_yoy": 22.5,
    "valuation_verdict": "合理",
    "top_holders": [
      {"name": "大唐电信", "ratio": 17.8}
    ]
  },
  "technicals": {
    "current_price": 68.5,
    "ma5": 66.2,
    "ma20": 63.1,
    "ma60": 58.9,
    "signal": "多头排列",
    "above_ma20": true,
    "above_ma60": true
  },
  "news_summary": "近期公司发布Q1财报超预期，营收同比+22%。机构评级：中金、中信给予买入评级。无重大负面消息。",
  "core_thesis": "国产替代加速，产能利用率回升，估值处于历史中位，技术面偏强。",
  "risk_factors": ["地缘政治风险影响设备采购", "行业竞争加剧"],
  "rating": "关注"
}
```

`rating` must be one of: `"重点关注"` / `"关注"` / `"观察"` / `"回避"`

Rating rules:
- 重点关注: fundamentals strong (ROE>12%, revenue_yoy>15%) AND technical bullish AND no major risks
- 关注: 2 of 3 dimensions positive
- 观察: mixed signals
- 回避: fundamentals weak OR major risk flags in news
```

**Step 2: Verify**

```bash
head -5 ~/.claude/agents/stock-researcher.md
```

**Step 3: Commit**

```bash
git -C ~/.claude add agents/stock-researcher.md
git -C ~/.claude commit -m "feat: add stock-researcher agent for individual stock deep-dives"
```

---

## Task 5: Write report-writer Agent

**Context:** Receives macro JSON + sector JSON + list of stock-researcher JSONs. Writes the chat summary (<500 chars) and the full Markdown report file.

**Files:**
- Create: `~/.claude/agents/report-writer.md`

**Step 1: Write the agent**

Write `~/.claude/agents/report-writer.md`:

```markdown
---
name: report-writer
description: A-share research report compiler. Takes structured JSON from macro-scanner, sector-screener, and stock-researcher agents. Outputs a short chat summary (<500 chars) and saves a full Markdown report to the workspace.
---

# Report Writer

You are a financial report compiler for A-share market research. You receive structured JSON data from the pipeline and produce two outputs.

## Input

You receive a combined JSON object:
```json
{
  "macro": { ... },       // from macro-scanner
  "sectors": { ... },     // from sector-screener
  "stocks": [ ... ]       // array of stock-researcher outputs
}
```

## Output 1: Chat Summary (print to stdout)

Print a concise summary in exactly this format. Keep total length under 500 Chinese characters:

```
市场日报 · {date}

【宏观】{index_summary}，北向{flow_direction}{flow_amount}亿，市场情绪：{verdict}（{score}/10）
【热点板块】{sector1} / {sector2} / {sector3}

【今日关注】
{for each stock rated 重点关注 or 关注:}
{n}. {name}({code}) — {core_thesis_one_line}

⚠️ 以上仅为AI调研结果，不构成投资建议
```

Rules:
- `index_summary`: "上证 {change}%" format (pick the 上证指数 from macro data)
- `flow_direction`: "净流入" if positive, "净流出" if negative
- Only list stocks rated "重点关注" or "关注" (skip 观察/回避)
- `core_thesis_one_line`: truncate to 20 Chinese characters max

## Output 2: Full Markdown Report (save to file)

Save the report to: `~/.nanobot/workspace/research/{date}-market-research.md`

Use this exact structure:

```markdown
# A股市场调研报告 · {date}

> 本报告由 AI 自动生成，仅供参考，不构成投资建议

---

## 一、宏观市场概况

| 指标 | 数值 | 变化 |
|------|------|------|
| 上证指数 | {price} | {change_pct}% |
| 深证成指 | {price} | {change_pct}% |
| 创业板指 | {price} | {change_pct}% |
| 北向资金 | {flow}亿 | — |
| 涨停数量 | {limit_up} | — |
| 跌停数量 | {limit_down} | — |
| 涨跌比 | {gainers_pct}% | — |
| 融资余额 | {balance}亿 | — |

**市场情绪：{verdict}（{score}/10）**

{risk_warning if abort was triggered}

---

## 二、热点板块

| 板块 | 涨跌幅 | 主力净流入 |
|------|--------|-----------|
{for each top sector: | name | gain% | inflow亿 |}

**概念热点：** {hot_concepts joined by " / "}

---

## 三、个股调研

{for each stock in research results:}

### {name}（{code}）· {sector} · {rating}

**核心逻辑：** {core_thesis}

#### 基本面

| 指标 | 数值 | 判断 |
|------|------|------|
| PE | {pe}x | {valuation_verdict} |
| PB | {pb}x | — |
| ROE | {roe}% | — |
| 毛利率 | {gross_margin}% | — |
| 营收同比 | {revenue_yoy}% | — |
| 净利润同比 | {net_profit_yoy}% | — |

前三大流通股东：{top_holders as "名称(比例%)" joined by ", "}

#### 技术面

当前价：{current_price} | MA5：{ma5} | MA20：{ma20} | MA60：{ma60}

信号：**{signal}**（{above_ma20_text}，{above_ma60_text}）

#### 近期动态

{news_summary}

#### 风险提示

{risk_factors as bullet list}

---
{end for each stock}

## 四、综合建议

{Generate a 3-5 sentence synthesis based on macro sentiment + sector momentum + individual stock ratings. Be balanced and note risks.}

---

*报告生成时间：{datetime}*
*数据来源：AKShare / Tushare Pro / DuckDuckGo*
*免责声明：本报告由 AI 自动生成，所有内容仅供参考，不构成任何投资建议。投资有风险，入市须谨慎。*
```

## How to Save the File

Use the shell tool to write the report:

```bash
cat > ~/.nanobot/workspace/research/{date}-market-research.md << 'REPORT_EOF'
{full report content}
REPORT_EOF
```

After saving, print the file path so the orchestrating skill can confirm it.

## Error Handling

- If a stock's data is partially missing (e.g., PE is null), render the table cell as "N/A"
- If all stocks were rated 回避, the chat summary should say "今日市场无明显机会，建议观望"
- Never skip the chat summary output — it is the primary user-facing output
```

**Step 2: Verify**

```bash
head -5 ~/.claude/agents/report-writer.md
```

**Step 3: Commit**

```bash
git -C ~/.claude add agents/report-writer.md
git -C ~/.claude commit -m "feat: add report-writer agent for compiling market research reports"
```

---

## Task 6: Write Main stock-research Skill (Orchestrator)

**Context:** This is the entry point. It coordinates the 4 sub-agents in sequence, handling the pipeline logic: macro → sectors → parallel stock research → report. It also handles the `--stocks` and `--sector` argument shortcuts.

**Files:**
- Create: `~/.claude/skills/stock-research/SKILL.md`

**Step 1: Write the skill**

Write `~/.claude/skills/stock-research/SKILL.md`:

```markdown
---
name: stock-research
description: A-share automated market research pipeline. Runs macro scan → sector screen → parallel individual stock deep-dives → report. Invoked as /stock-research. Supports --stocks and --sector flags to skip screening and target specific stocks or sectors.
---

# Stock Research Pipeline

You are orchestrating an automated A-share market research workflow. Follow this pipeline exactly.

## Argument Parsing

Parse the invocation arguments before starting:

| Argument | Effect |
|----------|--------|
| (none) | Run full pipeline |
| `--stocks 688981,002594` | Skip macro+sector; research these specific stocks directly |
| `--sector 半导体` | Skip macro; screen only this sector |

Store parsed arguments before proceeding.

## Pipeline Execution

### Phase 1: Macro Scan

Invoke the `macro-scanner` subagent. Pass it today's date.

Wait for the JSON result. Check `abort` field:
- If `abort: true` → output the `risk_warning` to the user and **STOP**. Do not continue.
- If `abort: false` → continue to Phase 2.

**Skip Phase 1** if `--stocks` argument was provided (jump directly to Phase 3).

### Phase 2: Sector Screening

Invoke the `sector-screener` subagent. Pass it the macro-scanner JSON result.

Wait for the JSON result containing `candidate_stocks`.

**Skip Phase 2** if `--stocks` argument was provided.
**Override sector** if `--sector` argument was provided (tell sector-screener to focus only on that sector).

### Phase 3: Parallel Stock Research

For each stock in `candidate_stocks` (or the `--stocks` list), invoke a `stock-researcher` subagent in **parallel**.

Limit: maximum 5 parallel subagents. If more than 5 candidates, take the top 5 by `net_inflow_yi`.

Collect all stock-researcher JSON results. Wait for ALL to complete before proceeding.

### Phase 4: Report Generation

Invoke the `report-writer` subagent. Pass it:
```json
{
  "macro": {macro-scanner result or null},
  "sectors": {sector-screener result or null},
  "stocks": [array of all stock-researcher results]
}
```

Wait for report-writer to complete. It will:
1. Print the chat summary → you relay this to the user
2. Save the full report file → confirm the file path to the user

## User-Facing Messages

### On start (print immediately):
```
正在启动市场调研流水线... 预计耗时 2-3 分钟
```

### After Phase 1 (macro data ready):
```
宏观扫描完成，市场情绪：{verdict}（{score}/10）
```

### After Phase 2 (sector data ready):
```
板块筛选完成，今日热点：{sector1} / {sector2} / {sector3}
开始并行调研 {n} 只候选股票...
```

### Final output: relay the report-writer chat summary verbatim, then add:
```
完整报告已保存至：{file_path}
```

## Error Recovery

- If any single stock-researcher fails: skip it, continue with remaining stocks
- If sector-screener fails: ask user if they want to provide a stock list manually
- If macro-scanner fails: warn user that macro data is unavailable, ask if they want to continue without it

## Dependencies

- AKShare must be installed: `uv pip install akshare` or `pip install akshare`
- Tushare (optional): `uv pip install tushare` — only needed for financial indicators
- Set `TUSHARE_TOKEN` env var for Tushare Pro access

## Cron Configuration Example

To run automatically every weekday at 8:30 AM, add to nanobot config:

```yaml
scheduler:
  jobs:
    - cron: "30 8 * * 1-5"
      skill: stock-research
      channel: feishu
```
```

**Step 2: Verify**

```bash
head -5 ~/.claude/skills/stock-research/SKILL.md
cat ~/.claude/skills/stock-research/SKILL.md | wc -l
```

Expected: frontmatter header, ~100+ lines.

**Step 3: Commit**

```bash
git -C ~/.claude add skills/stock-research/SKILL.md
git -C ~/.claude commit -m "feat: add stock-research orchestrator skill"
```

---

## Task 7: Install Python Dependencies

**Context:** AKShare must be available in the Python environment where nanobot runs its shell tool. Tushare is optional.

**Files:** None created. Shell commands only.

**Step 1: Check if AKShare is already installed**

```bash
python3 -c "import akshare; print(akshare.__version__)"
```

If it prints a version, skip Step 2.

**Step 2: Install AKShare**

```bash
uv pip install akshare
# or if uv is not available:
pip3 install akshare
```

Expected output: `Successfully installed akshare-...`

**Step 3: (Optional) Install Tushare**

Only if you have a Tushare Pro token:

```bash
uv pip install tushare
export TUSHARE_TOKEN=your_token_here
```

Add the export to `~/.zshrc` or `~/.bashrc` to persist it:

```bash
echo 'export TUSHARE_TOKEN=your_token_here' >> ~/.zshrc
```

**Step 4: Smoke-test AKShare**

```bash
python3 -c "
import akshare as ak
df = ak.stock_zh_index_spot()
row = df[df['代码'] == '000001'].iloc[0]
print(f'上证指数: {row[\"最新价\"]} ({row[\"涨跌幅\"]}%)')
"
```

Expected: prints current Shanghai Composite price (only works on trading days during market hours, or uses last close).

**Step 5: No commit needed** (no files changed)

---

## Task 8: End-to-End Validation

**Context:** Verify the full pipeline works by running it manually and checking the output. Since agents are Markdown docs and not Python code, validation means invoking the skill in a nanobot session and checking behavior.

**Step 1: Start nanobot in interactive mode**

```bash
nanobot run
```

Or connect to an existing nanobot session via your configured channel (Feishu, Telegram, etc.).

**Step 2: Run a limited test (single stock, skip pipeline)**

Send this message to the agent:
```
/stock-research --stocks 600519
```

(600519 = 贵州茅台, reliable data, easy to verify)

Expected behavior:
1. Agent prints "正在启动市场调研流水线..."
2. Skips macro + sector phases (--stocks flag)
3. Invokes stock-researcher for 600519
4. Invokes report-writer
5. Prints chat summary with 贵州茅台 data
6. Confirms report saved to `~/.nanobot/workspace/research/YYYY-MM-DD-market-research.md`

**Step 3: Verify the saved report**

```bash
cat ~/.nanobot/workspace/research/$(date +%Y-%m-%d)-market-research.md
```

Expected: Full Markdown report with fundamental data, technical signals, and news summary for 贵州茅台.

**Step 4: Run full pipeline test**

Send this message:
```
/stock-research
```

Expected: Full pipeline runs (macro → sectors → up to 5 stocks → report). Watch for all 4 progress messages. Total time should be under 5 minutes.

**Step 5: Verify abort logic**

This is a documentation test — no live API needed. Ask the agent:
```
请模拟市场情绪评分为2的场景，运行stock-research
```

Expected: Agent reports risk warning and stops without proceeding to sector screening.

---

## Task 9: Update Project Docs

**Files:**
- Modify: `docs/README.md` (if it exists) or create `docs/stock-research.md`

**Step 1: Check if docs/README.md references skills**

```bash
grep -l "skill" /Users/jodejoester/mono/nanobot/docs/*.md
```

**Step 2: Add a note to nanobot docs**

Add a brief entry to `docs/configuration.md` or `docs/chat-commands.md` referencing the new skill:

The addition should document `/stock-research` as an available community skill with its flags and cron example.

**Step 3: Commit**

```bash
git add docs/
git commit -m "docs: document stock-research skill usage and cron config"
```

---

## Summary

| Task | Output | Est. Time |
|------|--------|-----------|
| 1 | Directory structure | 2 min |
| 2 | macro-scanner.md | 5 min |
| 3 | sector-screener.md | 5 min |
| 4 | stock-researcher.md | 8 min |
| 5 | report-writer.md | 8 min |
| 6 | stock-research/SKILL.md | 8 min |
| 7 | AKShare installed | 3 min |
| 8 | E2E validation | 15 min |
| 9 | Docs update | 3 min |

**Total: ~57 minutes**

All 5 core files are Markdown documents — no Python code to write. The implementation effort is primarily in crafting precise agent instructions that produce the right JSON schemas at each pipeline stage.
