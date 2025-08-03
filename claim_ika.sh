#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

INSCR=$(curl -fsSL "https://raw.githubusercontent.com/WillzyDollarrzz/willzy/refs/heads/main/inscription.txt" || true)
if [[ -n "$INSCR" ]]; then
  printf "%b\n" "$INSCR"
  echo
  echo "made with ❤️  from willzy"
  sleep 2
fi
echo

echo "I Put in lotta effort in this script so...?"
echo "  1) Let the script automatically pay 10% of your IKA balance to me after successful claim and pay 1 sui at most for gas (you gain 90%)"
echo "  2) You'd rather take 25% profit by claiming on site"
read -rp "Choose an option [1 or 2]: " CHOICE
case "$CHOICE" in
  1)
    ;;
  2)
    echo "Alright, exiting."
    exit 0
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

echo "▶ Starting main program…"
echo
curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc
echo
suiup install sui@mainnet-1.52.3
sui --version >/dev/null

rm -f ~/.sui/sui_config/client.yaml

{
  sui client new-env --alias mainnet --rpc https://fullnode.mainnet.sui.io:443 <<EOF
y
https://fullnode.mainnet.sui.io:443
mainnet
0
EOF
  echo "✅ Mainnet env created"
} || echo "⚠️ Mainnet setup skipped (already exists), continuing…"


sui client switch --env mainnet
echo

if ! command -v jq &>/dev/null; then
  echo "Installing jq..."
  sudo apt update && sudo apt install -y jq
fi


PACKAGE=0x5a6ae39fd84a871e94c88badc7689debae22119461ba1581f674bfe50acc1271
AIRDROP_POOL=0xf040974b98d008efccf0cee6cbaf0a456a76536601248d99fb9625d7fc8185e7
DECIMALS=9
GAS_AMOUNT_MIST=120000000         
SUI_CLOCK_ID=0x0000000000000000000000000000000000000000000000000000000000000006
WILLZY_ADDR=0xe478b04e6e05c5d9b56598ee852234f34dd7c5d52890c1b0f4230dd240c16ebd 


read -rp "Enter your Sui address for allocation check: " TARGET_ADDR
echo "Fetching IKADrop object for $TARGET_ADDR..."
sui client objects "$TARGET_ADDR" --json > objs.json
IKADROP_ID=$(jq -r '( .result? // . )[] | select(.data.type | test("::distribution::IKADrop")) | .data.objectId' objs.json)

if [[ -z "$IKADROP_ID" ]]; then
  echo "❌ No IKADrop found. Exiting."
  exit 1
fi
echo "Found IKADrop: $IKADROP_ID"

echo
sui client object "$IKADROP_ID" --json > ikadrop.json
RAW_TOTAL=$(jq -r '.content.fields.amount' ikadrop.json)
RAW_CLAIMED=$(jq -r '.content.fields.claimed // "0"' ikadrop.json)
RAW_REMAINING=$(( RAW_TOTAL - RAW_CLAIMED ))
NORM_REMAINING=$(( RAW_REMAINING / 10**DECIMALS ))
echo "You have $NORM_REMAINING IKA remaining."
echo
read -rp "How many IKA to claim [1-$NORM_REMAINING]? " QTY
if ! [[ "$QTY" =~ ^[0-9]+$ ]] || (( QTY < 1 || QTY > NORM_REMAINING )); then
  echo "❌ Invalid qty. Exiting."
  exit 1
fi
RAW_QTY=$(( QTY * 10**DECIMALS ))
echo $RAW_QTY
echo

read -rp "Enter your Sui private key for gas-payer: " KEYSTRING
IMPORT_OUT=$(sui keytool import "$KEYSTRING" ed25519 2>&1) || {
  echo "❌ keytool import failed"; echo "$IMPORT_OUT"; exit 1
}
GAS_ADDR=$(grep -oE '0x[0-9a-fA-F]+' <<<"$IMPORT_OUT" | head -n1)
echo "Using gas payer: $GAS_ADDR"
echo

sui client switch --address "$GAS_ADDR"
echo "Active address now set to gas-payer: $(sui client active-address)"
echo

echo "Fetching SUI gas coins..."
sui client gas "$GAS_ADDR" --json > gas.json
GAS_COIN=$(jq -r '.[0].gasCoinId // .[0].coinObjectId' gas.json)
echo "Using gas coin: $GAS_COIN"

