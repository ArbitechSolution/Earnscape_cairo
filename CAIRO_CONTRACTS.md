# Cairo Contracts Documentation

Complete documentation for all Earnscape Cairo smart contracts deployed on Starknet.

**Version**: 1.0.0  
**Cairo Edition**: 2024_07  
**OpenZeppelin**: v0.20.0  
**Total Contracts**: 9

---

## Table of Contents

1. [EarnsToken](#1-earnstoken)
2. [StEarnToken](#2-stearntoken)
3. [Escrow](#3-escrow)
4. [USDCBNBManager](#4-usdcbnbmanager)
5. [USDCMATICManager](#5-usdcmaticmanager)
6. [EarnXDCManager](#6-earnxdcmanager)
7. [EarnscapeBulkVesting](#7-earnscapebulkvesting)
8. [EarnscapeVesting](#8-earnscapevesting)
9. [EarnscapeStaking](#9-earnscapestaking)

---

## 1. EarnsToken

**File**: `src/earns_token.cairo`  
**Type**: ERC20 Token  
**Supply**: 1,000,000,000 EARN (1 billion tokens)

### Overview

The main utility token of the Earnscape ecosystem. Standard ERC20 with additional distribution logic to Contract4 and Contract5.

### Key Features

- **Standard ERC20**: Full compliance with OpenZeppelin ERC20 implementation
- **Fixed Supply**: 1 billion tokens minted at deployment
- **Distribution Logic**: Automatic allocation to Contract4/Contract5
- **Ownable**: Owner can update distribution addresses

### Storage

```cairo
token: ERC20Component::Storage
ownable: OwnableComponent::Storage
contract4: ContractAddress
contract5: ContractAddress
```

### Constructor

```cairo
fn constructor(ref self: ContractState, owner: ContractAddress)
```

**Parameters**:
- `owner`: Contract owner address

**Initializes**:
- Name: "Earns"
- Symbol: "EARN"
- Decimals: 18
- Total Supply: 1,000,000,000 * 10^18

### Functions

#### Owner Functions

**set_contract4(contract4: ContractAddress, contract5: ContractAddress)**
- Sets Contract4 and Contract5 addresses for distribution
- Transfers 50% supply to each contract
- Can only be called once (after addresses are non-zero)
- Access: Owner only

**update_contract4(contract4: ContractAddress)**
- Updates Contract4 address
- Access: Owner only

**update_contract5(contract5: ContractAddress)**
- Updates Contract5 address
- Access: Owner only

#### View Functions

**get_contract4() -> ContractAddress**
- Returns Contract4 address

**get_contract5() -> ContractAddress**
- Returns Contract5 address

#### Standard ERC20 Functions

- `total_supply() -> u256`
- `balance_of(account: ContractAddress) -> u256`
- `transfer(recipient: ContractAddress, amount: u256) -> bool`
- `transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool`
- `approve(spender: ContractAddress, amount: u256) -> bool`
- `allowance(owner: ContractAddress, spender: ContractAddress) -> u256`
- `name() -> ByteArray`
- `symbol() -> ByteArray`
- `decimals() -> u8`

### Events

**ContractAddressesSet**
- `contract4: ContractAddress`
- `contract5: ContractAddress`

### Usage Example

```cairo
// Deploy
let earns_token = EarnsTokenDispatcher { contract_address: EARNS_ADDRESS };

// Set distribution addresses
earns_token.set_contract4(contract4_addr, contract5_addr);

// Transfer tokens
earns_token.transfer(recipient, 1000 * 10^18);
```

---

## 2. StEarnToken

**File**: `src/stearn_token.cairo`  
**Type**: ERC20 Token with Mint/Burn  
**Initial Supply**: 0

### Overview

Staked EARN token representing staked positions in the staking contract. Users receive stEARN when staking EARN tokens.

### Key Features

- **Mintable**: Only staking contract can mint
- **Burnable**: Only staking contract can burn
- **No Initial Supply**: Supply grows with staking
- **1:1 Ratio**: 1 EARN staked = 1 stEARN minted

### Storage

```cairo
token: ERC20Component::Storage
ownable: OwnableComponent::Storage
```

### Constructor

```cairo
fn constructor(ref self: ContractState, owner: ContractAddress)
```

**Parameters**:
- `owner`: Contract owner address

**Initializes**:
- Name: "Staked Earns"
- Symbol: "stEARN"
- Decimals: 18
- Total Supply: 0

### Functions

#### Owner Functions

**mint(recipient: ContractAddress, amount: u256)**
- Mints stEARN tokens
- Access: Owner only (should be staking contract)

**burn(account: ContractAddress, amount: u256)**
- Burns stEARN tokens
- Access: Owner only (should be staking contract)

#### Standard ERC20 Functions

Same as EarnsToken (transfer, approve, etc.)

### Events

Inherits standard ERC20 events (Transfer, Approval)

### Usage Example

```cairo
// Mint stEARN when user stakes
stearn_token.mint(user_address, stake_amount);

// Burn stEARN when user unstakes
stearn_token.burn(user_address, unstake_amount);
```

---

## 3. Escrow

**File**: `src/escrow.cairo`  
**Type**: Token Distribution Contract

### Overview

Manages EARN token distribution and acts as Contract5. Holds tokens and releases them according to vesting schedules or manual withdrawals.

### Key Features

- **Token Holding**: Stores EARN tokens
- **Withdrawal Control**: Owner-controlled releases
- **Vesting Integration**: Works with vesting contracts
- **Treasury Management**: Sends tokens to treasury

### Storage

```cairo
ownable: OwnableComponent::Storage
token: IERC20Dispatcher
contract4: ContractAddress
treasury_wallet: ContractAddress
```

### Constructor

```cairo
fn constructor(
    ref self: ContractState,
    owner: ContractAddress,
    token_address: ContractAddress,
    treasury_wallet: ContractAddress
)
```

**Parameters**:
- `owner`: Contract owner
- `token_address`: EARN token address
- `treasury_wallet`: Treasury wallet address

### Functions

#### Owner Functions

**withdraw_to_contract4(amount: u256)**
- Withdraws tokens to Contract4 (vesting contracts)
- Validates sufficient balance
- Access: Owner only

**withdraw_to_treasury(amount: u256)**
- Withdraws tokens to treasury wallet
- Validates sufficient balance
- Access: Owner only

**set_contract4(contract4: ContractAddress)**
- Updates Contract4 address
- Access: Owner only

**update_treasury_wallet(treasury_wallet: ContractAddress)**
- Updates treasury wallet address
- Access: Owner only

#### View Functions

**get_contract4() -> ContractAddress**
- Returns Contract4 address

**get_treasury_wallet() -> ContractAddress**
- Returns treasury wallet address

**get_escrow_balance() -> u256**
- Returns EARN token balance in escrow

### Events

**TokensWithdrawn**
- `to: ContractAddress`
- `amount: u256`

### Usage Example

```cairo
// Deploy escrow
let escrow = EscrowDispatcher { contract_address: ESCROW_ADDRESS };

// Withdraw to vesting contract
escrow.withdraw_to_contract4(1000000 * 10^18);

// Withdraw to treasury
escrow.withdraw_to_treasury(500000 * 10^18);
```

---

## 4. USDCBNBManager

**File**: `src/usdc_bnb_manager.cairo`  
**Type**: Cross-Chain Manager

### Overview

Manages USDC transactions on BNB Chain. Handles deposits, withdrawals, and cross-chain communication.

### Key Features

- **USDC Management**: Track USDC deposits/withdrawals
- **User Tracking**: Record user transactions
- **Owner Control**: Restricted operations

### Storage

```cairo
ownable: OwnableComponent::Storage
total_usdc_deposited: u256
total_usdc_withdrawn: u256
user_deposits: Map<ContractAddress, u256>
user_withdrawals: Map<ContractAddress, u256>
```

### Constructor

```cairo
fn constructor(ref self: ContractState, owner: ContractAddress)
```

### Functions

#### Owner Functions

**record_usdc_deposit(user: ContractAddress, amount: u256)**
- Records USDC deposit from BNB Chain
- Updates user balance and total
- Access: Owner only

**record_usdc_withdrawal(user: ContractAddress, amount: u256)**
- Records USDC withdrawal to BNB Chain
- Updates user balance and total
- Access: Owner only

#### View Functions

**get_total_usdc_deposited() -> u256**
**get_total_usdc_withdrawn() -> u256**
**get_user_deposit(user: ContractAddress) -> u256**
**get_user_withdrawal(user: ContractAddress) -> u256**

### Events

**USDCDeposited**
- `user: ContractAddress`
- `amount: u256`

**USDCWithdrawn**
- `user: ContractAddress`
- `amount: u256`

---

## 5. USDCMATICManager

**File**: `src/usdc_matic_manager.cairo`  
**Type**: Cross-Chain Manager

### Overview

Manages USDC transactions on Polygon (MATIC) Chain. Identical functionality to USDCBNBManager but for Polygon network.

### Key Features

Same as USDCBNBManager

### Functions

Same as USDCBNBManager (record_usdc_deposit, record_usdc_withdrawal, view functions)

### Events

Same as USDCBNBManager

---

## 6. EarnXDCManager

**File**: `src/earnxdc_manager.cairo`  
**Type**: Cross-Chain Manager

### Overview

Manages EARN token transactions on XDC Network. Handles token bridges and cross-chain operations.

### Storage

```cairo
ownable: OwnableComponent::Storage
earn_token: IERC20Dispatcher
total_earn_locked: u256
total_earn_unlocked: u256
user_locked_earn: Map<ContractAddress, u256>
user_unlocked_earn: Map<ContractAddress, u256>
```

### Constructor

```cairo
fn constructor(
    ref self: ContractState,
    owner: ContractAddress,
    earn_token_address: ContractAddress
)
```

### Functions

#### Owner Functions

**lock_earn(user: ContractAddress, amount: u256)**
- Locks EARN tokens for XDC bridge
- Transfers from user to contract
- Access: Owner only

**unlock_earn(user: ContractAddress, amount: u256)**
- Unlocks EARN tokens from XDC
- Transfers from contract to user
- Access: Owner only

#### View Functions

**get_total_earn_locked() -> u256**
**get_total_earn_unlocked() -> u256**
**get_user_locked_earn(user: ContractAddress) -> u256**
**get_user_unlocked_earn(user: ContractAddress) -> u256**

### Events

**EarnLocked**
- `user: ContractAddress`
- `amount: u256`

**EarnUnlocked**
- `user: ContractAddress`
- `amount: u256`

---

## 7. EarnscapeBulkVesting

**File**: `src/vesting_bulk.cairo`  
**Type**: Bulk Vesting Contract

### Overview

Manages token vesting for 9 different investor/stakeholder categories with time-based release schedules.

### Categories

| ID | Category | Supply | Vesting Duration |
|----|----------|--------|------------------|
| 0 | Seed Investors | 2,500,000 EARN | 300 seconds |
| 1 | Private Investors | 2,500,000 EARN | 300 seconds |
| 2 | KOL Investors | 1,600,000 EARN | 300 seconds |
| 3 | Public Sale | 2,000,000 EARN | 0 (immediate) |
| 4 | Ecosystem Rewards | 201,333,333 EARN | 300 seconds |
| 5 | Airdrops | 50,000,000 EARN | 300 seconds |
| 6 | Development Reserve | 200,000,000 EARN | 300 seconds |
| 7 | Liquidity | 150,000,000 EARN | 0 (immediate) |
| 8 | Team & Advisors | 200,000,000 EARN | 300 seconds |

**Total**: 909,933,333 EARN

### Storage

```cairo
ownable: OwnableComponent::Storage
token: IERC20Dispatcher
contract5: ContractAddress (Escrow)
cliff_period: u64 (0 seconds)
sliced_period: u64 (60 seconds)
category_names: Map<u8, felt252>
category_supply: Map<u8, u256>
category_remaining_supply: Map<u8, u256>
category_vesting_duration: Map<u8, u64>
user_vesting_count: Map<ContractAddress, u32>
vesting_schedule: Map<(ContractAddress, u32), VestingSchedule>
```

### Constructor

```cairo
fn constructor(
    ref self: ContractState,
    contract3_address: ContractAddress,
    contract5_address: ContractAddress,
    token_address: ContractAddress,
    owner: ContractAddress
)
```

### Functions

#### Owner Functions

**add_user_data(category_id: u8, names: Span<felt252>, user_addresses: Span<ContractAddress>, amounts: Span<u256>)**
- Adds users to vesting category
- Creates vesting schedules
- Can withdraw from Contract5 for categories 0,1,2 if supply insufficient
- Access: Owner only

**release_vested_amount(beneficiary: ContractAddress)**
- Releases all vested tokens for beneficiary
- Calculates releasable amount based on time
- Transfers tokens to beneficiary
- Access: Owner only

**release_immediately(category_id: u8, recipient: ContractAddress)**
- Releases entire category supply immediately
- Only for categories 3 (Public) and 7 (Liquidity)
- Access: Owner only

**update_category_supply(category_id: u8, additional_supply: u256)**
- Adds to category's remaining supply
- Access: Owner only

#### View Functions

**calculate_releasable_amount(beneficiary: ContractAddress) -> (u256, u256)**
- Returns (total_releasable, total_remaining)
- Calculates based on vesting schedules

**get_category_details(category_id: u8) -> (felt252, u256, u256, u64)**
- Returns (name, supply, remaining_supply, vesting_duration)

**get_user_vesting_count(beneficiary: ContractAddress) -> u32**
- Returns number of vesting schedules for user

**get_vesting_schedule(beneficiary: ContractAddress, index: u32) -> (...)**
- Returns vesting schedule details

**get_total_amount_vested() -> u256**
- Returns total amount vested across all users

### Events

**UserAdded**
- `category_id: u8`
- `name: felt252`
- `user_address: ContractAddress`
- `amount: u256`

**VestingScheduleCreated**
- `beneficiary: ContractAddress`
- `start: u64`
- `cliff: u64`
- `duration: u64`
- `slice_period_seconds: u64`
- `amount: u256`

**SupplyUpdated**
- `category_id: u8`
- `additional_supply: u256`

**TokensReleasedImmediately**
- `category_id: u8`
- `recipient: ContractAddress`
- `amount: u256`

### Vesting Algorithm

```
Time-based linear vesting:
1. Before cliff: 0 tokens releasable
2. After cliff, during vesting:
   releasable = (total_amount * time_elapsed) / vesting_duration
3. After vesting duration: full amount releasable

Slice period: Vesting calculated in 60-second intervals
```

---

## 8. EarnscapeVesting

**File**: `src/vesting.cairo`  
**Type**: Individual Vesting with Tipping

### Overview

Manages individual vesting schedules with category-based durations and tipping system. Integrates with staking contract.

### Key Features

- **5 Vesting Categories**: V1-V5 with different durations
- **Tipping System**: Users can tip each other with platform fees
- **Staking Integration**: Tracks EARN and stEARN balances
- **Tax System**: Applies tax on releases based on staking level

### Vesting Durations by Level

| Level | Duration (seconds) | Duration (minutes) |
|-------|-------------------|-------------------|
| V1 | 2400 | 40 minutes |
| V2 | 2057 | ~34 minutes |
| V3 | 1800 | 30 minutes |
| V4 | 1600 | ~27 minutes |
| V5 | 1440 | 24 minutes |

### Storage

```cairo
ownable: OwnableComponent::Storage
token: IERC20Dispatcher
stearn_token: IStEarnDispatcher
staking_contract: ContractAddress
contract3_address: ContractAddress
merchandise_admin_wallet: ContractAddress
fee_recipient: ContractAddress
platform_fee_pct: u256 (2% = 200 basis points)
cliff_period: u64 (0 seconds)
sliced_period: u64 (60 seconds)
user_vesting_count: Map<ContractAddress, u32>
vesting_schedules: Map<(ContractAddress, u32), VestingSchedule>
earn_balance: Map<ContractAddress, u256>
stearn_balance: Map<ContractAddress, u256>
total_tips_sent: Map<ContractAddress, u256>
total_tips_received: Map<ContractAddress, u256>
```

### Constructor

```cairo
fn constructor(
    ref self: ContractState,
    owner: ContractAddress,
    token_address: ContractAddress,
    stearn_token_address: ContractAddress,
    staking_contract_address: ContractAddress,
    contract3_address: ContractAddress,
    fee_recipient: ContractAddress,
    merchandise_admin_wallet: ContractAddress
)
```

### Functions

#### Public Functions

**deposit_earn(beneficiary: ContractAddress, amount: u256)**
- Deposits EARN tokens for vesting
- Determines vesting duration from staking level
- Creates vesting schedule
- Transfers tokens from caller

**give_a_tip(receiver: ContractAddress, tip_amount: u256)**
- Send tip to another user
- Deducts platform fee (2%)
- Creates vesting schedule for receiver
- Updates tip tracking

**release_vested_amount(beneficiary: ContractAddress)**
- Releases vested tokens
- Applies tax based on staking level (0-45%)
- Transfers net amount to user
- Access: Owner only

#### Owner Functions

**set_fee_recipient(recipient: ContractAddress)**
- Updates fee recipient address

**set_platform_fee_pct(pct: u256)**
- Updates platform fee percentage (in basis points)

**update_merchandise_admin_wallet(wallet: ContractAddress)**
- Updates merchandise admin wallet

**update_contract3(contract3: ContractAddress)**
- Updates Contract3 address

**update_staking_contract(staking_contract: ContractAddress)**
- Updates staking contract address

**update_earn_balance(user: ContractAddress, amount: u256)**
- Updates user's EARN balance (called by staking contract)

**update_stearn_balance(user: ContractAddress, amount: u256)**
- Updates user's stEARN balance (called by staking contract)

#### View Functions

**calculate_releasable_amount(beneficiary: ContractAddress) -> (u256, u256)**
- Returns (total_releasable, total_remaining)

**get_vesting_schedule(beneficiary: ContractAddress, index: u32) -> (...)**
- Returns vesting schedule details

**get_user_vesting_count(beneficiary: ContractAddress) -> u32**
- Returns vesting count

**get_earn_balance(beneficiary: ContractAddress) -> u256**
- Returns EARN balance

**get_stearn_balance(beneficiary: ContractAddress) -> u256**
- Returns stEARN balance

**get_tips_sent(user: ContractAddress) -> u256**
- Returns total tips sent

**get_tips_received(user: ContractAddress) -> u256**
- Returns total tips received

### Events

**TokensLocked**
- `user: ContractAddress`
- `amount: u256`

**VestingScheduleCreated**
- `beneficiary: ContractAddress`
- `start: u64`
- `cliff: u64`
- `duration: u64`
- `slice_period_seconds: u64`
- `amount: u256`
- `category: u8`

**TipGiven**
- `sender: ContractAddress`
- `receiver: ContractAddress`
- `gross_amount: u256`
- `net_amount: u256`
- `fee: u256`

**PlatformFeeTaken**
- `from_user: ContractAddress`
- `to_user: ContractAddress`
- `tip_amount: u256`
- `fee: u256`

**TokensReleasedImmediately**
- `beneficiary: ContractAddress`
- `amount: u256`

### Vesting Duration Logic

```cairo
Level determination (from staking contract):
- V1: 2400 seconds (longest vesting)
- V2: 2057 seconds
- V3: 1800 seconds
- V4: 1600 seconds
- V5: 1440 seconds (shortest vesting)

Tax calculation (from staking contract):
- No staking: 45% tax
- Level 1: 38% tax
- Level 2: 28% tax
- Level 3: 18% tax
- Level 4: 8% tax
- Level 5: 0% tax (no tax)
```

### Tipping Flow

```
1. User calls give_a_tip(receiver, 1000 EARN)
2. Platform fee calculated: 1000 * 2% = 20 EARN
3. Net amount: 1000 - 20 = 980 EARN
4. Transfers 1000 from sender
5. Creates vesting schedule for receiver with 980 EARN
6. Sends 20 EARN fee to fee_recipient
7. Updates tip tracking for both users
```

---

## 9. EarnscapeStaking

**File**: `src/staking.cairo`  
**Type**: Multi-Category Staking

### Overview

Advanced staking contract with 6 categories (T.R.A.V.E.L), 5 levels per category, dual token support (EARN/stEARN), and sophisticated tax system.

### Categories

| ID | Name | Description |
|----|------|-------------|
| 0 | T | Travel Category |
| 1 | R | Rewards Category |
| 2 | A | Advantage Category (special perks) |
| 3 | V | Vesting Category |
| 4 | E | Ecosystem Category |
| 5 | L | Loyalty Category |

### Levels

Each category has 5 levels (1-5) with increasing benefits:
- Level 1: Base benefits
- Level 2: Enhanced benefits
- Level 3: Premium benefits
- Level 4: VIP benefits
- Level 5: Maximum benefits (no tax)

### Storage

```cairo
ownable: OwnableComponent::Storage
reentrancy_guard: ReentrancyGuardComponent::Storage
earn_token: IERC20Dispatcher
stearn_token: IStEarnDispatcher
vesting_contract: ContractAddress
user_category: Map<ContractAddress, u8>
user_level: Map<ContractAddress, u8>
user_staked_earn: Map<ContractAddress, u256>
user_staked_stearn: Map<ContractAddress, u256>
total_staked_earn: u256
total_staked_stearn: u256
```

### Constructor

```cairo
fn constructor(
    ref self: ContractState,
    owner: ContractAddress,
    earn_token_address: ContractAddress,
    stearn_token_address: ContractAddress,
    vesting_contract_address: ContractAddress
)
```

### Functions

#### Public Functions

**stake(category: u8, level: u8, earn_amount: u256, stearn_amount: u256)**
- Stakes EARN and/or stEARN tokens
- Sets user's category and level
- Validates category (0-5) and level (1-5)
- Reentrancy protected

**unstake(earn_amount: u256, stearn_amount: u256)**
- Unstakes tokens with mixed-rate tax
- Tax rate depends on staked amounts ratio
- Updates vesting contract balances
- Reentrancy protected

**reshuffle(new_category: u8, new_level: u8)**
- Changes category/level
- Applies 25% tax on all staked tokens
- Tax sent to owner
- Cannot reshuffle within same category
- Reentrancy protected

#### View Functions

**get_user_category(user: ContractAddress) -> u8**
- Returns user's category

**get_user_level(user: ContractAddress) -> u8**
- Returns user's level

**get_user_staked_earn(user: ContractAddress) -> u256**
- Returns EARN staked amount

**get_user_staked_stearn(user: ContractAddress) -> u256**
- Returns stEARN staked amount

**get_total_staked_earn() -> u256**
- Returns total EARN staked

**get_total_staked_stearn() -> u256**
- Returns total stEARN staked

**calculate_release_tax(user: ContractAddress) -> u256**
- Returns tax percentage (0-45)
- Based on category and level

**get_vesting_duration(user: ContractAddress) -> u64**
- Returns vesting duration for user
- Based on category V level

#### Owner Functions

**update_vesting_contract(vesting_contract: ContractAddress)**
- Updates vesting contract address

### Events

**Staked**
- `user: ContractAddress`
- `category: u8`
- `level: u8`
- `earn_amount: u256`
- `stearn_amount: u256`

**Unstaked**
- `user: ContractAddress`
- `earn_amount: u256`
- `stearn_amount: u256`
- `tax_amount: u256`

**Reshuffled**
- `user: ContractAddress`
- `old_category: u8`
- `new_category: u8`
- `old_level: u8`
- `new_level: u8`
- `tax_amount: u256`

### Tax System

#### Release Tax (for vesting releases)

| Category | Level 1 | Level 2 | Level 3 | Level 4 | Level 5 |
|----------|---------|---------|---------|---------|---------|
| T | 38% | 28% | 18% | 8% | 0% |
| R | 38% | 28% | 18% | 8% | 0% |
| A | 45% | 38% | 28% | 18% | 2.5% |
| V | 38% | 28% | 18% | 8% | 0% |
| E | 38% | 28% | 18% | 8% | 0% |
| L | 38% | 28% | 18% | 8% | 0% |

**Special Note**: Category A (Advantage) has different tax rates with minimum 2.5% at level 5.

#### Unstake Tax (mixed-rate)

When unstaking, tax is calculated based on the ratio of EARN to stEARN:

```cairo
// If user has 100 EARN and 100 stEARN staked (1:1 ratio)
// And unstakes 50 EARN and 50 stEARN
// Tax applied: (release_tax * 50%) + (0 * 50%)
// Because stEARN has 0% tax on unstake
```

Formula:
```
mixed_tax = (earn_unstake * release_tax + stearn_unstake * 0) / total_unstake
```

#### Reshuffle Tax

- Fixed 25% tax on all staked tokens when changing category
- Tax sent to contract owner

### Category A Special Perks

Category A provides reduced tax rates:
- Level 1: 45% → Still high
- Level 2: 38% → Better than other categories at L1
- Level 3: 28% → Same as other categories at L2
- Level 4: 18% → Same as other categories at L3
- Level 5: 2.5% → Much better than 0%

### Reentrancy Protection

All state-changing functions use ReentrancyGuard:
```cairo
#[abi(embed_v0)]
impl ReentrancyGuardImpl = ReentrancyGuardComponent::ReentrancyGuardImpl<ContractState>;
```

This prevents:
- Recursive calls during stake/unstake
- Cross-function reentrancy attacks
- Flash loan attacks

---

## Contract Interactions

### Deployment Order

1. **EarnsToken** - Main token
2. **StEarnToken** - Staking token
3. **Escrow** - Token holder (needs EARN address)
4. **USDCBNBManager** - Cross-chain manager
5. **USDCMATICManager** - Cross-chain manager
6. **EarnXDCManager** - Cross-chain manager (needs EARN address)
7. **EarnscapeStaking** - Staking (needs EARN, stEARN addresses)
8. **EarnscapeVesting** - Vesting (needs EARN, stEARN, Staking addresses)
9. **EarnscapeBulkVesting** - Bulk vesting (needs EARN, Escrow addresses)

### Integration Flow

```
EarnsToken
    ├─> Escrow (holds 50% supply)
    ├─> EarnXDCManager (locks/unlocks EARN)
    ├─> EarnscapeStaking (stakes EARN)
    └─> EarnscapeVesting (vests EARN)

StEarnToken
    ├─> EarnscapeStaking (mints/burns stEARN)
    └─> EarnscapeVesting (tracks stEARN balance)

Escrow
    └─> EarnscapeBulkVesting (withdraws tokens for vesting)

EarnscapeStaking
    ├─> EarnscapeVesting (provides level/tax info)
    └─> StEarnToken (mints/burns)

EarnscapeVesting
    ├─> EarnscapeStaking (queries level/category)
    ├─> EarnscapeStaking (updates balances)
    └─> StEarnToken (burns when needed)

EarnscapeBulkVesting
    └─> Escrow (withdraws additional tokens)
```

### Post-Deployment Setup

1. **EarnsToken**: Call `set_contract4()` to distribute supply
2. **StEarnToken**: Transfer ownership to Staking contract
3. **EarnscapeStaking**: Set vesting contract address
4. **EarnscapeVesting**: Set all addresses (staking, stEARN, etc.)
5. **EarnscapeBulkVesting**: Add users to categories

---

## Development Guidelines

### Testing

```bash
# Build all contracts
scarb build

# Run tests (when implemented)
scarb test
```

### Common Patterns

#### Checking Zero Address

```cairo
use core::num::traits::Zero;

assert(!address.is_zero(), 'Address cannot be zero');
```

#### Safe Math (Built-in)

Cairo has built-in overflow protection. No need for SafeMath libraries.

#### Storage Access

```cairo
// Reading
let value = self.storage_var.read();

// Writing
self.storage_var.write(new_value);

// Maps
let balance = self.balances.entry(user).read();
self.balances.entry(user).write(amount);
```

#### Events

```cairo
self.emit(EventName {
    field1: value1,
    field2: value2,
});
```

### Security Considerations

1. **Reentrancy**: Use ReentrancyGuard for critical functions
2. **Access Control**: Use Ownable for admin functions
3. **Zero Checks**: Always validate addresses
4. **Integer Overflow**: Built-in protection in Cairo
5. **Front-running**: Consider transaction ordering
6. **Flash Loans**: Reentrancy guard helps prevent

---

## Troubleshooting

### Build Errors

**"Type not found"**: Check imports and OpenZeppelin version
**"Storage conflict"**: Ensure unique storage variable names
**"Component error"**: Verify component initialization

### Runtime Errors

**"Insufficient balance"**: Check token balances before operations
**"Only owner"**: Ensure caller is contract owner
**"Reentrancy detected"**: Don't call guarded functions recursively

---

## Resources

- **Starknet Docs**: https://docs.starknet.io/
- **Cairo Book**: https://book.cairo-lang.org/
- **OpenZeppelin Cairo**: https://docs.openzeppelin.com/contracts-cairo/
- **Starknet Explorer**: https://starkscan.co/

---

**Last Updated**: October 16, 2025  
**Maintainer**: Earnscape Development Team  
**License**: MIT
