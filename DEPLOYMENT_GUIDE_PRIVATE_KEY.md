# 🚀 Earnscape Deployment Guide - Private Key Method

Complete guide to deploy all Earnscape contracts using an external wallet private key.

## 📋 Table of Contents
1. [Prerequisites](#prerequisites)
2. [Setup](#setup)
3. [Deployment](#deployment)
4. [Configuration](#configuration)
5. [Testing](#testing)
6. [Final Steps](#final-steps)
7. [Troubleshooting](#troubleshooting)

---

## ✅ Prerequisites

Before deploying, ensure you have:

- **Starkli** installed and updated
- **Scarb** (Cairo compiler) installed
- **External wallet private key** with testnet ETH
- **Minimum 0.1 ETH** on Sepolia testnet for gas fees

### Check Your Setup:
```bash
# Check starkli version
starkli --version

# Check scarb version
scarb --version

# Check if contracts compile
scarb build
```

---

## 🔧 Setup

### Step 1: Set Your Private Key

**IMPORTANT:** Your private key should start with `0x`

```bash
# Export your private key (DO NOT share this!)
export DEPLOYER_PRIVATE_KEY='0x<your_private_key_here>'

# Verify it's set
echo $DEPLOYER_PRIVATE_KEY
```

### Step 2: Check Your Balance

```bash
# Option A (recommended): Manually derive or supply your deployer/account address
# If you already have an account deployed, set its address explicitly:
export DEPLOYER_ADDRESS='0x<your_account_address_here>'
echo "Your address: $DEPLOYER_ADDRESS"

# Option B: Derive the address from a private key using a library such as
# `starknet_py` (Python) or `starknet.js`. Example (requires starknet_py):
#
# python -c "from starknet_py.net.account.account import AccountClient\nfrom starknet_py.net.signer.stark_curve import pedersen\nprint('See starknet_py docs for deriving address from private key')"

### Optional: Use starkli keystore helper to inspect public key
If you only have a raw private key and want to see the corresponding public key (stark key), you can create a temporary keystore and inspect it with `starkli`:

```bash
# Create a temporary keystore from private key (non-interactive)
printf "%s" "$DEPLOYER_PRIVATE_KEY" | starkli signer keystore from-key /tmp/deployer-keystore.json --private-key-stdin --password "temp-pass" --force

# Inspect the keystore and print the raw public key
starkli signer keystore inspect --raw /tmp/deployer-keystore.json --password "temp-pass"

# Remove temporary keystore when done
rm -f /tmp/deployer-keystore.json
```

Note: The public key is NOT the same as an account address; many account contracts derive their own address from the public key at deploy-time. Use the public key to deploy an account or set `DEPLOYER_ADDRESS` to an existing deployed account address.

# Check balance (replace with your chosen RPC if needed)
starkli balance $DEPLOYER_ADDRESS --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7
```

**Need testnet ETH?** Get from faucet:
- https://starknet-faucet.vercel.app/
- https://blastapi.io/faucets/starknet-sepolia-eth

---

## 🚀 Deployment

### Step 3: Make Scripts Executable

```bash
chmod +x deploy_with_private_key.sh
chmod +x configure_contracts.sh
```

### Step 4: Deploy All Contracts

```bash
./deploy_with_private_key.sh
```

**What happens during deployment:**

1. ✅ Builds all contracts
2. ✅ Declares contract classes (7 contracts)
3. ✅ Deploys all contracts with constructor arguments
4. ✅ Saves addresses to `deployed_addresses.env`
5. ✅ Creates deployment log file

**Expected time:** 5-10 minutes (depends on network)

### Deployed Contracts:

| # | Contract | Description |
|---|----------|-------------|
| 1 | EarnsToken | Main EARN ERC20 token (1B supply) |
| 2 | StEarnToken | Staked EARN token (minted by Staking) |
| 3 | EarnXDCManager | XDC Network bridge manager |
| 4 | BulkVesting | 9-category bulk vesting contract |
| 5 | Escrow | Token distribution and treasury |
| 6 | Staking | 6-category staking with StEARN |
| 7 | Vesting | Individual vesting with tipping |

---

## ⚙️ Configuration

### Step 5: Load Deployed Addresses

```bash
source deployed_addresses.env
```

This exports all contract addresses to your environment:
- `DEPLOYER_ADDRESS`
- `EARNS_ADDR`
- `STEARN_ADDR`
- `EARNXDC_ADDR`
- `BULK_VESTING_ADDR`
- `ESCROW_ADDR`
- `STAKING_ADDR`
- `VESTING_ADDR`

### Step 6: Configure Contracts

```bash
./configure_contracts.sh
```

**This script automatically:**

1. ✅ Sets `contract4` (BulkVesting) and `contract5` (Escrow) in EarnsToken
2. ✅ Transfers StEarnToken ownership to Staking contract
3. ✅ Verifies all configurations

---

## 🧪 Testing

### Step 7: Update Test Scripts with New Addresses

The `load_addresses.sh` script needs to be updated with your new deployment:

```bash
# Edit load_addresses.sh and replace the addresses with your deployed ones
nano load_addresses.sh
```

Or run this to auto-update:

```bash
cat > load_addresses.sh << EOF
#!/bin/bash

# Load deployed addresses from deployed_addresses.env
if [ -f "deployed_addresses.env" ]; then
    source deployed_addresses.env
    
    # Also export OWNER_ADDR for backward compatibility
    export OWNER_ADDR=\$DEPLOYER_ADDRESS
    
    echo "✓ Addresses loaded from deployed_addresses.env"
else
    echo "❌ Error: deployed_addresses.env not found"
    exit 1
fi
EOF
```

### Step 8: Run Tests

```bash
# Load addresses
source deployed_addresses.env

# Run test menu
./run_tests.sh
```

**Available Tests:**
- Quick Status Check (all 7 contracts)
- Individual contract tests
- Batch testing
- Write function tests (with gas)

---

## 🎯 Final Steps

### Step 9: Verify Token Distribution

Before renouncing ownership, check where tokens are:

```bash
# Check EarnsToken balance (should have 1B tokens)
starkli call $EARNS_ADDR balance_of $EARNS_ADDR --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7

# Check total supply
starkli call $EARNS_ADDR total_supply --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7
```

Expected result:
- Contract balance: `1,000,000,000 EARN` (all tokens)
- Total supply: `1,000,000,000 EARN`

### Step 10: Renounce Ownership (CRITICAL!)

**⚠️ WARNING: This is PERMANENT and CANNOT be undone!**

This function will:
1. Transfer all 1B EARN tokens from contract to BulkVesting
2. Permanently renounce ownership (no owner can ever modify the contract)

```bash
# Make sure you're ready!
# sold_supply = 1,000,000,000 EARN = 1000000000000000000000000000 (with 18 decimals)

starkli invoke $EARNS_ADDR renounce_ownership_with_transfer \
  1000000000000000000000000000 \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7
```

**After renouncing:**
- ✅ BulkVesting has 1B EARN tokens
- ✅ No owner can modify EarnsToken
- ✅ Contract is fully decentralized

---

## 🐛 Troubleshooting

### Issue: "Could not derive address from private key"

**Solution:** Make sure private key starts with `0x`
```bash
export DEPLOYER_PRIVATE_KEY='0x1234...'
```

### Issue: "Insufficient balance"

**Solution:** Get testnet ETH from faucet:
- https://starknet-faucet.vercel.app/

### Issue: "Contract already declared"

**Solution:** This is OK! The script will use the existing class hash.

### Issue: "Transaction failed"

**Solution:** 
1. Check your balance
2. Wait a few seconds and retry
3. Check network status: https://status.starknet.io/

### Issue: "renounce_ownership_with_transfer fails with 'insufficient balance'"

**Solution:** This means tokens are in wrong address. Check:
```bash
# Where are the tokens?
starkli call $EARNS_ADDR balance_of $EARNS_ADDR
starkli call $EARNS_ADDR balance_of $DEPLOYER_ADDRESS
```

The tokens should be in the **contract address** (`$EARNS_ADDR`), not the deployer address.

---

## 📊 Deployment Checklist

Use this checklist to track your deployment:

- [ ] Prerequisites installed (starkli, scarb)
- [ ] Private key exported to `DEPLOYER_PRIVATE_KEY`
- [ ] Sufficient testnet ETH in wallet (0.1+ ETH)
- [ ] Contracts compiled successfully (`scarb build`)
- [ ] All contracts deployed (`./deploy_with_private_key.sh`)
- [ ] Addresses loaded (`source deployed_addresses.env`)
- [ ] Contracts configured (`./configure_contracts.sh`)
- [ ] Configuration verified (contract4, contract5, StEARN owner)
- [ ] Tests run successfully (`./run_tests.sh`)
- [ ] Token distribution verified (1B in contract)
- [ ] Ownership renounced (when ready for production)

---

## 🔗 Useful Links

- **StarkScan (Sepolia):** https://sepolia.starkscan.co/
- **Starknet Faucet:** https://starknet-faucet.vercel.app/
- **Starkli Docs:** https://book.starkli.rs/
- **Cairo Book:** https://book.cairo-lang.org/

---

## 📝 Notes

- All deployment logs are saved to `deployment_YYYYMMDD_HHMMSS.log`
- All addresses are saved to `deployed_addresses.env`
- Keep your private key secure - NEVER commit it to git!
- For mainnet deployment, replace RPC URL with mainnet endpoint

---

## 🆘 Need Help?

If you encounter issues:

1. Check deployment logs: `cat deployment_*.log`
2. Verify contract addresses: `cat deployed_addresses.env`
3. Check transaction on StarkScan using contract address
4. Review error messages carefully

---

**Good luck with your deployment! 🚀**
