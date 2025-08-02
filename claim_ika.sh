#!/usr/bin/env bash
set -euo pipefail

curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc

suiup install sui@mainnet-1.52.3
sui --version

rm -f ~/.sui/sui_config/client.yaml
sui client new-env <<EOF
y
https://fullnode.mainnet.sui.io:443
mainnet
0
EOF

sui client switch --env mainnet


if ! command -v jq &>/dev/null; then
  echo "Installing jq..."
  sudo apt update && sudo apt install -y jq
fi

PACKAGE_ID="0x5a6ae39fd84a871e94c88badc7689debae22119461ba1581f674bfe50acc1271"
AIRDROP_POOL="0xf040974b98d008efccf0cee6cbaf0a456a76536601248d99fb9625d7fc8185e7"
GAS_AMOUNT_MIST=1000000000   # ~ 1 $SUI


read -rp "Enter your Sui address for allocation check: " TARGET_ADDR

echo "Fetching on-chain objects for $TARGET_ADDR..."
sui client objects "$TARGET_ADDR" --json > objs.json


IKADROP_ID=$(jq -r '
  .[]
  | select(.data.type | test("::distribution::IKADrop"))
  | .data.objectId
' objs.json || true)

if [[ -z "$IKADROP_ID" ]]; then
  echo "No IKADrop object found for $TARGET_ADDR. Exiting."
  exit 1
fi
echo "Found IKADrop ID: $IKADROP_ID"

sui client object "$IKADROP_ID" --json > ikadrop.json
AMOUNT=$(jq -r '.data.content.fields.normalized_amount // .content.fields.normalized_amount' ikadrop.json)
echo "Claimable IKA: $AMOUNT"


echo
echo "1) Claim IKA allocation"
echo "2) Exit"
read -rp "Select an option (1 or 2): " CHOICE
if [[ "$CHOICE" != "1" ]]; then
  echo "Exiting."
  exit 0
fi


read -rp "Enter your mnemonic or private key: " KEYSTRING
echo "$KEYSTRING" | sui keytool import --scheme ed25519 --privkey >/dev/null


echo "Fetching SUI coins for gas..."
sui client gas "$TARGET_ADDR" --json > gas.json
GAS_COIN=$(jq -r '.[0].gasCoinId // .[0].coinObjectId' gas.json || true)

if [[ -z "$GAS_COIN" ]]; then
  echo "No SUI gas coin found. Exiting."
  exit 1
fi
echo "Using gas coin: $GAS_COIN"


read -rp "About to use 1 SUI as gas. Continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi



mapfile -t SBT_IDS < <(jq -r '
  .[]
  | select(.data.type | test("::sbt::SoulBoundToken"))
  | .data.objectId
' objs.json)

if [[ ${#SBT_IDS[@]} -eq 0 ]]; then
  echo "No SoulBoundToken found, will use plain claim."
  USE_SBT=false
elif [[ ${#SBT_IDS[@]} -eq 1 ]]; then
  SBT_ID="${SBT_IDS[0]}"
  echo "Found one SoulBoundToken: $SBT_ID"
  USE_SBT=true
else
  echo "Multiple SoulBoundTokens found:"
  for i in "${!SBT_IDS[@]}"; do
    echo "  [$((i+1))] ${SBT_IDS[i]}"
  done
  read -rp "Select which SBT to use [1-${#SBT_IDS[@]}]: " sel
  if (( sel >= 1 && sel <= ${#SBT_IDS[@]} )); then
    SBT_ID="${SBT_IDS[sel-1]}"
    echo "Using SBT: $SBT_ID"
    USE_SBT=true
  else
    echo "Invalid selection, exiting."
    exit 1
  fi
fi


if [[ "$USE_SBT" == true ]]; then
  echo "Submitting claim_sbt transaction…"
  TX_DIGEST=$(sui client call \
    --package "$PACKAGE_ID" \
    --module distribution \
    --function claim_sbt \
    --args \
      "$AIRDROP_POOL" \
      "$IKADROP_ID" \
      1 \
      "$GAS_COIN" \
      "$SBT_ID" \
    --gas-budget "$GAS_AMOUNT_MIST" \
    --json \
  | jq -r '.digest')
else
  echo "Submitting plain claim transaction…"
  TX_DIGEST=$(sui client call \
    --package "$PACKAGE_ID" \
    --module distribution \
    --function claim \
    --args \
      "$AIRDROP_POOL" \
      "$IKADROP_ID" \
      1 \
      "$GAS_COIN" \
    --gas-budget "$GAS_AMOUNT_MIST" \
    --json \
  | jq -r '.digest')
fi

echo
echo "✅ Claimed! Transaction hash: $TX_DIGEST"
echo "View on Explorer:"
echo "https://explorer.sui.io/transactions/$TX_DIGEST?network=mainnet"

echo "please donate some sui for the work put in this... thanks🙏"
echo "SUI ADDRESS : 0x0ca92bf91d52594745bd6538f73363e6ecc80a133bf8985c308ff19f92b40083 "
