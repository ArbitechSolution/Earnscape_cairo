# Earnscape Deployment Function Reference

## Overview
This document explains **exactly which functions** are called during deployment and **why**.

---

## 📋 Function Calls During Deployment

### 1. EarnsToken.set_contract4()
```cairo
fn set_contract4(
    ref self: ContractState,
    _contract4: ContractAddress,  // Escrow address
    _contract5: ContractAddress   // BulkVesting address
)
```

**What it does:**
- Sets two authorized contracts that can interact with EarnsToken
- `contract4` = Escrow contract
- `contract5` = BulkVesting contract

**Why we call it:**
- EarnsToken needs to know which contracts are allowed to transfer tokens
- Escrow will distribute tokens to BulkVesting
- BulkVesting will release vested tokens to users

**Command in deploy.sh:**
```bash
starkli invoke \
    $EARNS_ADDR \                    # Call EarnsToken contract
    set_contract4 \                   # Function name
    $ESCROW_ADDR \                    # Parameter 1: contract4 (Escrow)
    $BULK_VESTING_ADDR \              # Parameter 2: contract5 (BulkVesting)
    --account $ACCOUNT_FILE \
    --keystore $KEYSTORE_FILE \
    --rpc $RPC_URL
```

---

### 2. Escrow.set_contract4()
```cairo
fn set_contract4(
    ref self: ContractState,
    contract4: ContractAddress  // BulkVesting address
)
```

**What it does:**
- Sets the BulkVesting contract address in Escrow
- Allows Escrow to send tokens to BulkVesting for distribution

**Why we call it:**
- Escrow holds the tokens initially
- BulkVesting needs to pull tokens from Escrow for vesting schedules
- This creates the link: Escrow → BulkVesting → Users

**Command in deploy.sh:**
```bash
starkli invoke \
    $ESCROW_ADDR \                    # Call Escrow contract
    set_contract4 \                   # Function name
    $BULK_VESTING_ADDR \              # Parameter: contract4 (BulkVesting)
    --account $ACCOUNT_FILE \
    --keystore $KEYSTORE_FILE \
    --rpc $RPC_URL
```

---

### 3. Staking.set_contract3()
```cairo
fn set_contract3(
    ref self: ContractState,
    new_contract: ContractAddress  // Vesting contract address
)
```

**What it does:**
- Links the Staking contract to the Vesting contract
- Allows stakers to use their staked tokens for tipping in Vesting

**Why we call it:**
- Users who stake tokens get stEARN tokens
- They can use stEARN to tip creators in the Vesting contract
- Staking needs to communicate with Vesting for reward distribution

**Command in deploy.sh:**
```bash
starkli invoke \
    $STAKING_ADDR \                   # Call Staking contract
    set_contract3 \                   # Function name
    $VESTING_ADDR \                   # Parameter: contract3 (Vesting)
    --account $ACCOUNT_FILE \
    --keystore $KEYSTORE_FILE \
    --rpc $RPC_URL
```

---

### 4. StEarnToken.transfer_ownership()
```cairo
fn transfer_ownership(
    ref self: ContractState,
    new_owner: ContractAddress  // New owner address
)
```

**What it does:**
- Transfers ownership of StEarnToken contract to Staking contract
- After this, **only Staking contract** can mint/burn stEARN tokens

**Why we call it:**
- StEarnToken should only be minted when users stake
- StEarnToken should only be burned when users unstake
- Staking contract needs exclusive control over stEARN supply

**Command in deploy.sh:**
```bash
starkli invoke \
    $STEARN_ADDR \                    # Call StEarnToken contract
    transfer_ownership \              # Function name
    $STAKING_ADDR \                   # Parameter: new_owner (Staking)
    --account $ACCOUNT_FILE \
    --keystore $KEYSTORE_FILE \
    --rpc $RPC_URL
```

---

## 🔗 Contract Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    EARNSCAPE CONTRACT ECOSYSTEM                  │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐
│  EarnsToken  │  (Main ERC20 Token)
│   (EARN)     │
└──────┬───────┘
       │ set_contract4(Escrow, BulkVesting)
       ├───────────────────────┐
       ↓                       ↓