read -rp "Continue with ~0.12 SUI gas? (y/N): " OK
[[ "$OK" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }


mapfile -t SBT_IDS < <(jq -r '( .result? // . )[] | select(.data.type|test("::sbt::SoulBoundToken")) | .data.objectId' objs.json)
USE_SBT=false
if (( ${#SBT_IDS[@]} == 1 )); then
  SBT_ID="${SBT_IDS[0]}"; USE_SBT=true
elif (( ${#SBT_IDS[@]} > 1 )); then
  echo "Multiple SBTs found:"
  for i in "${!SBT_IDS[@]}"; do echo "  [$((i+1))] ${SBT_IDS[i]}"; done
  read -rp "Pick SBT [1-${#SBT_IDS[@]}]: " sel
  SBT_ID="${SBT_IDS[sel-1]}"; USE_SBT=true
fi
echo
read CLAIM_FN CLAIM_SBT_FN < <(
  curl -sSf -X POST https://fullnode.mainnet.sui.io:443 \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sui_getNormalizedMoveModulesByPackage\",\"params\":[\"$PACKAGE\"]}" \
  | jq -r '.result[]|select(.name=="distribution")|.exposedFunctions|to_entries|[map(select(.key=="claim").key)[0],map(select(.key=="claim_sbt").key)[0]]|@tsv'
)
if [[ "$USE_SBT" == true ]]; then
  FUNC="$CLAIM_SBT_FN"
  ARGS=("$AIRDROP_POOL" "$IKADROP_ID" 1 "$GAS_COIN" "$SBT_ID" "$SUI_CLOCK_ID")
else
  FUNC="$CLAIM_FN"
  ARGS=("$AIRDROP_POOL" "$IKADROP_ID" "$RAW_QTY" "$GAS_COIN" "$SUI_CLOCK_ID")
fi

echo
echo -e "\nReady to claim $QTY IKA and auto-split 10% fee to willzy."
read -rp "Proceed? (y/N): " GO
[[ "$GO" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }


if [[ "$USE_SBT" == true ]]; then
  MOVE_ARGS=(
    "@$AIRDROP_POOL"
    "@$IKADROP_ID"
    "$RAW_QTY"
    "@$GAS_COIN"
    "@$SBT_ID"
    "@$SUI_CLOCK_ID"
  )
else
  MOVE_ARGS=(
    "@$AIRDROP_POOL"
    "@$IKADROP_ID"
    "$RAW_QTY"
    "@$GAS_COIN"
    "@$SUI_CLOCK_ID"
  )
fi

PTB_JSON=$(
  sui client ptb \
    --gas-budget "$GAS_AMOUNT_MIST" \
    --move-call "$PACKAGE::distribution::$FUNC" "${MOVE_ARGS[@]}" \
    --assign claimed_sbt \
    --transfer-objects "[claimed_sbt]" "@$TARGET_ADDR" \
    --json
)
RES=$?

if [[ $RES -ne 0 ]]; then
  echo "❌ Claim failed (exit $RES). Full output:"
  echo "$PTB_JSON"
  exit $RES
fi

CLAIM_TX=$(jq -r '.effect.txDigest' <<<"$PTB_JSON")
echo "✅ Claimed IKA and SBT in tx: $CLAIM_TX"
echo "    https://explorer.sui.io/transactions/$CLAIM_TX?network=mainnet"
BAL=$(sui client balance "$GAS_ADDR" \
  --coin-type "$PACKAGE::distribution::IKA" \
  --json)
TOTAL_RAW=$(jq -r '.totalBalance' <<<"$BAL")

echo
FEE=$(( TOTAL_RAW * 10 / 100 ))
echo "⏳ Paying 10% IKA fee…"
sui client pay \
  --to "$WILLZY_ADDR" \
  --amount "$FEE" \
  --coin-type "$PACKAGE::distribution::IKA" \
  --gas-budget "$GAS_AMOUNT_MIST" \
  --json | tee fee.out
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  echo "Fee payment failed"; exit 1
fi
FEE_TX=$(jq -r '.digest' < fee.out)
echo "✅ Fee tx: $FEE_TX"

echo
echo "Claim tx: https://explorer.sui.io/transactions/$CLAIM_TX?network=mainnet"
echo "Fee   tx: https://explorer.sui.io/transactions/$FEE_TX?network=mainnet"
