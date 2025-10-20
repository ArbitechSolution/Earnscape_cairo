#[starknet::contract]
mod EarnscapeStaking {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess
    };
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Reentrancy guard pattern
    const NOT_ENTERED: u8 = 0;
    const ENTERED: u8 = 1;

    // Constants
    const DEFAULT_TAX: u256 = 5000; // 50%
    const RESHUFFLE_TAX_DEFAULT: u256 = 2500; // 25%
    const MAX_LEVEL: u8 = 5;

    // Interface for Vesting Contract
    #[starknet::interface]
    trait IEarnscapeVesting<TContractState> {
        fn update_earn_balance(ref self: TContractState, user: ContractAddress, amount: u256);
        fn get_earn_balance(self: @TContractState, beneficiary: ContractAddress) -> u256;
        fn update_stearn_balance(ref self: TContractState, user: ContractAddress, amount: u256);
        fn get_stearn_balance(self: @TContractState, beneficiary: ContractAddress) -> u256;
        fn stearn_transfer(ref self: TContractState, sender: ContractAddress, amount: u256);
        fn calculate_releasable_amount(
            self: @TContractState, beneficiary: ContractAddress
        ) -> (u256, u256);
    }

    // Interface for stEARN token
    #[starknet::interface]
    trait IStEarn<TContractState> {
        fn burn(ref self: TContractState, user: ContractAddress, amount: u256);
        fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct UserCategoryData {
        level: u256,
        staked_amount: u256,
        staked_token: ContractAddress,
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        // Reentrancy guard
        reentrancy_status: u8,
        // Contract addresses
        earn_token: IERC20Dispatcher,
        stearn_token: IERC20Dispatcher,
        stearn_contract: ContractAddress,
        vesting_contract: ContractAddress,
        earnStarkManager: ContractAddress,
        // User data for EARN staking (user => category => data)
        user_levels: Map::<(ContractAddress, felt252), u256>,
        user_staked_amounts: Map::<(ContractAddress, felt252), u256>,
        user_staked_tokens: Map::<(ContractAddress, felt252), ContractAddress>,
        user_categories_count: Map::<ContractAddress, u32>,
        user_categories: Map::<(ContractAddress, u32), felt252>, // (user, index) => category
        // User data for stEARN staking
        stearn_user_levels: Map::<(ContractAddress, felt252), u256>,
        stearn_user_staked_amounts: Map::<(ContractAddress, felt252), u256>,
        stearn_user_staked_tokens: Map::<(ContractAddress, felt252), ContractAddress>,
        stearn_user_categories_count: Map::<ContractAddress, u32>,
        stearn_user_categories: Map::<(ContractAddress, u32), felt252>,
        // Level costs per category
        level_costs: Map::<(felt252, u8), u256>, // (category, level) => cost
        // Staking status
        is_staked_with_stearn: Map::<(ContractAddress, ContractAddress), bool>,
        is_staked_with_earn: Map::<(ContractAddress, ContractAddress), bool>,
        stearn_staked_amount: Map::<(ContractAddress, ContractAddress), u256>,
        earn_staked_amount: Map::<(ContractAddress, ContractAddress), u256>,
        user_pending_stearn_tax: Map::<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        Staked: Staked,
        Unstaked: Unstaked,
        Reshuffled: Reshuffled,
        LevelCostsUpdated: LevelCostsUpdated,
        TransferredAllTokens: TransferredAllTokens,
    }

    #[derive(Drop, starknet::Event)]
    struct Staked {
        #[key]
        user: ContractAddress,
        amount: u256,
        category: felt252,
        level: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Unstaked {
        #[key]
        user: ContractAddress,
        amount: u256,
        tax_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Reshuffled {
        #[key]
        user: ContractAddress,
        amount: u256,
        tax_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LevelCostsUpdated {
        category: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferredAllTokens {
        #[key]
        new_contract: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        earn_token: ContractAddress,
        stearn_token: ContractAddress,
        earnStarkManager: ContractAddress
    ) {
        self.ownable.initializer(owner);
        self.reentrancy_status.write(NOT_ENTERED);
        self.earn_token.write(IERC20Dispatcher { contract_address: earn_token });
        self.stearn_token.write(IERC20Dispatcher { contract_address: stearn_token });
        self.stearn_contract.write(stearn_token);
        self.earnStarkManager.write(earnStarkManager);
        self._set_default_level_costs();
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _non_reentrant_before(ref self: ContractState) {
            assert(self.reentrancy_status.read() != ENTERED, 'ReentrancyGuard: reentrant call');
            self.reentrancy_status.write(ENTERED);
        }

        fn _non_reentrant_after(ref self: ContractState) {
            self.reentrancy_status.write(NOT_ENTERED);
        }

        fn _set_default_level_costs(ref self: ContractState) {
            let categories: Array<felt252> = array!['T', 'R', 'A', 'V', 'E', 'L'];
            let costs: Array<u256> = array![
                100000000000000000000, // Level 1: 100 tokens * 10^18
                200000000000000000000, // Level 2: 200 tokens
                400000000000000000000, // Level 3: 400 tokens
                800000000000000000000, // Level 4: 800 tokens
                1600000000000000000000 // Level 5: 1600 tokens
            ];

            let mut cat_idx: u32 = 0;
            while cat_idx < 6 {
                let category = *categories.at(cat_idx);

                let mut level: u8 = 1;
                while level <= MAX_LEVEL {
                    let cost = *costs.at((level - 1).into());
                    self.level_costs.entry((category, level)).write(cost);
                    level += 1;
                };

                cat_idx += 1;
            };
        }

        fn _is_valid_category(self: @ContractState, category: felt252) -> bool {
            category == 'T'
                || category == 'R'
                || category == 'A'
                || category == 'V'
                || category == 'E'
                || category == 'L'
        }

        fn _category_exists(
            self: @ContractState, user: ContractAddress, category: felt252
        ) -> bool {
            let count = self.user_categories_count.entry(user).read();
            let mut i: u32 = 0;
            while i < count {
                if self.user_categories.entry((user, i)).read() == category {
                    return true;
                }
                i += 1;
            };
            false
        }

        fn _stearn_category_exists(
            self: @ContractState, user: ContractAddress, category: felt252
        ) -> bool {
            let count = self.stearn_user_categories_count.entry(user).read();
            let mut i: u32 = 0;
            while i < count {
                if self.stearn_user_categories.entry((user, i)).read() == category {
                    return true;
                }
                i += 1;
            };
            false
        }

        fn _get_perk_for_level(self: @ContractState, level: u256) -> u256 {
            if level == 1 {
                4500 // 45.00%
            } else if level == 2 {
                4000 // 40.00%
            } else if level == 3 {
                3250 // 32.50%
            } else if level == 4 {
                1500 // 15.00%
            } else if level == 5 {
                250 // 2.50%
            } else {
                0
            }
        }

        fn _calculate_tax(self: @ContractState, amount: u256, tax_rate: u256) -> u256 {
            (amount * tax_rate) / 10000
        }

        fn _detect_mixed_rate(self: @ContractState, user: ContractAddress) -> (bool, u256) {
            let count = self.user_categories_count.entry(user).read();
            let mut has_a = false;
            let mut has_other = false;

            let mut i: u32 = 0;
            while i < count {
                let category = self.user_categories.entry((user, i)).read();
                let staked = self.user_staked_amounts.entry((user, category)).read();

                if staked > 0 {
                    if category == 'A' {
                        has_a = true;
                    } else {
                        has_other = true;
                    }
                }
                i += 1;
            };

            let mixed = has_a && has_other;
            if mixed {
                let lvl_a = self.user_levels.entry((user, 'A')).read();
                let mixed_rate = self._get_perk_for_level(lvl_a);
                (true, mixed_rate)
            } else {
                (false, 0)
            }
        }

        fn _detect_mixed_rate_stearn(
            self: @ContractState, user: ContractAddress
        ) -> (bool, u256) {
            let count = self.stearn_user_categories_count.entry(user).read();
            let mut has_a = false;
            let mut has_other = false;

            let mut i: u32 = 0;
            while i < count {
                let category = self.stearn_user_categories.entry((user, i)).read();
                let staked = self.stearn_user_staked_amounts.entry((user, category)).read();

                if staked > 0 {
                    if category == 'A' {
                        has_a = true;
                    } else {
                        has_other = true;
                    }
                }
                i += 1;
            };

            let mixed = has_a && has_other;
            if mixed {
                let lvl_a = self.stearn_user_levels.entry((user, 'A')).read();
                let mixed_rate = self._get_perk_for_level(lvl_a);
                (true, mixed_rate)
            } else {
                (false, 0)
            }
        }

        fn _reset_user_data(ref self: ContractState, user: ContractAddress) {
            let count = self.user_categories_count.entry(user).read();

            let mut i: u32 = 0;
            while i < count {
                let category = self.user_categories.entry((user, i)).read();
                self.user_levels.entry((user, category)).write(0);
                self.user_staked_amounts.entry((user, category)).write(0);
                i += 1;
            };

            self.user_categories_count.entry(user).write(0);
        }

        fn _reset_stearn_user_data(ref self: ContractState, user: ContractAddress) {
            let count = self.stearn_user_categories_count.entry(user).read();

            let mut i: u32 = 0;
            while i < count {
                let category = self.stearn_user_categories.entry((user, i)).read();
                self.stearn_user_levels.entry((user, category)).write(0);
                self.stearn_user_staked_amounts.entry((user, category)).write(0);
                i += 1;
            };

            self.stearn_user_categories_count.entry(user).write(0);
        }

        fn _adjust_stearn_balance(ref self: ContractState, user: ContractAddress) {
            let vesting = IEarnscapeVestingDispatcher {
                contract_address: self.vesting_contract.read()
            };
            let (_, locked) = vesting.calculate_releasable_amount(user);
            let stearn_balance = vesting.get_stearn_balance(user);

            if stearn_balance > locked {
                let excess = stearn_balance - locked;
                vesting.update_stearn_balance(user, locked);
                let stearn = IStEarnDispatcher { contract_address: self.stearn_contract.read() };
                stearn.burn(self.vesting_contract.read(), excess);
            }
        }
    }


    #[abi(embed_v0)]
    impl EarnscapeStakingImpl of super::IEarnscapeStaking<ContractState> {
        fn stake(ref self: ContractState, category: felt252, levels: Span<u256>) {
            self._non_reentrant_before();

            assert(self._is_valid_category(category), 'Invalid category');
            let caller = get_caller_address();

            let earn_token = self.earn_token.read();
            let stearn_contract = self.stearn_contract.read();
            
            let earn_balance = earn_token.balance_of(caller);
            let stearn_balance = IERC20Dispatcher { contract_address: stearn_contract }
                .balance_of(caller);

            let use_stearn = stearn_balance > 0;

            let mut total_required: u256 = 0;
            let mut i: u32 = 0;

            while i < levels.len() {
                let level_u256 = *levels.at(i);
                assert(level_u256 > 0 && level_u256 <= MAX_LEVEL.into(), 'Invalid level');

                let level: u8 = level_u256.try_into().unwrap();
                let required_amount = self.level_costs.entry((category, level)).read();
                total_required += required_amount;

                i += 1;
            };

            if use_stearn {
                assert(stearn_balance >= total_required, 'Insufficient stEARN balance');

                // Set level and staked amount
                let final_level = *levels.at(levels.len() - 1);
                self.stearn_user_levels.entry((caller, category)).write(final_level);

                let current_staked = self.stearn_user_staked_amounts.entry((caller, category)).read();
                self
                    .stearn_user_staked_amounts
                    .entry((caller, category))
                    .write(current_staked + total_required);
                self.stearn_user_staked_tokens.entry((caller, category)).write(stearn_contract);

                // Add category if not exists
                if !self._stearn_category_exists(caller, category) {
                    let count = self.stearn_user_categories_count.entry(caller).read();
                    self.stearn_user_categories.entry((caller, count)).write(category);
                    self.stearn_user_categories_count.entry(caller).write(count + 1);
                }

                let earn_disp = IERC20Dispatcher { contract_address: stearn_contract };
                earn_disp.transfer_from(caller, get_contract_address(), total_required);

                self.is_staked_with_stearn.entry((caller, stearn_contract)).write(true);
                let current_total = self.stearn_staked_amount.entry((caller, stearn_contract)).read();
                self
                    .stearn_staked_amount
                    .entry((caller, stearn_contract))
                    .write(current_total + total_required);
            } else {
                assert(earn_balance >= total_required, 'Insufficient EARN balance');

                // Set level and staked amount
                let final_level = *levels.at(levels.len() - 1);
                self.user_levels.entry((caller, category)).write(final_level);

                let current_staked = self.user_staked_amounts.entry((caller, category)).read();
                self
                    .user_staked_amounts
                    .entry((caller, category))
                    .write(current_staked + total_required);
                self.user_staked_tokens.entry((caller, category)).write(earn_token.contract_address);

                // Add category if not exists
                if !self._category_exists(caller, category) {
                    let count = self.user_categories_count.entry(caller).read();
                    self.user_categories.entry((caller, count)).write(category);
                    self.user_categories_count.entry(caller).write(count + 1);
                }

                earn_token.transfer_from(caller, get_contract_address(), total_required);

                self.is_staked_with_earn.entry((caller, earn_token.contract_address)).write(true);
                let current_total = self
                    .earn_staked_amount
                    .entry((caller, earn_token.contract_address))
                    .read();
                self
                    .earn_staked_amount
                    .entry((caller, earn_token.contract_address))
                    .write(current_total + total_required);
            }

            let final_level = *levels.at(levels.len() - 1);
            self.emit(Staked { user: caller, amount: total_required, category: category, level: final_level });

            self._non_reentrant_after();
        }

        fn unstake(ref self: ContractState) {
            self._non_reentrant_before();

            let caller = get_caller_address();
            let mut total_amount: u256 = 0;
            let mut total_tax: u256 = 0;

            let (mixed, mixed_rate) = self._detect_mixed_rate(caller);

            // Process EARN staking
            let count = self.user_categories_count.entry(caller).read();
            let mut i: u32 = 0;

            while i < count {
                let category = self.user_categories.entry((caller, i)).read();
                let staked = self.user_staked_amounts.entry((caller, category)).read();

                if staked > 0 {
                    let tax = if mixed {
                        self._calculate_tax(staked, mixed_rate)
                    } else if category == 'A' {
                        let level = self.user_levels.entry((caller, category)).read();
                        let perk = self._get_perk_for_level(level);
                        self._calculate_tax(staked, perk)
                    } else {
                        self._calculate_tax(staked, DEFAULT_TAX)
                    };

                    total_amount += staked;
                    total_tax += tax;
                }

                i += 1;
            };

            if total_amount > 0 {
                let earn_token = self.earn_token.read();
                let net_amount = total_amount - total_tax;

                self.earn_staked_amount.entry((caller, earn_token.contract_address)).write(0);
                self.is_staked_with_earn.entry((caller, earn_token.contract_address)).write(false);

                earn_token.transfer(self.earnStarkManager.read(), total_tax);
                earn_token.transfer(caller, net_amount);
            }

            self._reset_user_data(caller);
            self.emit(Unstaked { user: caller, amount: total_amount, tax_amount: total_tax });

            self._non_reentrant_after();
        }

        fn reshuffle(ref self: ContractState) {
            self._non_reentrant_before();

            let caller = get_caller_address();
            let mut total_amount: u256 = 0;
            let mut total_tax: u256 = 0;

            let (mixed, mixed_rate) = self._detect_mixed_rate(caller);

            // Process EARN staking with reshuffle tax
            let count = self.user_categories_count.entry(caller).read();
            let mut i: u32 = 0;

            while i < count {
                let category = self.user_categories.entry((caller, i)).read();
                let staked = self.user_staked_amounts.entry((caller, category)).read();

                if staked > 0 {
                    let tax = if mixed {
                        self._calculate_tax(staked, mixed_rate / 2) // Half for reshuffle
                    } else if category == 'A' {
                        let level = self.user_levels.entry((caller, category)).read();
                        let perk = self._get_perk_for_level(level);
                        self._calculate_tax(staked, perk / 2) // Half for reshuffle
                    } else {
                        self._calculate_tax(staked, RESHUFFLE_TAX_DEFAULT)
                    };

                    total_amount += staked;
                    total_tax += tax;
                }

                i += 1;
            };

            if total_amount > 0 {
                let earn_token = self.earn_token.read();
                let net_amount = total_amount - total_tax;

                self.earn_staked_amount.entry((caller, earn_token.contract_address)).write(0);
                self.is_staked_with_earn.entry((caller, earn_token.contract_address)).write(false);

                earn_token.transfer(self.earnStarkManager.read(), total_tax);
                earn_token.transfer(caller, net_amount);
            }

            self._reset_user_data(caller);
            self.emit(Reshuffled { user: caller, amount: total_amount, tax_amount: total_tax });

            self._non_reentrant_after();
        }

        fn set_level_costs(ref self: ContractState, category: felt252, costs: Span<u256>) {
            self.ownable.assert_only_owner();
            assert(self._is_valid_category(category), 'Invalid category');
            assert(costs.len() == MAX_LEVEL.into(), 'Must provide 5 costs');

            let mut level: u8 = 1;
            let mut i: u32 = 0;
            while level <= MAX_LEVEL {
                let cost = *costs.at(i);
                self.level_costs.entry((category, level)).write(cost);
                level += 1;
                i += 1;
            };

            self.emit(LevelCostsUpdated { category: category });
        }

        fn set_earnStarkManager(ref self: ContractState, new_contract: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(new_contract.into() != 0, 'Invalid contract address');
            self.earnStarkManager.write(new_contract);
        }

        fn set_vesting_contract(ref self: ContractState, contract: ContractAddress) {
            self.ownable.assert_only_owner();
            self.vesting_contract.write(contract);
        }

        fn set_stearn_contract(ref self: ContractState, contract: ContractAddress) {
            self.ownable.assert_only_owner();
            self.stearn_contract.write(contract);
        }

        fn transfer_all_tokens(ref self: ContractState, new_contract: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(new_contract.into() != 0, 'Invalid address');

            let earn_token = self.earn_token.read();
            let balance = earn_token.balance_of(get_contract_address());
            earn_token.transfer(new_contract, balance);

            self.emit(TransferredAllTokens { new_contract: new_contract });
        }

        fn get_user_data(
            self: @ContractState, user: ContractAddress
        ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>) {
            let count = self.user_categories_count.entry(user).read();

            let mut categories: Array<felt252> = ArrayTrait::new();
            let mut levels: Array<u256> = ArrayTrait::new();
            let mut staked_amounts: Array<u256> = ArrayTrait::new();
            let mut staked_tokens: Array<ContractAddress> = ArrayTrait::new();

            let mut i: u32 = 0;
            while i < count {
                let category = self.user_categories.entry((user, i)).read();
                categories.append(category);
                levels.append(self.user_levels.entry((user, category)).read());
                staked_amounts.append(self.user_staked_amounts.entry((user, category)).read());
                staked_tokens.append(self.user_staked_tokens.entry((user, category)).read());
                i += 1;
            };

            (categories, levels, staked_amounts, staked_tokens)
        }

        fn get_user_stearn_data(
            self: @ContractState, user: ContractAddress
        ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>) {
            let count = self.stearn_user_categories_count.entry(user).read();

            let mut categories: Array<felt252> = ArrayTrait::new();
            let mut levels: Array<u256> = ArrayTrait::new();
            let mut staked_amounts: Array<u256> = ArrayTrait::new();
            let mut staked_tokens: Array<ContractAddress> = ArrayTrait::new();

            let mut i: u32 = 0;
            while i < count {
                let category = self.stearn_user_categories.entry((user, i)).read();
                categories.append(category);
                levels.append(self.stearn_user_levels.entry((user, category)).read());
                staked_amounts.append(self.stearn_user_staked_amounts.entry((user, category)).read());
                staked_tokens.append(self.stearn_user_staked_tokens.entry((user, category)).read());
                i += 1;
            };

            (categories, levels, staked_amounts, staked_tokens)
        }

        fn read_level(self: @ContractState, user: ContractAddress, category: felt252) -> u256 {
            self.user_levels.entry((user, category)).read()
        }

        fn get_level_cost(self: @ContractState, category: felt252, level: u8) -> u256 {
            self.level_costs.entry((category, level)).read()
        }

        fn check_is_staked_with_earn(
            self: @ContractState, user: ContractAddress, token: ContractAddress
        ) -> bool {
            self.is_staked_with_earn.entry((user, token)).read()
        }

        fn check_is_staked_with_stearn(
            self: @ContractState, user: ContractAddress, token: ContractAddress
        ) -> bool {
            self.is_staked_with_stearn.entry((user, token)).read()
        }

        fn get_earn_staked_amount(
            self: @ContractState, user: ContractAddress, token: ContractAddress
        ) -> u256 {
            self.earn_staked_amount.entry((user, token)).read()
        }

        fn get_stearn_staked_amount(
            self: @ContractState, user: ContractAddress, token: ContractAddress
        ) -> u256 {
            self.stearn_staked_amount.entry((user, token)).read()
        }

        fn get_user_pending_stearn_tax(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_pending_stearn_tax.entry(user).read()
        }

        // Get all level costs for a category (returns array of 5 costs)
        fn get_level_costs(self: @ContractState, category: felt252) -> Array<u256> {
            let mut costs: Array<u256> = ArrayTrait::new();
            let mut level: u8 = 1;
            while level <= MAX_LEVEL {
                costs.append(self.level_costs.entry((category, level)).read());
                level += 1;
            };
            costs
        }

        // Calculate user's stearn tax before unstaking
        fn calculate_user_stearn_tax(self: @ContractState, user: ContractAddress) -> (u256, u256) {
            // Detect mixed rate
            let (mixed, mixed_rate) = self._detect_mixed_rate_stearn(user);
            
            let mut total_tax_amount: u256 = 0;
            let mut total_staked_amount: u256 = 0;
            
            let count = self.stearn_user_categories_count.entry(user).read();
            let stearn_contract_addr = self.stearn_contract.read();
            let mut i: u32 = 0;
            
            while i < count {
                let category = self.stearn_user_categories.entry((user, i)).read();
                let staked_amount = self.stearn_user_staked_amounts.entry((user, category)).read();
                let staked_token = self.stearn_user_staked_tokens.entry((user, category)).read();
                
                // Only tax what was staked via stEarn
                if staked_token != stearn_contract_addr {
                    i += 1;
                    continue;
                }
                
                if staked_amount == 0 {
                    i += 1;
                    continue;
                }
                
                let tax_amount = if mixed {
                    // Apply mixed rate
                    self._calculate_tax(staked_amount, mixed_rate)
                } else if category == 'A' {
                    // Apply A category perk
                    let level = self.stearn_user_levels.entry((user, category)).read();
                    let perk = self._get_perk_for_level(level);
                    self._calculate_tax(staked_amount, perk)
                } else {
                    // Default tax
                    self._calculate_tax(staked_amount, DEFAULT_TAX)
                };
                
                total_tax_amount += tax_amount;
                total_staked_amount += staked_amount;
                
                i += 1;
            };
            
            (total_tax_amount, total_staked_amount)
        }

        // Update user pending stearn tax (only callable by vesting contract)
        fn update_user_pending_stearn_tax(ref self: ContractState, user: ContractAddress, new_tax_amount: u256) {
            let caller = get_caller_address();
            assert(caller == self.vesting_contract.read(), 'Only vesting contract');
            self.user_pending_stearn_tax.entry(user).write(new_tax_amount);
        }

        // Getter for earn_token address
        fn earn_token(self: @ContractState) -> ContractAddress {
            self.earn_token.read().contract_address
        }

        // Getter for stearn_token address
        fn stearn_token(self: @ContractState) -> ContractAddress {
            self.stearn_token.read().contract_address
        }

        // Getter for stearn_contract address
        fn stearn_contract(self: @ContractState) -> ContractAddress {
            self.stearn_contract.read()
        }

        // Getter for vesting_contract address
        fn vesting_contract(self: @ContractState) -> ContractAddress {
            self.vesting_contract.read()
        }

        // Getter for earnStarkManager (EarnStarkManager) address
        fn earnStarkManager(self: @ContractState) -> ContractAddress {
            self.earnStarkManager.read()
        }
    }
}

#[starknet::interface]
trait IEarnscapeStaking<TContractState> {
    // Write functions
    fn stake(ref self: TContractState, category: felt252, levels: Span<u256>);
    fn unstake(ref self: TContractState);
    fn reshuffle(ref self: TContractState);
    fn set_level_costs(ref self: TContractState, category: felt252, costs: Span<u256>);
    fn set_earnStarkManager(ref self: TContractState, new_contract: starknet::ContractAddress);
    fn set_vesting_contract(ref self: TContractState, contract: starknet::ContractAddress);
    fn set_stearn_contract(ref self: TContractState, contract: starknet::ContractAddress);
    fn transfer_all_tokens(ref self: TContractState, new_contract: starknet::ContractAddress);
    fn update_user_pending_stearn_tax(
        ref self: TContractState,
        user: starknet::ContractAddress,
        new_tax_amount: u256
    );
    
    // Read functions - User data
    fn get_user_data(
        self: @TContractState, user: starknet::ContractAddress
    ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<starknet::ContractAddress>);
    fn get_user_stearn_data(
        self: @TContractState, user: starknet::ContractAddress
    ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<starknet::ContractAddress>);
    fn read_level(self: @TContractState, user: starknet::ContractAddress, category: felt252) -> u256;
    
    // Read functions - Level costs
    fn get_level_cost(self: @TContractState, category: felt252, level: u8) -> u256;
    fn get_level_costs(self: @TContractState, category: felt252) -> Array<u256>;
    
    // Read functions - Staking status
    fn check_is_staked_with_earn(
        self: @TContractState, user: starknet::ContractAddress, token: starknet::ContractAddress
    ) -> bool;
    fn check_is_staked_with_stearn(
        self: @TContractState, user: starknet::ContractAddress, token: starknet::ContractAddress
    ) -> bool;
    fn get_earn_staked_amount(
        self: @TContractState, user: starknet::ContractAddress, token: starknet::ContractAddress
    ) -> u256;
    fn get_stearn_staked_amount(
        self: @TContractState, user: starknet::ContractAddress, token: starknet::ContractAddress
    ) -> u256;
    fn get_user_pending_stearn_tax(self: @TContractState, user: starknet::ContractAddress) -> u256;
    fn calculate_user_stearn_tax(self: @TContractState, user: starknet::ContractAddress) -> (u256, u256);
    
    // Read functions - Contract addresses
    fn earn_token(self: @TContractState) -> starknet::ContractAddress;
    fn stearn_token(self: @TContractState) -> starknet::ContractAddress;
    fn stearn_contract(self: @TContractState) -> starknet::ContractAddress;
    fn vesting_contract(self: @TContractState) -> starknet::ContractAddress;
    fn earnStarkManager(self: @TContractState) -> starknet::ContractAddress;
}
