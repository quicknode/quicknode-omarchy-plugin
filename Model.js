// Parsing and formatting for QuickNode Admin API responses
// (https://api.quicknode.com/v0). Plain JS so it stays testable outside
// the shell, mirroring the first-party widgets' Model.js convention.

function toInt(value) {
  var n = parseInt(String(value), 10)
  return isNaN(n) ? null : n
}

function parseEnvelope(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return null
    if (data.error) return { error: String(data.error) }
    return data
  } catch (e) {
    return null
  }
}

// GET /v0/usage/rpc → { data: { credits_used, credits_remaining, limit,
// overages, start_time, end_time }, error }. Returns null when the payload
// is not JSON (treat as a transport failure worth retrying), or an
// { error } object when the API answered with an error message.
function parseUsage(raw) {
  var data = parseEnvelope(raw)
  if (!data || data.error) return data
  var d = data.data
  if (!d || typeof d !== "object") return null
  return {
    creditsUsed: toInt(d.credits_used),
    creditsRemaining: toInt(d.credits_remaining),
    limit: toInt(d.limit),
    overages: toInt(d.overages),
    startTime: toInt(d.start_time),
    endTime: toInt(d.end_time)
  }
}

// GET /v0/endpoints → { data: [ { id, name, label, status, chain, network,
// http_url, wss_url, ... } ], error }. Same null / { error } conventions.
function parseEndpoints(raw) {
  var data = parseEnvelope(raw)
  if (!data || data.error) return data
  if (!data.data || !data.data.length) return []
  var out = []
  for (var i = 0; i < data.data.length; i++) {
    var e = data.data[i]
    if (!e || !e.id) continue
    out.push({
      id: String(e.id),
      name: String(e.name || ""),
      label: String(e.label || e.name || e.id),
      chain: String(e.chain || ""),
      network: String(e.network || ""),
      httpUrl: String(e.http_url || ""),
      wssUrl: String(e.wss_url || ""),
      active: String(e.status || "").toLowerCase() !== "paused"
    })
  }
  return out
}

// GET /v0/usage/rpc/by-chain → { data: { chains: [ { name, credits_used,
// ... } ] } }. Returns a map of normalized chain name → credits used.
function parseChainUsage(raw) {
  var data = parseEnvelope(raw)
  if (!data || data.error) return data
  var chains = data.data && data.data.chains ? data.data.chains : []
  var out = {}
  for (var i = 0; i < chains.length; i++) {
    var c = chains[i]
    if (!c || !c.name) continue
    out[normalizeChain(c.name)] = toInt(c.credits_used) || 0
  }
  return out
}

// The endpoint list and the usage report don't necessarily spell a chain
// the same way ("eth" vs "ethereum", "matic" vs "polygon"), so both sides
// are reduced to a canonical token before matching.
var CHAIN_ALIASES = {
  eth: "ethereum",
  matic: "polygon",
  polygonpos: "polygon",
  bsc: "bnb",
  bnbchain: "bnb",
  binance: "bnb",
  binancesmartchain: "bnb",
  sol: "solana",
  btc: "bitcoin",
  avax: "avalanche",
  arb: "arbitrum",
  arbitrumone: "arbitrum",
  op: "optimism",
  ftm: "fantom",
  xdai: "gnosis",
  zksyncera: "zksync"
}

function normalizeChain(value) {
  var token = String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
  return CHAIN_ALIASES[token] || token
}

function chainCredits(chainUsage, chain) {
  if (!chainUsage || !chain) return null
  var wanted = normalizeChain(chain)
  if (chainUsage[wanted] !== undefined) return chainUsage[wanted]
  for (var key in chainUsage) {
    if (key.indexOf(wanted) === 0 || wanted.indexOf(key) === 0) return chainUsage[key]
  }
  return null
}

// Every whitespace-separated term must appear in the endpoint's label,
// subdomain, chain, or network (case-insensitive).
function filterEndpoints(endpoints, query) {
  var terms = String(query || "").toLowerCase().split(/\s+/).filter(function(t) { return t !== "" })
  if (!endpoints || !endpoints.length) return []
  if (terms.length === 0) return endpoints
  return endpoints.filter(function(e) {
    var haystack = [e.label, e.name, e.chain, e.network].join(" ").toLowerCase()
    for (var i = 0; i < terms.length; i++) {
      if (haystack.indexOf(terms[i]) === -1) return false
    }
    return true
  })
}

// Brand-colored badge per chain. Symbols are nerd-font glyphs where the
// font has one (ethereum, bitcoin), unicode where conventional (◎ solana),
// and the chain's initial otherwise. Unknown chains get a color derived
// from the name so the same chain always looks the same.
var CHAIN_BADGES = {
  ethereum:  { symbol: "󰡪", color: "#627EEA" },
  bitcoin:   { symbol: "󰠓", color: "#F7931A" },
  solana:    { symbol: "◎", color: "#9945FF" },
  base:      { symbol: "B", color: "#0052FF" },
  arbitrum:  { symbol: "A", color: "#28A0F0" },
  optimism:  { symbol: "OP", color: "#FF0420" },
  polygon:   { symbol: "P", color: "#8247E5" },
  bnb:       { symbol: "B", color: "#F0B90B" },
  avalanche: { symbol: "A", color: "#E84142" },
  fantom:    { symbol: "F", color: "#1969FF" },
  gnosis:    { symbol: "G", color: "#04795B" },
  zksync:    { symbol: "Z", color: "#8C8DFC" },
  linea:     { symbol: "L", color: "#3FA7D6" },
  scroll:    { symbol: "S", color: "#D8A468" },
  blast:     { symbol: "B", color: "#B8B800" },
  near:      { symbol: "N", color: "#00C08B" },
  tron:      { symbol: "T", color: "#EF0027" },
  xrp:       { symbol: "X", color: "#346AA9" },
  sui:       { symbol: "S", color: "#4DA2FF" },
  aptos:     { symbol: "A", color: "#2DD8A3" },
  celo:      { symbol: "C", color: "#C9CC00" },
  mantle:    { symbol: "M", color: "#65B3AE" },
  sei:       { symbol: "S", color: "#9E1F19" },
  berachain: { symbol: "B", color: "#814625" },
  monad:     { symbol: "M", color: "#836EF9" },
  cosmos:    { symbol: "C", color: "#2E3148" },
  polkadot:  { symbol: "P", color: "#E6007A" },
  cardano:   { symbol: "C", color: "#0033AD" },
  ton:       { symbol: "T", color: "#0098EA" },
  stellar:   { symbol: "S", color: "#7D8B99" },
  algorand:  { symbol: "A", color: "#5C6AC4" }
}

