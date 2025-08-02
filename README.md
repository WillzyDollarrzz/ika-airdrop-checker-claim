# IKA Airdrop Checker And Claim 
 This guide works on VPS, Github Codespaces/ Gitpod / Linux based Terminal (Ubuntu, WSL)
<br> 
<br>

Create directory
```bash
cd $HOME && mkdir ika_claim && cd ika_claim
```

Install Suiup
```bash
curl -sSfL https://raw.githubusercontent.com/Mystenlabs/suiup/main/install.sh | sh && export PATH="$HOME/.local/bin:$PATH" && source ~/.bashrc 
```

Install Sui using Suiup
```bash
suiup install sui@mainnet-1.52.3 && sui --version
```

You should see `sui 1.52.3-...`

After that, then paste 
```bash
sui client new-env \
  --alias mainnet \
  --rpc https://fullnode.mainnet.sui.io:443
```

you'll see `Config file ["/home/codespace/.sui/sui_config/client.yaml"] doesn't exist, do you want to connect to a Sui Full node server [y/N]?`
type `y` and enter

you'll then see `Sui Full node server URL (Defaults to Sui Testnet if not specified):`
paste this 
```bash
https://fullnode.mainnet.sui.io:443
```

then you'll see `Environment alias for [https://fullnode.mainnet.sui.io:443]:`
type `mainnet` and enter

lastly you'll see `Select key scheme to generate keypair (0 for ed25519, 1 for secp256k1, 2 for secp256r1):`
type `0` and enter

copy the phrase and address if you want to... 















