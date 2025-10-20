# Edge Cases & Testing Guide
## Comprehensive Test Scenarios for EarnScape Contracts

**Date:** October 20, 2025  
**Purpose:** Document all edge cases and testing scenarios to ensure production readiness

---

## 🎯 CRITICAL EDGE CASES TO TEST

### 1. VESTING CONTRACT - Tip Functionality

#### Scenario A: Tip with Insufficient Funds
```
Test: User tries to tip more than wallet + vesting balance
Expected: Transaction reverts with "Insufficient total funds"
Cairo Code: assert(wallet_avail + vesting_avail >= tip_amount, 'Insufficient total funds');
```

#### Scenario B: Merchandise Wallet Fee Skip
```
Test: Tip to merchandiseAdminWallet should have 0% fee
Given: platformFeePct = 40, receiver = merchandiseAdminWallet
Expected: feeAmount = 0, full tip goes to receiver
Cairo Code: let is_merch = receiver == merch_wallet; let fee_pct = if is_merch { 0 } else { ... };
```

#### Scenario C: Mixed Wallet + Vesting Tip
```
Test: Tip 1000 when wallet has 300 and vesting has 800
Given: tipAmount = 1000, walletAvail = 300, vestingAvail = 800, fee = 40%
Expected:
  - Wallet fee: 300 * 0.4 = 120 → feeRecipient
  - Wallet net: 300 - 120 = 180 → receiver
  - Vesting fee: 400 - 120 = 280 → feeRecipient vesting
  - Vesting net: 1000 - 300 - 400 = 300 → receiver vesting
```

#### Scenario D: Vesting After Tip - Duration Recalculation
```
Test: User has vesting schedule ending in 10 days, tips 50% of locked amount
Given:
  - Schedule: start=day 0, duration=10 days, amountTotal=1000, released=0
  - Current day: 5 (50% unlocked)
  - Tip deduction: 300 from locked portion
Expected:
  - New schedule: start=day 5, duration=5 days (recalculated), amountTotal=released+700
  - Duration preserved from original end date
```

#### Scenario E: Multiple Schedules Tip Deduction
```
Test: User has 3 schedules, tip deducts across multiple
Given:
  - Schedule 1: 100 locked
  - Schedule 2: 200 locked
  - Schedule 3: 300 locked
  - Tip deduction: 450
Expected:
  - Schedule 1: fully consumed (amountTotal = released)
  - Schedule 2: fully consumed
  - Schedule 3: partial deduction (250 remaining)
```

---

### 2. VESTING CONTRACT - Release with Tax

#### Scenario F: Release with Pending Tax
```
Test: User has 1000 releasable, 200 tax, 100 staked
Given:
  - Releasable: 1000
  - Tax: 200
  - Total staked (st): 100
Expected:
  - Tax deducted from locked vesting: 200
  - Net payout: (1000 - 100) = 900
  - Tax transferred to earnStarkManager
  - Pending tax cleared on staking contract
```

#### Scenario G: No Claimable After Tax
```
Test: User has releasable <= totalStaked (all locked in stEARN)
Given: releasable = 500, totalStaked = 600
Expected: Transaction reverts with "No claimable amount available after tax deduction"
```

#### Scenario H: Schedule Compression During Release
```
Test: Release fully empties some schedules, should compress array
Given: User has 5 schedules, releasing empties schedule 1 and 3
Expected:
  - Schedules shifted down (no gaps)
  - holdersVestingCount decremented by 2
  - Last 2 array positions deleted
```

---

### 3. VESTING CONTRACT - stEARN Balance Adjustment

#### Scenario I: Excess stEARN Burn
```
Test: User has more stEARN than locked vesting
Given:
  - stEARN balance: 1000
  - Locked vesting: 700
Expected:
  - Excess: 300
  - Burn 300 stEARN from contract
  - Update user's stearnBalance to 700
```

#### Scenario J: Admin Instant Release
```
Test: merchandiseAdminWallet releases all vesting immediately
Given:
  - 3 schedules with total 5000 tokens
  - Some partially released, some locked
Expected:
  - All schedules summed
  - All marked as fully released
  - State wiped: count=0, Earnbalance=0, stearnBalance=0
  - Full amount transferred
```

---

### 4. STAKING CONTRACT - Level Requirements

#### Scenario K: Upgrade Multiple Levels
```
Test: User upgrades from level 1 to level 3 in one transaction
Given: category="V", levels=[3] (target level 3)
Expected:
  - Calculate cumulative cost: level1 + level2 + level3
  - Total required = sum of all levels up to 3
  - User level set to 3
  - Staked amount updated
```

