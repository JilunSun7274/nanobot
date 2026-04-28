# Stock Research Skill 设计文档

**日期：** 2026-04-28
**状态：** 已批准，待实现
**市场范围：** A股（沪深两市）

---

## 一、背景与目标

构建一个 nanobot Skill，让 Agent 能够自动化执行 A股市场的全链路调研：从宏观扫描 → 板块筛选 → 个股深研 → 报告输出。支持手动触发和定时自动运行，输出聊天摘要和本地 Markdown 报告两种形式。

---

## 二、整体架构

采用**多 Agent 并行流水线**方案，由主 Skill 编排 4 个专职子 Agent：

```
触发（手动 /stock-research 或 cron）
          │
          ▼
  ┌─────────────────────────────────────┐
  │          macro-scanner              │
  │  • 拉取上证/深证/创业板指数          │
  │  • 北向资金流向                      │
  │  • 今日涨跌停数量、涨跌比            │
  │  • 两融余额变化                      │
  │  输出：市场情绪评分 + 简要判断        │
  └──────────────┬──────────────────────┘
                 │ 若情绪极度悲观 → 输出风险预警，终止
                 ▼
  ┌─────────────────────────────────────┐
  │         sector-screener             │
  │  • 行业板块涨幅排名（TOP 5）         │
  │  • 板块资金净流入                    │
  │  • 概念热点题材                      │
  │  输出：推荐板块列表 + 候选股票池      │
  │        （每个板块取 1-2 只龙头股）   │
  └──────────────┬──────────────────────┘
                 │ 并行（最多 5 只）
         ┌───────┼───────┐
         ▼       ▼       ▼
  ┌──────────┐ ┌──────┐ ┌──────┐
  │stock-    │ │stock-│ │stock-│
  │researcher│ │      │ │      │
  │• 财务指标│ │ ...  │ │ ...  │
  │• K线分析 │ │      │ │      │
  │• 新闻搜索│ │      │ │      │
  │• 风险提示│ │      │ │      │
  └──────────┘ └──────┘ └──────┘
                 │
                 ▼
  ┌─────────────────────────────────────┐
  │          report-writer              │
  │  • 合并所有子 Agent 输出             │
  │  • 生成聊天摘要（<500字）            │
  │  • 生成完整 Markdown 报告            │
  │  • 保存到 docs/research/YYYY-MM-DD  │
  └─────────────────────────────────────┘
```

---

## 三、数据源

### macro-scanner
| 数据 | 来源 | 成本 |
|------|------|------|
| 大盘指数（上证、深证、创业板） | AKShare `stock_zh_index_spot` | 免费 |
| 北向资金流入/流出 | AKShare `stock_hsgt_north_net_flow` | 免费 |
| 市场情绪（涨跌停数量、涨跌比） | AKShare `stock_market_activity_legu` | 免费 |
| 融资融券余额 | AKShare `stock_margin_sse` | 免费 |

### sector-screener
| 数据 | 来源 | 成本 |
|------|------|------|
| 行业板块涨跌幅排名 | AKShare `stock_sector_spot` | 免费 |
| 板块资金流向 | AKShare `stock_fund_flow_industry` | 免费 |
| 概念热点题材 | AKShare `stock_hot_concept_spot` | 免费 |

### stock-researcher
| 数据 | 来源 | 成本 |
|------|------|------|
| 财务指标（PE/PB/ROE/毛利率） | Tushare Pro `fina_indicator` | 付费积分 |
| 近期财报（营收、利润） | Tushare Pro `income` | 付费积分 |
| K线/技术指标 | AKShare `stock_zh_a_hist` | 免费 |
| 股东变化/机构持仓 | Tushare Pro `top10_floatholders` | 付费积分 |
| 最新新闻/公告 | DuckDuckGo Web 搜索（可扩展为 Kagi） | 免费 |
| 分析师评级 | DuckDuckGo Web 搜索 | 免费 |

**降级策略：** 若 Tushare 积分不足，自动降级到 AKShare 财务接口（覆盖率约 80%）。

**Web 搜索扩展点：** 默认使用 DuckDuckGo（免费），预留配置项可切换到 Kagi（nanobot 已集成）。

---

## 四、流水线关键决策

- **宏观熔断：** 若市场情绪评分 < 阈值（极度恐慌），直接输出风险预警并终止，不做选股
- **候选股上限：** 最多 5 只，避免并行 Agent 过多消耗 token
- **预计耗时：** 每只股票调研约 60-90 秒，5 只并行总耗时约 2 分钟

---

## 五、输出格式

### 聊天摘要（即时发送，<500字）

```
📊 市场日报 · YYYY-MM-DD

【宏观】上证 +X%，北向净流入 XX亿，市场情绪：XX
【热点板块】XX / XX / XX

【今日关注】
1. 股票A(XXXXXX) — 核心逻辑一句话
2. 股票B(XXXXXX) — 核心逻辑一句话
3. 股票C(XXXXXX) — 核心逻辑一句话

⚠️ 风险提示：以上仅为调研结果，不构成投资建议
```

### 完整报告（Markdown 文件）

路径：`docs/research/YYYY-MM-DD-market-research.md`

包含章节：
1. 宏观市场概况（指数、资金、情绪表格）
2. 热点板块分析
3. 个股深度调研（每只含基本面/技术面/新闻/风险）
4. 综合建议
5. 免责声明

---

## 六、文件结构

```
~/.claude/skills/
└── stock-research/
    └── SKILL.md              # 主编排 Skill（入口）

~/.claude/agents/
├── macro-scanner.md          # 宏观市场扫描子 Agent
├── sector-screener.md        # 板块筛选子 Agent
├── stock-researcher.md       # 个股深研子 Agent
└── report-writer.md          # 报告生成子 Agent

# 报告输出位置
docs/research/
└── YYYY-MM-DD-market-research.md
```

---

## 七、触发机制

### 手动触发

```
/stock-research                          # 运行完整流程
/stock-research --stocks 688981,002594   # 跳过筛选，直接调研指定股票
/stock-research --sector 半导体          # 只看特定板块
```

### 定时触发（nanobot cron）

```yaml
scheduler:
  jobs:
    - cron: "30 8 * * 1-5"   # 每个工作日早盘前 8:30
      skill: stock-research
      channel: feishu         # 结果推送到飞书
```

---

## 八、依赖环境变量

```
TUSHARE_TOKEN=xxx    # Tushare Pro token（可选，无则降级到 AKShare）
```

AKShare 和 DuckDuckGo 开箱即用，无需额外配置。

---

## 九、后续扩展点

- Web 搜索替换为 Kagi（已预留配置项）
- 新增港股/美股支持（扩展 sector-screener 数据源）
- 新增量化回测 Agent（验证选股策略历史表现）
- 接入 Notion/飞书文档自动归档报告