┌──────────────┐        ┌────────────────┐
│    Escrow    │───────>│  BulkVesting   │  
│              │        │  (9 Categories)│
└──────────────┘        └────────────────┘
       │ set_contract4(BulkVesting)
       │
       └──────> Sends tokens to BulkVesting for distribution

┌──────────────┐        ┌────────────────┐
│   Staking    │<───────│  StEarnToken   │
│ (6 Categories)│        │    (stEARN)    │
└──────┬───────┘        └────────────────┘
       │ set_contract3(Vesting)      ↑
       │                              │ transfer_ownership(Staking)
       ↓                              │
┌──────────────┐                      │
│   Vesting    │──────────────────────┘
│  (Tipping)   │  Staking controls stEARN mint/burn
└──────────────┘

┌──────────────┐
│ EarnXDCManager│  (Bridge to XDC Network - separate)
└──────────────┘
```

---

## 📝 Function Summary Table

| Function | Contract | Parameters | Purpose |
|----------|----------|------------|---------|
| `set_contract4()` | EarnsToken | contract4, contract5 | Authorize Escrow & BulkVesting |
| `set_contract4()` | Escrow | contract4 | Link to BulkVesting |
| `set_contract3()` | Staking | new_contract | Link to Vesting |
| `transfer_ownership()` | StEarnToken | new_owner | Give control to Staking |

---

## 🎯 Token Flow After Configuration

### For Bulk Vesting (9 Categories):
```
Owner → EarnsToken → Escrow → BulkVesting → Users
                     (set via set_contract4)
```

### For Staking:
```
User Stakes EARN → Staking Contract → Mints stEARN
                   (owns StEarnToken after transfer_ownership)
```

### For Individual Vesting (Tipping):
```
Creator Deposits EARN → Vesting Contract
User Tips with stEARN → Vesting Contract → Staking Contract
                        (linked via set_contract3)
```

---

## 🔍 How to Verify Configuration

After deployment, you can verify the configuration:

### Check EarnsToken configuration:
```bash
# Check contract4 (Escrow)
starkli call $EARNS_ADDR contract4 --rpc $RPC_URL

# Check contract5 (BulkVesting)
starkli call $EARNS_ADDR contract5 --rpc $RPC_URL
```

### Check Escrow configuration:
```bash
# Check contract4 (BulkVesting)
starkli call $ESCROW_ADDR contract4 --rpc $RPC_URL
```

### Check Staking configuration:
```bash
# Check contract3 (Vesting)
starkli call $STAKING_ADDR contract3 --rpc $RPC_URL
```

### Check StEarnToken ownership:
```bash
# Should return Staking contract address
starkli call $STEARN_ADDR owner --rpc $RPC_URL
```

---

## ⚠️ Important Notes

1. **Order Matters**: Functions must be called in this order because:
   - EarnsToken needs addresses of Escrow & BulkVesting
   - Escrow needs address of BulkVesting
   - Staking needs address of Vesting (deployed last)
   - StEarnToken ownership transfer should be last

2. **One-Time Setup**: These functions are typically called once during deployment

3. **Owner Only**: All these functions require owner privileges (only you can call them)

4. **Contract Names**: 
   - "contract3" = arbitrary naming in Staking (means Vesting contract)
   - "contract4" = arbitrary naming (means distribution contracts)
   - "contract5" = arbitrary naming (means BulkVesting in EarnsToken)

---

## 📚 Related Documentation

- **CAIRO_CONTRACTS.md** - Full contract implementation details
- **QUICK_DEPLOY_GUIDE.md** - Step-by-step deployment guide
- **deploy.sh** - Automated deployment script with all function calls

---

## 🔧 Manual Function Calls (If Needed)

If you need to update any configuration manually:

```bash
# Update EarnsToken contracts
starkli invoke $EARNS_ADDR set_contract4 <NEW_ESCROW> <NEW_BULKVESTING> \
  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL

# Update Escrow contract4
starkli invoke $ESCROW_ADDR set_contract4 <NEW_BULKVESTING> \
  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL

# Update Staking contract3
starkli invoke $STAKING_ADDR set_contract3 <NEW_VESTING> \
  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL

# Transfer StEarnToken ownership
starkli invoke $STEARN_ADDR transfer_ownership <NEW_OWNER> \
  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL
```

---

**Last Updated**: October 16, 2025
**Version**: 1.0
**Network**: Starknet Sepolia/Mainnet