#### Scenario L: stEARN Staking with Excess Burn
```
Test: User stakes with stEARN, has more than required
Given:
  - Required: 1000 stEARN
  - User has: 1200 stEARN in vesting contract
Expected:
  - Transfer 1000 from vesting to contract
  - Burn excess 200
  - Update level
```

#### Scenario M: Category Tracking
```
Test: User stakes in category not yet tracked
Given: User's first time staking in category "A"
Expected:
  - user_categories_count incremented
  - Category "A" added to user_categories map
  - Level and staked amount recorded
```

---

### 5. STAKING CONTRACT - Unstake

#### Scenario N: Unstake with Multiple Categories
```
Test: User has staked in 3 categories (A, B, V)
Given:
  - Category A: 500 staked
  - Category B: 300 staked
  - Category V: 200 staked
  - Total: 1000
  - Tax: 50% = 500
Expected:
  - Net payout: 500
  - Tax: 500 to contract3
  - All categories cleared
  - user_categories_count = 0
```

#### Scenario O: Unstake with stEARN
```
Test: User has both EARN and stEARN staking
Given:
  - EARN staking: 800
  - stEARN staking: 200
  - User has 150 stEARN in vesting, 50 excess
Expected:
  - Clear EARN categories
  - Clear stEARN categories
  - Burn 50 excess stEARN
  - Calculate tax on total
```

---

### 6. BULK VESTING CONTRACT

#### Scenario P: Add User Exceeding Supply
```
Test: Add user with amount exceeding remaining supply
Given:
  - Category remaining: 500
  - User amount: 800
Expected:
  - Withdraw 300 from escrow
  - Update category supply
  - Create vesting schedule
  - Update remaining supply
```

#### Scenario Q: Immediate Release Category
```
Test: Release tokens from category with 0 duration (Public Sale)
Given: categoryId = 3 (Public Sale), duration = 0
Expected:
  - All tokens immediately releasable
  - No cliff period
  - Transfer on first release call
```

---

### 7. EARN TOKEN - Finalize

#### Scenario R: Finalize with Zero Unsold
```
Test: All tokens sold (soldSupply = TOTAL_SUPPLY)
Given: soldSupply = 1,000,000,000 * 10^18
Expected:
  - Unsold = 0, no transfer to escrow
  - All tokens to bulkVesting
  - Ownership renounced
```

#### Scenario S: Finalize with Zero Sold
```
Test: No tokens sold (soldSupply = 0)
Given: soldSupply = 0
Expected:
  - All tokens to escrow
  - No transfer to bulkVesting
  - Ownership renounced
```

---

### 8. ESCROW CONTRACT

#### Scenario T: Withdraw to Bulk Vesting - Not Authorized
```
Test: Non-bulkVesting address tries to withdraw
Given: caller != contract4 (bulkVesting)
Expected: Transaction reverts with "Only Contract 4"
```

#### Scenario U: Transfer All Edge Case
```
Test: Transfer all when balance is very small (dust)
Given: balance = 1 wei
Expected: Successfully transfer 1 wei to treasury
```

---

### 9. EARNXDC MANAGER

#### Scenario V: Deposit to Vesting - Two-Step Process
```
Test: earnDepositToVesting transfers then calls depositEarn
Given: amount = 1000 EARNS
Expected:
  1. Transfer 1000 EARNS from manager to vesting contract
  2. Call vesting.depositEarn(receiver, 1000)
  3. Vesting mints 1000 stEARN
  4. Vesting creates schedule
```

---

### 10. stEARN TOKEN - Transfer Restrictions

#### Scenario W: User-to-User Transfer Blocked
```
Test: User tries to transfer stEARN to another user
Given: sender = userA, recipient = userB
Expected: Transaction reverts with "Transfers only allowed to vesting, stakingContract, or burn address"
```

#### Scenario X: Allowed Transfers
```
Test: User transfers stEARN to allowed addresses
Given: vesting_contract = 0x123, staking_contract = 0x456
Expected:
  - user → vesting_contract: ✅ Allowed
  - user → staking_contract: ✅ Allowed
  - user → 0x0 (burn): ✅ Allowed
  - contract → any: ✅ Allowed (minting)
```

---

## 🧪 INTEGRATION TEST SCENARIOS

