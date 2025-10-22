#[starknet::contract]
mod VestingFacade {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // Import the interfaces from the split contracts
    #[starknet::interface]
    trait IVestingCore<TContractState> {
        fn update_earn_stark_manager(ref self: TContractState, earn_stark_manager: ContractAddress);
        fn update_staking_contract(ref self: TContractState, staking_contract: ContractAddress);
        fn update_earn_balance(ref self: TContractState, user: ContractAddress, amount: u256);
        fn update_stearn_balance(ref self: TContractState, user: ContractAddress, amount: u256);
        fn st_earn_transfer(ref self: TContractState, sender: ContractAddress, amount: u256);
        fn deposit_earn(ref self: TContractState, beneficiary: ContractAddress, amount: u256);
        fn release_vested_amount(ref self: TContractState, beneficiary: ContractAddress);
        fn force_release_vested_amount(ref self: TContractState, beneficiary: ContractAddress);
        fn release_vested_admins(ref self: TContractState);
        fn set_fee_recipient(ref self: TContractState, recipient: ContractAddress);
        fn set_platform_fee_pct(ref self: TContractState, pct: u64);
        fn update_merchandise_admin_wallet(ref self: TContractState, merch_wallet: ContractAddress);
        fn give_a_tip(ref self: TContractState, receiver: ContractAddress, tip_amount: u256);
    }

    #[starknet::interface]
    trait IVestingReader<TContractState> {
        fn get_earn_balance(self: @TContractState, beneficiary: ContractAddress) -> u256;
        fn get_stearn_balance(self: @TContractState, beneficiary: ContractAddress) -> u256;
        fn get_user_vesting_count(self: @TContractState, beneficiary: ContractAddress) -> u32;
        fn get_vesting_schedule(self: @TContractState, beneficiary: ContractAddress, index: u32) -> (ContractAddress, u64, u64, u64, u64, u256, u256);
        fn get_user_vesting_details(self: @TContractState, beneficiary: ContractAddress) -> Array<(u32, ContractAddress, u64, u64, u64, u64, u256, u256)>;
        fn calculate_releasable_amount(self: @TContractState, beneficiary: ContractAddress) -> (u256, u256);
        fn preview_vesting_params(self: @TContractState, beneficiary: ContractAddress) -> (u64, u64);
        fn get_fee_recipient(self: @TContractState) -> ContractAddress;
        fn get_platform_fee_pct(self: @TContractState) -> u64;
        fn get_merchandise_admin_wallet(self: @TContractState) -> ContractAddress;
        fn get_earn_stark_manager(self: @TContractState) -> ContractAddress;
        fn get_default_vesting_time(self: @TContractState) -> u64;
        fn get_total_amount_vested(self: @TContractState) -> u256;
    }

    #[storage]
    struct Storage {
        core_contract: ContractAddress,
        reader_contract: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core_contract: ContractAddress,
        reader_contract: ContractAddress
    ) {
        self.core_contract.write(core_contract);
        self.reader_contract.write(reader_contract);
    }

    #[abi(embed_v0)]
    impl VestingFacadeImpl of super::IVesting<ContractState> {
        // ========== ADMIN FUNCTIONS - Delegate to Core ==========
        fn update_earn_stark_manager(ref self: ContractState, earn_stark_manager: ContractAddress) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .update_earn_stark_manager(earn_stark_manager);
        }

