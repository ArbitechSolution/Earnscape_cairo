#[starknet::contract]
mod VestingReader {
    use starknet::{ContractAddress, get_block_timestamp};
    use starknet::storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::array::ArrayTrait;

    #[starknet::interface]
    trait IEarnscapeStaking<TContractState> {
        fn get_user_data(self: @TContractState, user: ContractAddress) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>);
    }

    #[storage]
    struct Storage {
        core_contract: ContractAddress,
        staking_contract: ContractAddress,
        default_vesting_time: u64,
        earn_balance: Map::<ContractAddress, u256>,
        stearn_balance: Map::<ContractAddress, u256>,
        user_vesting_count: Map::<ContractAddress, u32>,
        vesting_beneficiary: Map::<(ContractAddress, u32), ContractAddress>,
        vesting_cliff: Map::<(ContractAddress, u32), u64>,
        vesting_start: Map::<(ContractAddress, u32), u64>,
        vesting_duration: Map::<(ContractAddress, u32), u64>,
        vesting_slice_period: Map::<(ContractAddress, u32), u64>,
        vesting_amount_total: Map::<(ContractAddress, u32), u256>,
        vesting_released: Map::<(ContractAddress, u32), u256>,
        fee_recipient: ContractAddress,
        platform_fee_pct: u64,
        merchandise_admin_wallet: ContractAddress,
        earn_stark_manager: ContractAddress,
        total_amount_vested: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core_contract: ContractAddress,
        staking_contract: ContractAddress
    ) {
        self.core_contract.write(core_contract);
        self.staking_contract.write(staking_contract);
        self.default_vesting_time.write(2880 * 60);
    }

    #[abi(embed_v0)]
    impl VestingReaderImpl of super::IVestingReader<ContractState> {
        fn get_earn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            self.earn_balance.entry(beneficiary).read()
        }

        fn get_stearn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            self.stearn_balance.entry(beneficiary).read()
        }

        fn get_user_vesting_count(self: @ContractState, beneficiary: ContractAddress) -> u32 {
            self.user_vesting_count.entry(beneficiary).read()
        }

        fn get_vesting_schedule(
            self: @ContractState,
            beneficiary: ContractAddress,
            index: u32
        ) -> (ContractAddress, u64, u64, u64, u64, u256, u256) {
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

        fn get_user_vesting_details(
            self: @ContractState,
            beneficiary: ContractAddress
        ) -> Array<(u32, ContractAddress, u64, u64, u64, u64, u256, u256)> {
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut details = ArrayTrait::new();
            let mut i: u32 = 0;
            
            while i < vesting_count {
                let schedule = (
                    i,
                    self.vesting_beneficiary.entry((beneficiary, i)).read(),
                    self.vesting_cliff.entry((beneficiary, i)).read(),
                    self.vesting_start.entry((beneficiary, i)).read(),
                    self.vesting_duration.entry((beneficiary, i)).read(),
                    self.vesting_slice_period.entry((beneficiary, i)).read(),
                    self.vesting_amount_total.entry((beneficiary, i)).read(),
                    self.vesting_released.entry((beneficiary, i)).read()
                );
                details.append(schedule);
                i += 1;
            }
            details
        }

        fn calculate_releasable_amount(
            self: @ContractState,
            beneficiary: ContractAddress
        ) -> (u256, u256) {
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut total_releasable: u256 = 0;
            let mut total_remaining: u256 = 0;
            let mut i: u32 = 0;
            
            while i < vesting_count {
                let current_time = get_block_timestamp();
                let cliff = self.vesting_cliff.entry((beneficiary, i)).read();
                let start = self.vesting_start.entry((beneficiary, i)).read();
                let duration = self.vesting_duration.entry((beneficiary, i)).read();
                let amount_total = self.vesting_amount_total.entry((beneficiary, i)).read();
                let released = self.vesting_released.entry((beneficiary, i)).read();
                
                let (releasable, remaining) = if current_time < cliff {
                    (0, amount_total - released)
                } else if current_time >= start + duration {
                    (amount_total - released, 0)
                } else {
                    let time_from_start = current_time - start;
                    let slice_period = self.vesting_slice_period.entry((beneficiary, i)).read();
                    let vested_slice_periods = time_from_start / slice_period;
                    let vested_seconds = vested_slice_periods * slice_period;
                    let total_vested = (amount_total * vested_seconds.into()) / duration.into();
                    let rel = total_vested - released;
                    let rem = amount_total - total_vested;
                    (rel, rem)
                };
                
                total_releasable += releasable;
                total_remaining += remaining;
                i += 1;
            };
            
            (total_releasable, total_remaining)
        }

        fn preview_vesting_params(
            self: @ContractState,
            beneficiary: ContractAddress
        ) -> (u64, u64) {
            let staking = IEarnscapeStakingDispatcher { 
                contract_address: self.staking_contract.read() 
            };
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

        fn update_staking_contract(ref self: ContractState, staking: ContractAddress) {
            // Only core contract can update
            assert(starknet::get_caller_address() == self.core_contract.read(), 'Only core');
            self.staking_contract.write(staking);
        }
    }
}

#[starknet::interface]
trait IVestingReader<TContractState> {
    fn get_earn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn get_stearn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn get_user_vesting_count(self: @TContractState, beneficiary: starknet::ContractAddress) -> u32;
    fn get_vesting_schedule(self: @TContractState, beneficiary: starknet::ContractAddress, index: u32) -> (starknet::ContractAddress, u64, u64, u64, u64, u256, u256);
    fn get_user_vesting_details(self: @TContractState, beneficiary: starknet::ContractAddress) -> Array<(u32, starknet::ContractAddress, u64, u64, u64, u64, u256, u256)>;
    fn calculate_releasable_amount(self: @TContractState, beneficiary: starknet::ContractAddress) -> (u256, u256);
    fn preview_vesting_params(self: @TContractState, beneficiary: starknet::ContractAddress) -> (u64, u64);
    fn get_fee_recipient(self: @TContractState) -> starknet::ContractAddress;
    fn get_platform_fee_pct(self: @TContractState) -> u64;
    fn get_merchandise_admin_wallet(self: @TContractState) -> starknet::ContractAddress;
    fn get_earn_stark_manager(self: @TContractState) -> starknet::ContractAddress;
    fn get_default_vesting_time(self: @TContractState) -> u64;
    fn get_total_amount_vested(self: @TContractState) -> u256;
    fn update_staking_contract(ref self: TContractState, staking: starknet::ContractAddress);
}