// Chains with a bundled logo in icons/<slug>.svg (see scripts/fetch-icons.sh).
// Keyed by the raw QuickNode slug, which is what an endpoint's `chain` is.
var CHAIN_ICONS = {}
;("0g abstract apt arb arc ault avax base bch bera blast bsc btc celestia celo cosmos doge dot eth "
  + "flare flow fraxtal fuel gravity hedera hemi hype injective ink joc kaia katana linea lisk ltc "
  + "mantle matic megaeth mode monad near nova optimism osmosis peaq plasma robinhood scroll sei sol "
  + "soneium sonic stellar strk stx sui tempo ton tron unichain vana worldchain xdai xlayer xrp "
  + "xrplevm zec zksync zora").split(" ").forEach(function(slug) { CHAIN_ICONS[slug] = true })

function chainIcon(chain) {
  var slug = String(chain || "").toLowerCase()
  return CHAIN_ICONS[slug] ? "icons/" + slug + ".svg" : ""
}

function chainBadge(chain) {
  var key = normalizeChain(chain)
  if (CHAIN_BADGES[key]) return CHAIN_BADGES[key]
  var hash = 0
  for (var i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) & 0xffffffff
  var hue = Math.abs(hash) % 360
  return {
    symbol: key === "" ? "?" : key.charAt(0).toUpperCase(),
    color: hslToHex(hue, 0.55, 0.45)
  }
}

function hslToHex(h, s, l) {
  var c = (1 - Math.abs(2 * l - 1)) * s
  var x = c * (1 - Math.abs((h / 60) % 2 - 1))
  var m = l - c / 2
  var r = 0, g = 0, b = 0
  if (h < 60) { r = c; g = x } else if (h < 120) { r = x; g = c } else if (h < 180) { g = c; b = x }
  else if (h < 240) { g = x; b = c } else if (h < 300) { r = x; b = c } else { r = c; b = x }
  function hex(v) {
    var s = Math.round((v + m) * 255).toString(16)
    return s.length === 1 ? "0" + s : s
  }
  return "#" + hex(r) + hex(g) + hex(b)
}

// Whole percent once usage is meaningful, one decimal below 10% so a large
// plan doesn't sit at "0%" for most of the month.
function usagePercent(usage) {
  if (!usage || usage.creditsUsed === null || !usage.limit) return null
  var pct = usage.creditsUsed / usage.limit * 100
  return pct < 10 ? Math.round(pct * 10) / 10 : Math.round(pct)
}

// Bar text is the bare number; the pill's logo already says what it is.
function barLabel(percent) {
  return percent === null || percent === undefined ? "" : String(percent)
}

// Compact credit counts for the stats row: 1234 → "1.2K", 56000000 → "56M".
function formatCredits(value) {
  if (value === null || value === undefined) return "—"
  var n = Number(value)
  if (isNaN(n)) return "—"
  if (n >= 1e9) return compact(n / 1e9) + "B"
  if (n >= 1e6) return compact(n / 1e6) + "M"
  if (n >= 1e3) return compact(n / 1e3) + "K"
  return String(n)
}

function compact(n) {
  var rounded = Math.round(n * 10) / 10
  return String(rounded >= 100 ? Math.round(rounded) : rounded)
}

// Days until the billing period rolls over. The usage report's end_time is
// just "now"; start_time is the first of the month, so the period ends at
// the start of the following month (UTC). "today" inside the final day.
function resetShort(startTime, nowMs) {
  if (!startTime) return "—"
  var start = new Date(startTime * 1000)
  var periodEnd = Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 1)
  var msLeft = periodEnd - nowMs
  if (msLeft <= 0) return "—"
  var days = Math.floor(msLeft / 86400000)
  return days < 1 ? "today" : days + "d"
}

function maskedKey(key) {
  var k = String(key || "")
  if (k === "") return ""
  return k.length <= 4 ? "••••" : "••••" + k.slice(-4)
}

function endpointLocation(endpoint) {
  if (!endpoint) return ""
  return [endpoint.chain, endpoint.network]
    .filter(function(part) { return !!part })
    .join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseUsage: parseUsage,
    parseEndpoints: parseEndpoints,
    parseChainUsage: parseChainUsage,
    normalizeChain: normalizeChain,
    chainCredits: chainCredits,
    filterEndpoints: filterEndpoints,
    chainBadge: chainBadge,
    chainIcon: chainIcon,
    usagePercent: usagePercent,
    barLabel: barLabel,
    formatCredits: formatCredits,
    resetShort: resetShort,
    maskedKey: maskedKey,
    endpointLocation: endpointLocation
  }
}
