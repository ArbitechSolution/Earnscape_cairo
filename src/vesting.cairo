#[starknet::contract]
mod Vesting {
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use starknet::storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::array::ArrayTrait;
    use core::num::traits::Zero;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Interface for stEARN token
    #[starknet::interface]
    trait IStEarn<TContractState> {
        fn burn(ref self: TContractState, user: ContractAddress, amount: u256);
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
        fn transfer(ref self: TContractState, to: ContractAddress, amount: u256) -> bool;
    }

    // Interface for Staking Contract
    #[starknet::interface]
    trait IEarnscapeStaking<TContractState> {
        fn get_user_data(self: @TContractState, user: ContractAddress) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>);
        fn get_user_stearn_data(self: @TContractState, user: ContractAddress) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>);
        fn get_user_pending_stearn_tax(self: @TContractState, user: ContractAddress) -> u256;
        fn calculate_user_stearn_tax(self: @TContractState, user: ContractAddress) -> (u256, u256);
        fn update_user_pending_stearn_tax(ref self: TContractState, user: ContractAddress, new_tax_amount: u256);
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        token: IERC20Dispatcher,
        stearn_token: ContractAddress,
        earnStarkManager: ContractAddress,
        staking_contract: ContractAddress,
        total_amount_vested: u256,
        cliff_period: u64,
        sliced_period: u64,
        // user balances
        earn_balance: Map::<ContractAddress, u256>,
        stearn_balance: Map::<ContractAddress, u256>,
        // vesting schedules
        user_vesting_count: Map::<ContractAddress, u32>,
        vesting_beneficiary: Map::<(ContractAddress, u32), ContractAddress>,
        vesting_cliff: Map::<(ContractAddress, u32), u64>,
        vesting_start: Map::<(ContractAddress, u32), u64>,
        vesting_duration: Map::<(ContractAddress, u32), u64>,
        vesting_slice_period: Map::<(ContractAddress, u32), u64>,
        vesting_amount_total: Map::<(ContractAddress, u32), u256>,
        vesting_released: Map::<(ContractAddress, u32), u256>,
        // configuration
        earn_stark_manager: ContractAddress,
        fee_recipient: ContractAddress,
        merchandise_admin_wallet: ContractAddress,
        default_vesting_time: u64,
        platform_fee_pct: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        TokensLocked: TokensLocked,
        PendingEarnDueToStearnUnstake: PendingEarnDueToStearnUnstake,
        TipGiven: TipGiven,
        PlatformFeeTaken: PlatformFeeTaken,
        VestingScheduleCreated: VestingScheduleCreated,
        TokensReleasedImmediately: TokensReleasedImmediately,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensLocked { #[key] beneficiary: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct PendingEarnDueToStearnUnstake { #[key] user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct TipGiven { #[key] giver: ContractAddress, #[key] receiver: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct PlatformFeeTaken { #[key] from: ContractAddress, #[key] to: ContractAddress, feeAmount: u256 }

    #[derive(Drop, starknet::Event)]
    struct VestingScheduleCreated { #[key] beneficiary: ContractAddress, start: u64, cliff: u64, duration: u64, slice_period_seconds: u64, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct TokensReleasedImmediately { #[key] category_id: u8, #[key] recipient: ContractAddress, amount: u256 }

    #[constructor]
    fn constructor(ref self: ContractState, token_address: ContractAddress, stearn_address: ContractAddress, earn_stark_manager: ContractAddress, staking_contract: ContractAddress, owner: ContractAddress) {
        self.ownable.initializer(owner);
        self.token.write(IERC20Dispatcher { contract_address: token_address });
        self.stearn_token.write(stearn_address);
        self.earn_stark_manager.write(earn_stark_manager);
        self.staking_contract.write(staking_contract);
        self.default_vesting_time.write(2880 * 60); // 2880 minutes in seconds
        self.platform_fee_pct.write(40);
        self.fee_recipient.write(owner);
        self.merchandise_admin_wallet.write(owner);
        self.cliff_period.write(0);
        self.sliced_period.write(60); // 60 seconds = 1 minute for testing
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _create_vesting_schedule(
            ref self: ContractState,
            beneficiary: ContractAddress,
            start: u64,
            cliff: u64,
            duration: u64,
            slice_period_seconds: u64,
            amount: u256
        ) {
            assert(duration >= cliff, 'Duration must be >= cliff');
            let cliff_time = start + cliff;
            let current_index = self.user_vesting_count.entry(beneficiary).read();
            self.vesting_beneficiary.entry((beneficiary, current_index)).write(beneficiary);
            self.vesting_cliff.entry((beneficiary, current_index)).write(cliff_time);
            self.vesting_start.entry((beneficiary, current_index)).write(start);
            self.vesting_duration.entry((beneficiary, current_index)).write(duration);
            self.vesting_slice_period.entry((beneficiary, current_index)).write(slice_period_seconds);
            self.vesting_amount_total.entry((beneficiary, current_index)).write(amount);
            self.vesting_released.entry((beneficiary, current_index)).write(0);
            self.user_vesting_count.entry(beneficiary).write(current_index + 1);
            self.total_amount_vested.write(self.total_amount_vested.read() + amount);
            self.emit(VestingScheduleCreated { beneficiary, start, cliff, duration, slice_period_seconds, amount });
        }

        fn _compute_releasable_amount(ref self: ContractState, beneficiary: ContractAddress, index: u32) -> (u256, u256) {
            let current_time = get_block_timestamp();
            let cliff = self.vesting_cliff.entry((beneficiary, index)).read();
            let start = self.vesting_start.entry((beneficiary, index)).read();
            let duration = self.vesting_duration.entry((beneficiary, index)).read();
            let amount_total = self.vesting_amount_total.entry((beneficiary, index)).read();
            let released = self.vesting_released.entry((beneficiary, index)).read();
            if current_time < cliff {
                return (0, amount_total - released);
            }
            if current_time >= start + duration {
                let releasable = amount_total - released;
                return (releasable, 0);
            }
            let time_from_start = current_time - start;
            let slice_period = self.vesting_slice_period.entry((beneficiary, index)).read();
            let vested_slice_periods = time_from_start / slice_period;
            let vested_seconds = vested_slice_periods * slice_period;
            let total_vested = (amount_total * vested_seconds.into()) / duration.into();
            let releasable = total_vested - released;
            let remaining = amount_total - total_vested;
            (releasable, remaining)
        }

        // _adjust_stearn_balance - burn excess stEARN
        fn _adjust_stearn_balance(ref self: ContractState, user: ContractAddress) {
            let (_, locked) = self._calculate_releasable_sum(user);
            let stearn_bal = self.stearn_balance.entry(user).read();
            
            if stearn_bal > locked {
                let excess = stearn_bal - locked;
                self.stearn_balance.entry(user).write(locked);
                let stearn_addr = self.stearn_token.read();
                let stearn = IStEarnDispatcher { contract_address: stearn_addr };
                let contract_addr = get_contract_address();
                stearn.burn(contract_addr, excess);
            }
        }

        // Helper to calculate total releasable/locked
        fn _calculate_releasable_sum(ref self: ContractState, user: ContractAddress) -> (u256, u256) {
            let vesting_count = self.user_vesting_count.entry(user).read();
            let mut total_releasable: u256 = 0;
            let mut total_remaining: u256 = 0;
            let mut i: u32 = 0;
            while i < vesting_count {
                let (releasable, remaining) = self._compute_releasable_amount(user, i);
                total_releasable += releasable;
                total_remaining += remaining;
                i += 1;
            };
            (total_releasable, total_remaining)
        }

        // _update_vesting_after_tip - adjust vesting schedules after tip deduction
        fn _update_vesting_after_tip(ref self: ContractState, user: ContractAddress, tip_deduction: u256) {
            let mut remaining_deduction = tip_deduction;
            let vesting_count = self.user_vesting_count.entry(user).read();
            let mut i: u32 = 0;
            
            while i < vesting_count && remaining_deduction > 0 {
                let amt_total = self.vesting_amount_total.entry((user, i)).read();
                let released = self.vesting_released.entry((user, i)).read();
                let effective_balance = amt_total - released;
                
                if effective_balance == 0 {
                    i += 1;
                    continue;
                }
                
                if remaining_deduction >= effective_balance {
                    remaining_deduction -= effective_balance;
                    self.vesting_amount_total.entry((user, i)).write(released);
                } else {
                    let leftover = effective_balance - remaining_deduction;
                    let start = self.vesting_start.entry((user, i)).read();
                    let duration = self.vesting_duration.entry((user, i)).read();
                    let original_end = start + duration;
                    let now = get_block_timestamp();
                    let new_duration = if original_end > now { original_end - now } else { 0 };
                    
                    self.vesting_start.entry((user, i)).write(now);
                    self.vesting_cliff.entry((user, i)).write(0);
                    self.vesting_duration.entry((user, i)).write(new_duration);
                    self.vesting_amount_total.entry((user, i)).write(released + leftover);
                    self.vesting_released.entry((user, i)).write(0);
                    remaining_deduction = 0;
                }
                i += 1;
            };
        }

        // _process_net_tip_vesting - handle vesting-based net tip transfer
        fn _process_net_tip_vesting(
            ref self: ContractState,
            sender: ContractAddress,
            receiver: ContractAddress,
            vesting_net: u256,
            total_releasable: u256,
            total_remaining: u256
        ) {
            let sender_stearn = self.stearn_balance.entry(sender).read();
            self.stearn_balance.entry(sender).write(sender_stearn - vesting_net);
            
            let sender_earn = self.earn_balance.entry(sender).read();
            self.earn_balance.entry(sender).write(sender_earn - vesting_net);
            
            let receiver_stearn = self.stearn_balance.entry(receiver).read();
            self.stearn_balance.entry(receiver).write(receiver_stearn + vesting_net);
            
            let receiver_earn = self.earn_balance.entry(receiver).read();
            self.earn_balance.entry(receiver).write(receiver_earn + vesting_net);
            
            self._update_vesting_after_tip(sender, vesting_net);
            
            let releasable_receiver = if vesting_net <= total_releasable { vesting_net } else { total_releasable };
            let locked_receiver = vesting_net - releasable_receiver;
            assert(locked_receiver <= total_remaining, 'Exceeds available vesting');

            let now = get_block_timestamp();
            
            if releasable_receiver > 0 {
                self._create_vesting_schedule(receiver, now, 0, 0, 0, releasable_receiver);
            }
            
            if locked_receiver > 0 {
                let merch = self.merchandise_admin_wallet.read();
                let fee_recip = self.fee_recipient.read();
                let vesting_duration = if receiver == merch || receiver == fee_recip {
                    0
                } else {
                    let (_, duration) = self._preview_vesting_params_internal(receiver);
                    duration
                };
                
                let cliff = self.cliff_period.read();
                let slice = self.sliced_period.read();
                self._create_vesting_schedule(receiver, now, cliff, vesting_duration, slice, locked_receiver);
            }
        }

        // Internal preview vesting params helper
        fn _preview_vesting_params_internal(self: @ContractState, beneficiary: ContractAddress) -> (u64, u64) {
            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            let (categories, levels, _, _) = staking.get_user_data(beneficiary);

            let mut vesting_duration = self.default_vesting_time.read();
            let category_v: felt252 = 'V';
            let mut i: u32 = 0;

            while i < categories.len() {
                if *categories.at(i) == category_v {
                    let level = *levels.at(i);
                    if level == 1 {
                        vesting_duration = 144000;
                    } else if level == 2 {
                        vesting_duration = 123420;
                    } else if level == 3 {
                        vesting_duration = 108000;
                    } else if level == 4 {
                        vesting_duration = 96000;
                    } else if level == 5 {
                        vesting_duration = 86400;
                    }
                    break;
                }
                i += 1;
            };

            let start = get_block_timestamp();
            (start, vesting_duration)
        }
    }

    #[abi(embed_v0)]
    impl VestingImpl of super::IVesting<ContractState> {
        // Admin setters
        fn update_earnStarkManager(ref self: ContractState, earnStarkManager: ContractAddress) {
            self.ownable.assert_only_owner();
            self.earnStarkManager.write(earnStarkManager);
        }

        fn update_staking_contract(ref self: ContractState, staking_contract: ContractAddress) {
            self.ownable.assert_only_owner();
            self.staking_contract.write(staking_contract);
        }

        // Read balances
        fn get_earn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            self.earn_balance.entry(beneficiary).read()
        }

        fn update_earn_balance(ref self: ContractState, user: ContractAddress, amount: u256) {
            let staking = self.staking_contract.read();
            assert(get_caller_address() == staking, 'Only staking contract');
            self.earn_balance.entry(user).write(amount);
        }

        fn get_stearn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            self.stearn_balance.entry(beneficiary).read()
        }

        fn update_stearn_balance(ref self: ContractState, user: ContractAddress, amount: u256) {
            let staking = self.staking_contract.read();
            assert(get_caller_address() == staking, 'Only staking contract');
            self.stearn_balance.entry(user).write(amount);
        }

        // stEARN transfer called by staking to move stEARN out
        fn st_earn_transfer(ref self: ContractState, sender: ContractAddress, amount: u256) {
            let current = self.stearn_balance.entry(sender).read();
            assert(current >= amount, 'Insufficient stEARN balance');
            self.stearn_balance.entry(sender).write(current - amount);
            let stearn_token = self.stearn_token.read();
            IERC20Dispatcher { contract_address: stearn_token }.transfer(get_caller_address(), amount);
        }

        // depositEarn - called by earnStarkManager
        fn deposit_earn(ref self: ContractState, beneficiary: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            let manager = self.earn_stark_manager.read();
            assert(caller == manager, 'Only earnStarkManager');
            assert(amount > 0, 'Amount must be > 0');

            // Determine vestingDuration via staking.getUserData
            let mut vesting_duration = self.default_vesting_time.read();
            let staking_addr = self.staking_contract.read();
            
            // Call staking contract to get user data
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            let (categories, levels, _staked_amounts, _staked_tokens) = staking.get_user_data(beneficiary);
            
            // Check if user is in category 'V' (felt252 value for 'V')
            let mut is_in_category_v = false;
            let category_v: felt252 = 'V';
            let mut i: u32 = 0;
            
            while i < categories.len() {
                if *categories.at(i) == category_v {
                    is_in_category_v = true;
                    let level = *levels.at(i);
                    
                    // Map level to vesting duration (in seconds) - Solidity uses minutes, convert to seconds
                    if level == 1 {
                        vesting_duration = 144000; // 2400 minutes = 144000 seconds
                    } else if level == 2 {
                        vesting_duration = 123420; // 2057 minutes = 123420 seconds
                    } else if level == 3 {
                        vesting_duration = 108000; // 1800 minutes = 108000 seconds
                    } else if level == 4 {
                        vesting_duration = 96000; // 1600 minutes = 96000 seconds
                    } else if level == 5 {
                        vesting_duration = 86400; // 1440 minutes = 86400 seconds
                    }
                    break;
                }
                i += 1;
            };

            // Update internal balances
            let prev_earn = self.earn_balance.entry(beneficiary).read();
            self.earn_balance.entry(beneficiary).write(prev_earn + amount);

            // Mint stEARN to this contract
            let stearn_addr = self.stearn_token.read();
            let stearn = IStEarnDispatcher { contract_address: stearn_addr };
            let contract_addr = get_contract_address();
            stearn.mint(contract_addr, amount);

            // Update stEARN balance for beneficiary
            let prev_stearn = self.stearn_balance.entry(beneficiary).read();
            self.stearn_balance.entry(beneficiary).write(prev_stearn + amount);

            let now = get_block_timestamp();
            let cliff = self.cliff_period.read();
            let slice = self.sliced_period.read();
            
            self._create_vesting_schedule(beneficiary, now, cliff, vesting_duration, slice, amount);
            self.emit(TokensLocked { beneficiary, amount });
        }

        // calculate_releasable_amount - iterate schedules
        fn calculate_releasable_amount(ref self: ContractState, beneficiary: ContractAddress) -> (u256, u256) {
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut total_releasable: u256 = 0;
            let mut total_remaining: u256 = 0;
            let mut i: u32 = 0;
            while i < vesting_count {
                let (releasable, remaining) = self._compute_releasable_amount(beneficiary, i);
                total_releasable += releasable;
                total_remaining += remaining;
                i += 1;
            };
            (total_releasable, total_remaining)
        }

        // release_vested_amount - only owner (staking might call)
        fn release_vested_amount(ref self: ContractState, beneficiary: ContractAddress) {
            self.ownable.assert_only_owner();
            let (releasable, _) = self.calculate_releasable_amount(beneficiary);
            assert(releasable > 0, 'No releasable amount');
            let mut remaining_amount = releasable;
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut i: u32 = 0;
            while i < vesting_count && remaining_amount > 0 {
                let (releasable_amount, _) = self._compute_releasable_amount(beneficiary, i);
                if releasable_amount > 0 {
                    let release_amount = if releasable_amount > remaining_amount { remaining_amount } else { releasable_amount };
                    let current_released = self.vesting_released.entry((beneficiary, i)).read();
                    self.vesting_released.entry((beneficiary, i)).write(current_released + release_amount);
                    remaining_amount -= release_amount;
                    self.token.read().transfer(beneficiary, release_amount);
                }
                i += 1;
            };
        }

        // getters for vesting schedule
        fn get_user_vesting_count(self: @ContractState, beneficiary: ContractAddress) -> u32 {
            self.user_vesting_count.entry(beneficiary).read()
        }

        fn get_vesting_schedule(self: @ContractState, beneficiary: ContractAddress, index: u32) -> (ContractAddress, u64, u64, u64, u64, u256, u256) {
            (
                self.vesting_beneficiary.entry((beneficiary, index)).read(),
                self.vesting_cliff.entry((beneficiary, index)).read(),
                self.vesting_start.entry((beneficiary, index)).read(),
                self.vesting_duration.entry((beneficiary, index)).read(),
                self.vesting_slice_period.entry((beneficiary, index)).read(),
                self.vesting_amount_total.entry((beneficiary, index)).read(),
                self.vesting_released.entry((beneficiary, index)).read()
            )
        }

        // Admin configuration setters
        fn set_fee_recipient(ref self: ContractState, recipient: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!recipient.is_zero(), 'Zero address');
            self.fee_recipient.write(recipient);
        }

        fn set_platform_fee_pct(ref self: ContractState, pct: u64) {
            self.ownable.assert_only_owner();
            assert(pct <= 100, 'Pct>100');
            self.platform_fee_pct.write(pct);
        }

        fn update_merchandise_admin_wallet(ref self: ContractState, merch_wallet: ContractAddress) {
            self.ownable.assert_only_owner();
            self.merchandise_admin_wallet.write(merch_wallet);
        }

        fn update_earn_stark_manager_address(ref self: ContractState, contract_addr: ContractAddress) {
            self.ownable.assert_only_owner();
            self.earn_stark_manager.write(contract_addr);
        }

        // Getters for configuration
        fn get_fee_recipient(self: @ContractState) -> ContractAddress {
            self.fee_recipient.read()
        }

        fn get_platform_fee_pct(self: @ContractState) -> u64 {
            self.platform_fee_pct.read()
        }

        fn get_merchandise_admin_wallet(self: @ContractState) -> ContractAddress {
            self.merchandise_admin_wallet.read()
        }

        fn get_earn_stark_manager(self: @ContractState) -> ContractAddress {
            self.earn_stark_manager.read()
        }

        fn get_default_vesting_time(self: @ContractState) -> u64 {
            self.default_vesting_time.read()
        }

        fn get_total_amount_vested(self: @ContractState) -> u256 {
            self.total_amount_vested.read()
        }

        // giveATip - complex tipping logic with fees
        fn give_a_tip(ref self: ContractState, receiver: ContractAddress, tip_amount: u256) {
            let sender = get_caller_address();
            assert(!receiver.is_zero(), 'Invalid receiver address');

            // Get wallet and vesting balances
            let wallet_avail = self.token.read().balance_of(sender);
            let vesting_avail = self.earn_balance.entry(sender).read();
            assert(wallet_avail + vesting_avail >= tip_amount, 'Insufficient total funds');

            // Skip fees for merchandise wallet
            let merch_wallet = self.merchandise_admin_wallet.read();
            let is_merch = receiver == merch_wallet;
            let fee_pct = if is_merch { 0 } else { self.platform_fee_pct.read() };

            // Calculate current vesting pools
            let (total_releasable, total_remaining) = self.calculate_releasable_amount(sender);
            let fee_amount = (tip_amount * fee_pct.into()) / 100;

            // 2) Wallet-based fee & net
            let wallet_fee = if wallet_avail >= fee_amount { fee_amount } else { wallet_avail };
            if wallet_fee > 0 {
                let fee_recip = self.fee_recipient.read();
                self.token.read().transfer_from(sender, fee_recip, wallet_fee);
            }
            
            let wallet_net = if tip_amount <= wallet_avail { 
                tip_amount - wallet_fee 
            } else { 
                wallet_avail - wallet_fee 
            };
            if wallet_net > 0 {
                self.token.read().transfer_from(sender, receiver, wallet_net);
            }

            // 3) Vesting-based fee
            let vesting_fee = if fee_amount > wallet_fee { fee_amount - wallet_fee } else { 0 };
            let mut adjusted_releasable = total_releasable;
            
            if vesting_fee > 0 {
                assert(vesting_fee <= vesting_avail, 'Insufficient vesting fee');
                
                let sender_stearn_bal = self.stearn_balance.entry(sender).read();
                self.stearn_balance.entry(sender).write(sender_stearn_bal - vesting_fee);
                
                let sender_earn_bal = self.earn_balance.entry(sender).read();
                self.earn_balance.entry(sender).write(sender_earn_bal - vesting_fee);
                
                let fee_recip = self.fee_recipient.read();
                let recip_stearn = self.stearn_balance.entry(fee_recip).read();
                self.stearn_balance.entry(fee_recip).write(recip_stearn + vesting_fee);
                
                let recip_earn = self.earn_balance.entry(fee_recip).read();
                self.earn_balance.entry(fee_recip).write(recip_earn + vesting_fee);
                
                let now = get_block_timestamp();
                self._create_vesting_schedule(fee_recip, now, 0, 0, 0, vesting_fee);
                self._update_vesting_after_tip(sender, vesting_fee);
                
                adjusted_releasable = if total_releasable > vesting_fee { 
                    total_releasable - vesting_fee 
                } else { 
                    0 
                };
            }

            // 4) Vesting-based net tip
            let vesting_net = tip_amount - wallet_fee - wallet_net - vesting_fee;
            if vesting_net > 0 {
                self._process_net_tip_vesting(sender, receiver, vesting_net, adjusted_releasable, total_remaining);
            }

            self.emit(TipGiven { giver: sender, receiver, amount: tip_amount });
        }

        // releaseVestedAmount - with tax deduction logic
        fn release_vested_amount_with_tax(ref self: ContractState, beneficiary: ContractAddress) {
            let (rel, _) = self.calculate_releasable_amount(beneficiary);
            assert(rel > 0, 'No releasable amount');
            
            self._adjust_stearn_balance(beneficiary);

            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            
            let tax = staking.get_user_pending_stearn_tax(beneficiary);
            let (_, st) = staking.calculate_user_stearn_tax(beneficiary);

            // 1) Remove tax from locked vesting
            self._update_vesting_after_tip(beneficiary, tax);
            let ben_earn = self.earn_balance.entry(beneficiary).read();
            self.earn_balance.entry(beneficiary).write(ben_earn - tax);

            // 1b) Pay out tax to manager
            if tax > 0 {
                let manager = self.earn_stark_manager.read();
                self.token.read().transfer(manager, tax);
                staking.update_user_pending_stearn_tax(beneficiary, 0);
            }

            // 2) Compute net payout
            let pay = if rel > st { rel - st } else { 0 };
            assert(pay > 0, 'No claimable after tax');

            // 3) Slice through vesting schedules
            let mut cnt = self.user_vesting_count.entry(beneficiary).read();
            let mut remaining_pay = pay;
            let mut i: u32 = 0;
            
            while i < cnt && remaining_pay > 0 {
                let amt_total = self.vesting_amount_total.entry((beneficiary, i)).read();
                let released = self.vesting_released.entry((beneficiary, i)).read();
                let available = amt_total - released;
                
                if available == 0 {
                    // Compress by moving last schedule to this position
                    if i < cnt - 1 {
                        let last_idx = cnt - 1;
                        self.vesting_beneficiary.entry((beneficiary, i)).write(
                            self.vesting_beneficiary.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_cliff.entry((beneficiary, i)).write(
                            self.vesting_cliff.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_start.entry((beneficiary, i)).write(
                            self.vesting_start.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_duration.entry((beneficiary, i)).write(
                            self.vesting_duration.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_slice_period.entry((beneficiary, i)).write(
                            self.vesting_slice_period.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_amount_total.entry((beneficiary, i)).write(
                            self.vesting_amount_total.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_released.entry((beneficiary, i)).write(
                            self.vesting_released.entry((beneficiary, last_idx)).read()
                        );
                    }
                    cnt -= 1;
                    continue;
                }

                let slice = if remaining_pay < available { remaining_pay } else { available };
                self.vesting_released.entry((beneficiary, i)).write(released + slice);
                
                let ben_earn = self.earn_balance.entry(beneficiary).read();
                self.earn_balance.entry(beneficiary).write(ben_earn - slice);
                
                remaining_pay -= slice;
                self.token.read().transfer(beneficiary, slice);

                let new_released = released + slice;
                if new_released == amt_total {
                    // Compress
                    if i < cnt - 1 {
                        let last_idx = cnt - 1;
                        self.vesting_beneficiary.entry((beneficiary, i)).write(
                            self.vesting_beneficiary.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_cliff.entry((beneficiary, i)).write(
                            self.vesting_cliff.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_start.entry((beneficiary, i)).write(
                            self.vesting_start.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_duration.entry((beneficiary, i)).write(
                            self.vesting_duration.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_slice_period.entry((beneficiary, i)).write(
                            self.vesting_slice_period.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_amount_total.entry((beneficiary, i)).write(
                            self.vesting_amount_total.entry((beneficiary, last_idx)).read()
                        );
                        self.vesting_released.entry((beneficiary, i)).write(
                            self.vesting_released.entry((beneficiary, last_idx)).read()
                        );
                    }
                    cnt -= 1;
                    continue;
                }
                i += 1;
            };

            self.user_vesting_count.entry(beneficiary).write(cnt);
            let released_amt = if rel > st { rel - st } else { 0 };
            self.emit(TokensReleasedImmediately { category_id: 0, recipient: beneficiary, amount: released_amt - tax - remaining_pay });
        }

        // releaseVestedAdmins - instant release for admin wallets
        fn release_vested_admins(ref self: ContractState) {
            let caller = get_caller_address();
            let merch = self.merchandise_admin_wallet.read();
            let fee_recip = self.fee_recipient.read();
            assert(caller == merch || caller == fee_recip, 'Not authorized');

            self._adjust_stearn_balance(caller);

            let vesting_count = self.user_vesting_count.entry(caller).read();
            assert(vesting_count > 0, 'No vesting schedules');

            // Sum all schedules
            let mut total_to_release: u256 = 0;
            let mut i: u32 = 0;
            while i < vesting_count {
                let amt_total = self.vesting_amount_total.entry((caller, i)).read();
                let released = self.vesting_released.entry((caller, i)).read();
                let available = amt_total - released;
                if available > 0 {
                    total_to_release += available;
                    self.vesting_released.entry((caller, i)).write(amt_total);
                }
                i += 1;
            };

            // Wipe state
            self.user_vesting_count.entry(caller).write(0);
            self.earn_balance.entry(caller).write(0);
            self.stearn_balance.entry(caller).write(0);

            assert(total_to_release > 0, 'No vested tokens');
            self.token.read().transfer(caller, total_to_release);

            self.emit(TokensReleasedImmediately { category_id: 0, recipient: caller, amount: total_to_release });
        }

        // preview_vesting_params - preview vesting duration for a user
        fn preview_vesting_params(self: @ContractState, beneficiary: ContractAddress) -> (u64, u64) {
            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            let (categories, levels, _, _) = staking.get_user_data(beneficiary);

            let mut vesting_duration = self.default_vesting_time.read();
            let category_v: felt252 = 'V';
            let mut i: u32 = 0;

            while i < categories.len() {
                if *categories.at(i) == category_v {
                    let level = *levels.at(i);
                    if level == 1 {
                        vesting_duration = 144000; // 2400 minutes
                    } else if level == 2 {
                        vesting_duration = 123420; // 2057 minutes
                    } else if level == 3 {
                        vesting_duration = 108000; // 1800 minutes
                    } else if level == 4 {
                        vesting_duration = 96000; // 1600 minutes
                    } else if level == 5 {
                        vesting_duration = 86400; // 1440 minutes
                    }
                    break;
                }
                i += 1;
            };

            let start = get_block_timestamp();
            (start, vesting_duration)
        }
    }
}

#[starknet::interface]
trait IVesting<TContractState> {
    fn update_earnStarkManager(ref self: TContractState, earnStarkManager: starknet::ContractAddress);
    fn update_staking_contract(ref self: TContractState, staking_contract: starknet::ContractAddress);
    fn get_earn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn update_earn_balance(ref self: TContractState, user: starknet::ContractAddress, amount: u256);
    fn get_stearn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn update_stearn_balance(ref self: TContractState, user: starknet::ContractAddress, amount: u256);
    fn st_earn_transfer(ref self: TContractState, sender: starknet::ContractAddress, amount: u256);
    fn deposit_earn(ref self: TContractState, beneficiary: starknet::ContractAddress, amount: u256);
    fn calculate_releasable_amount(ref self: TContractState, beneficiary: starknet::ContractAddress) -> (u256, u256);
    fn release_vested_amount(ref self: TContractState, beneficiary: starknet::ContractAddress);
    fn get_user_vesting_count(self: @TContractState, beneficiary: starknet::ContractAddress) -> u32;
    fn get_vesting_schedule(self: @TContractState, beneficiary: starknet::ContractAddress, index: u32) -> (starknet::ContractAddress, u64, u64, u64, u64, u256, u256);
    fn set_fee_recipient(ref self: TContractState, recipient: starknet::ContractAddress);
    fn set_platform_fee_pct(ref self: TContractState, pct: u64);
    fn update_merchandise_admin_wallet(ref self: TContractState, merch_wallet: starknet::ContractAddress);
    fn update_earn_stark_manager_address(ref self: TContractState, contract_addr: starknet::ContractAddress);
    fn get_fee_recipient(self: @TContractState) -> starknet::ContractAddress;
    fn get_platform_fee_pct(self: @TContractState) -> u64;
    fn get_merchandise_admin_wallet(self: @TContractState) -> starknet::ContractAddress;
    fn get_earn_stark_manager(self: @TContractState) -> starknet::ContractAddress;
    fn get_default_vesting_time(self: @TContractState) -> u64;
    fn get_total_amount_vested(self: @TContractState) -> u256;
    fn give_a_tip(ref self: TContractState, receiver: starknet::ContractAddress, tip_amount: u256);
    fn release_vested_amount_with_tax(ref self: TContractState, beneficiary: starknet::ContractAddress);
    fn release_vested_admins(ref self: TContractState);
    fn preview_vesting_params(self: @TContractState, beneficiary: starknet::ContractAddress) -> (u64, u64);
}