### Integration Test 1: Full User Journey
```
1. Deploy all contracts
2. User deposits EARNS to EarnXDCManager
3. Manager calls vesting.depositEarn
4. Vesting mints stEARN to itself
5. Vesting creates schedule based on user's staking level
6. User stakes in category V, level 3
7. User tips another user (mixed wallet + vesting)
8. Time passes, some vesting unlocks
9. User releases vested amount with tax deduction
10. User unstakes
11. Final balance checks
```

### Integration Test 2: Admin Flow
```
1. Deploy contracts
2. Add users to bulk vesting categories
3. Some users in immediate release category
4. Some users in vested categories
5. Time passes
6. Users release vested amounts
7. Admin (merchandise wallet) receives tips
8. Admin releases immediately (no vesting)
9. Escrow transfers remaining to treasury
```

### Integration Test 3: Edge Case Combinations
```
1. User has multiple vesting schedules
2. User stakes with stEARN
3. User tips using both wallet and vesting
4. Tip causes schedule compression
5. User upgrades staking level
6. User unstakes (burns excess stEARN)
7. User releases with tax
```

---

## 🔍 SECURITY TEST SCENARIOS

### Security Test 1: Reentrancy Attack Simulation
```
Attempt: Malicious contract tries to reenter stake() during callback
Expected: Reentrancy guard prevents reentry, transaction reverts
```

### Security Test 2: Integer Overflow
```
Attempt: Try to cause overflow in balance calculations
Expected: Cairo's built-in checks prevent overflow, transaction safe
```

### Security Test 3: Access Control Bypass
```
Attempt: Non-owner tries to call admin functions
Expected: All revert with appropriate error messages
```

### Security Test 4: Token Drainage
```
Attempt: Try to withdraw more tokens than available
Expected: Balance checks prevent over-withdrawal
```

---

## 📊 PERFORMANCE TEST SCENARIOS

### Performance Test 1: Many Vesting Schedules
```
Scenario: User has 50 vesting schedules
Operations:
  - Calculate releasable amount
  - Release vested amount
  - Give tip (updates all schedules)
Expected: Operations complete within gas limits
```

### Performance Test 2: Large Batch Operations
```
Scenario: Add 100 users to bulk vesting in sequence
Expected: All operations succeed, state properly tracked
```

---

## ✅ TESTING CHECKLIST

### Unit Tests (Per Contract)
- [ ] All public functions
- [ ] All view functions
- [ ] All modifiers/access control
- [ ] All events emitted
- [ ] All error cases

### Integration Tests
- [ ] Cross-contract calls
- [ ] Token transfers between contracts
- [ ] Vesting schedule creation and release
- [ ] Staking and unstaking flows
- [ ] Tipping flows

### Edge Case Tests
- [ ] All scenarios listed above (A-X)
- [ ] Boundary conditions (0, max values)
- [ ] Time-based vesting edge cases
- [ ] Array operations edge cases

### Security Tests
- [ ] Reentrancy protection
- [ ] Access control
- [ ] Integer safety
- [ ] Token drainage prevention

### Gas/Performance Tests
- [ ] Large data structure operations
- [ ] Batch operations
- [ ] Complex calculation functions

---

## 🎯 RECOMMENDED TESTING TOOLS

### For Cairo/Starknet:
1. **Starknet Foundry** - Testing framework for Cairo
2. **Protostar** - Testing and deployment tool
3. **Cairo-test** - Built-in testing
4. **Starknet-devnet** - Local testnet for development

### Testing Steps:
```bash
# 1. Set up local devnet
starknet-devnet --port 5050

# 2. Run unit tests
scarb test

# 3. Deploy to devnet
starkli deploy --network devnet

# 4. Run integration tests with scripts

# 5. Deploy to Sepolia testnet for final testing
starkli deploy --network sepolia
```

---

## 📝 TEST RESULT DOCUMENTATION

For each test, document:
1. ✅ Test Name
2. ✅ Expected Behavior
3. ✅ Actual Result
4. ✅ Gas Used (if applicable)
5. ✅ Pass/Fail Status
6. ✅ Notes/Observations

---

## 🚀 PRODUCTION READINESS CRITERIA

### Before Mainnet Deployment:
- [ ] All unit tests passing (100% coverage)
- [ ] All integration tests passing
- [ ] All edge cases tested and documented
- [ ] Security audit completed
- [ ] Gas optimization reviewed
- [ ] Deployment scripts tested on testnet
- [ ] Documentation complete
- [ ] Emergency pause mechanisms tested (if applicable)
- [ ] Upgrade/migration paths defined (if applicable)

---

**Document Version:** 1.0  
**Last Updated:** October 20, 2025  
**Status:** Ready for Testing Phase

