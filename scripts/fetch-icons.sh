#!/usr/bin/env bash
# Downloads chain logos from web3icons (MIT, https://github.com/0xa3k5/web3icons)
# into icons/<quicknode-chain-slug>.svg. The left column is the slug QuickNode
# uses in /v0/chains and on each endpoint's `chain`; the right column is the
# web3icons file, prefixed with `networks/` or `tokens/`. Re-run to refresh.
# After changing the list, update CHAIN_ICONS in Model.js to match.
#
# No logo is available upstream for: morph, 0g, cyber, story, sahara, moca,
# b3 — those fall back to the lettered badge in the panel.

set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p icons

BASE="https://raw.githubusercontent.com/0xa3k5/web3icons/main/raw-svgs"

declare -A ICONS=(
  [abstract]="networks/branded/abstract"
  [apt]="networks/branded/aptos"
  [arb]="networks/branded/arbitrum-one"
  [arc]="networks/branded/arc"
  [ault]="networks/branded/vaulta"
  [avax]="networks/branded/avalanche"
  [base]="networks/branded/base"
  [bch]="tokens/branded/BCH"
  [bera]="networks/branded/berachain"
  [blast]="networks/branded/blast"
  [bsc]="networks/branded/binance-smart-chain"
  [btc]="networks/branded/bitcoin"
  [celestia]="tokens/branded/TIA"
  [celo]="networks/branded/celo"
  [cosmos]="networks/branded/cosmos-hub"
  [doge]="tokens/branded/DOGE"
  [dot]="networks/branded/polkadot"
  [eth]="networks/branded/ethereum"
  [flare]="networks/branded/flare"
  [flow]="tokens/branded/FLOW"
  [fraxtal]="networks/branded/fraxtal"
  [fuel]="networks/branded/fuel"
  [gravity]="networks/branded/gravity"
  [hedera]="networks/branded/hedera-hashgraph"
  [hemi]="networks/branded/hemi"
  [hype]="networks/branded/hyper-evm"
  [injective]="networks/branded/injective"
  [ink]="networks/branded/ink"
  [joc]="networks/branded/japan-open-chain"
  [kaia]="networks/branded/kaia"
  [katana]="networks/branded/katana"
  [linea]="networks/branded/linea"
  [lisk]="networks/branded/lisk"
  [ltc]="networks/branded/litecoin"
  [mantle]="networks/branded/mantle"
  [matic]="networks/branded/polygon"
  [megaeth]="networks/branded/mega-eth"
  [mode]="networks/branded/mode"
  [monad]="networks/branded/monad"
  [near]="networks/branded/near-protocol"
  [nova]="networks/branded/arbitrum-nova"
  [optimism]="networks/branded/optimism"
  [osmosis]="networks/branded/osmosis"
  [peaq]="networks/branded/peaq"
  [plasma]="networks/branded/plasma"
  [robinhood]="networks/branded/robinhood"
  [scroll]="networks/branded/scroll"
  [sei]="networks/branded/sei-network"
  [sol]="networks/branded/solana"
  [soneium]="networks/branded/soneium"
  [sonic]="networks/branded/sonic"
  [stellar]="networks/branded/stellar"
  [strk]="networks/branded/starknet"
  [stx]="networks/branded/stacks"
  [sui]="networks/branded/sui"
  [tempo]="networks/branded/tempo"
  [ton]="networks/branded/ton"
  [tron]="networks/branded/tron"
  [unichain]="networks/branded/unichain"
  [vana]="networks/branded/vana"
  [worldchain]="networks/branded/world"
  [xdai]="networks/branded/gnosis"
  [xlayer]="networks/branded/x-layer"
  [xrp]="networks/branded/xrp"
  [xrplevm]="networks/branded/xrp"
  [zec]="tokens/branded/ZEC"
  [zksync]="networks/branded/zksync"
  [zora]="networks/branded/zora"
)

ok=0
missing=()
for slug in "${!ICONS[@]}"; do
  url="$BASE/${ICONS[$slug]}.svg"
  if curl -fsSL --max-time 20 "$url" -o "icons/$slug.svg"; then
    ok=$((ok + 1))
  else
    rm -f "icons/$slug.svg"
    missing+=("$slug")
  fi
done

echo "downloaded $ok icons"
if ((${#missing[@]})); then
  echo "no icon for: ${missing[*]}"
fi