        fn update_staking_contract(ref self: ContractState, staking_contract: ContractAddress) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .update_staking_contract(staking_contract);
        }

        fn set_fee_recipient(ref self: ContractState, recipient: ContractAddress) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .set_fee_recipient(recipient);
        }

        fn set_platform_fee_pct(ref self: ContractState, pct: u64) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .set_platform_fee_pct(pct);
        }

        fn update_merchandise_admin_wallet(ref self: ContractState, merch_wallet: ContractAddress) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .update_merchandise_admin_wallet(merch_wallet);
        }

        fn update_earn_stark_manager_address(ref self: ContractState, contract_addr: ContractAddress) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .update_earn_stark_manager(contract_addr);
        }

        // ========== BALANCE MANAGEMENT - Delegate appropriately ==========
        fn get_earn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_earn_balance(beneficiary)
        }

        fn update_earn_balance(ref self: ContractState, user: ContractAddress, amount: u256) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .update_earn_balance(user, amount);
        }

        fn get_stearn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_stearn_balance(beneficiary)
        }

        fn update_stearn_balance(ref self: ContractState, user: ContractAddress, amount: u256) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .update_stearn_balance(user, amount);
        }

        fn st_earn_transfer(ref self: ContractState, sender: ContractAddress, amount: u256) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .st_earn_transfer(sender, amount);
        }

        // ========== VESTING OPERATIONS - Delegate to Core ==========
        fn deposit_earn(ref self: ContractState, beneficiary: ContractAddress, amount: u256) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .deposit_earn(beneficiary, amount);
        }

        fn calculate_releasable_amount(self: @ContractState, beneficiary: ContractAddress) -> (u256, u256) {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .calculate_releasable_amount(beneficiary)
        }

        fn release_vested_amount(ref self: ContractState, beneficiary: ContractAddress) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .release_vested_amount(beneficiary);
        }

        fn force_release_vested_amount(ref self: ContractState, beneficiary: ContractAddress) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .force_release_vested_amount(beneficiary);
        }

        fn release_vested_admins(ref self: ContractState) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .release_vested_admins();
        }

        // ========== VESTING QUERIES - Delegate to Reader ==========
        fn get_user_vesting_count(self: @ContractState, beneficiary: ContractAddress) -> u32 {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_user_vesting_count(beneficiary)
        }

        fn get_vesting_schedule(
            self: @ContractState,
            beneficiary: ContractAddress,
            index: u32
        ) -> (ContractAddress, u64, u64, u64, u64, u256, u256) {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_vesting_schedule(beneficiary, index)
        }

        fn get_user_vesting_details(
            self: @ContractState,
            beneficiary: ContractAddress
        ) -> Array<(u32, ContractAddress, u64, u64, u64, u64, u256, u256)> {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_user_vesting_details(beneficiary)
        }

        fn preview_vesting_params(self: @ContractState, beneficiary: ContractAddress) -> (u64, u64) {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .preview_vesting_params(beneficiary)
        }

        // ========== CONFIGURATION GETTERS - Delegate to Reader ==========
        fn get_fee_recipient(self: @ContractState) -> ContractAddress {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_fee_recipient()
        }

        fn get_platform_fee_pct(self: @ContractState) -> u64 {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_platform_fee_pct()
        }

        fn get_merchandise_admin_wallet(self: @ContractState) -> ContractAddress {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_merchandise_admin_wallet()
        }

        fn get_earn_stark_manager(self: @ContractState) -> ContractAddress {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_earn_stark_manager()
        }

        fn get_default_vesting_time(self: @ContractState) -> u64 {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_default_vesting_time()
        }

        fn get_total_amount_vested(self: @ContractState) -> u256 {
            IVestingReaderDispatcher { contract_address: self.reader_contract.read() }
                .get_total_amount_vested()
        }

        // ========== TIPPING - Delegate to Core ==========
        fn give_a_tip(ref self: ContractState, receiver: ContractAddress, tip_amount: u256) {
            IVestingCoreDispatcher { contract_address: self.core_contract.read() }
                .give_a_tip(receiver, tip_amount);
        }
    }
}

// Original interface that other contracts depend on
#[starknet::interface]
trait IVesting<TContractState> {
    fn update_earn_stark_manager(ref self: TContractState, earn_stark_manager: starknet::ContractAddress);
    fn update_staking_contract(ref self: TContractState, staking_contract: starknet::ContractAddress);
    fn set_fee_recipient(ref self: TContractState, recipient: starknet::ContractAddress);
    fn set_platform_fee_pct(ref self: TContractState, pct: u64);
    fn update_merchandise_admin_wallet(ref self: TContractState, merch_wallet: starknet::ContractAddress);
    fn update_earn_stark_manager_address(ref self: TContractState, contract_addr: starknet::ContractAddress);
    fn get_earn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn update_earn_balance(ref self: TContractState, user: starknet::ContractAddress, amount: u256);
    fn get_stearn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn update_stearn_balance(ref self: TContractState, user: starknet::ContractAddress, amount: u256);
    fn st_earn_transfer(ref self: TContractState, sender: starknet::ContractAddress, amount: u256);
    fn deposit_earn(ref self: TContractState, beneficiary: starknet::ContractAddress, amount: u256);
    fn calculate_releasable_amount(self: @TContractState, beneficiary: starknet::ContractAddress) -> (u256, u256);
    fn release_vested_amount(ref self: TContractState, beneficiary: starknet::ContractAddress);
    fn force_release_vested_amount(ref self: TContractState, beneficiary: starknet::ContractAddress);
    fn release_vested_admins(ref self: TContractState);
    fn get_user_vesting_count(self: @TContractState, beneficiary: starknet::ContractAddress) -> u32;
    fn get_vesting_schedule(self: @TContractState, beneficiary: starknet::ContractAddress, index: u32) -> (starknet::ContractAddress, u64, u64, u64, u64, u256, u256);
    fn get_user_vesting_details(self: @TContractState, beneficiary: starknet::ContractAddress) -> Array<(u32, starknet::ContractAddress, u64, u64, u64, u64, u256, u256)>;
    fn preview_vesting_params(self: @TContractState, beneficiary: starknet::ContractAddress) -> (u64, u64);
    fn get_fee_recipient(self: @TContractState) -> starknet::ContractAddress;
    fn get_platform_fee_pct(self: @TContractState) -> u64;
    fn get_merchandise_admin_wallet(self: @TContractState) -> starknet::ContractAddress;
    fn get_earn_stark_manager(self: @TContractState) -> starknet::ContractAddress;
    fn get_default_vesting_time(self: @TContractState) -> u64;
    fn get_total_amount_vested(self: @TContractState) -> u256;
    fn give_a_tip(ref self: TContractState, receiver: starknet::ContractAddress, tip_amount: u256);
}