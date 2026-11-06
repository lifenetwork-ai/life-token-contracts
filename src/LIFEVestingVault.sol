// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LIFEEmissionVault} from "./LIFEEmissionVault.sol";
import {TGEDistributionVault} from "./TGEDistributionVault.sol";
import {TGERegistry} from "./TGERegistry.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {VestingMath} from "./libraries/VestingMath.sol";

/// @notice Shared grant entitlement ledger; upgrades remain a disclosed governance trust boundary.
contract LIFEVestingVault is Initializable, UUPSUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    enum Account {
        Investor,
        Foundation
    }

    struct InitParams {
        IERC20 token;
        address governance;
        address foundationWallet;
        address upgradeTimelock;
        address emergencyPauser;
    }

    struct WalletProposal {
        address wallet;
        uint256 nonce;
    }

    struct Grant {
        uint8 category;
        address[2] wallets;
        uint256 allocation;
        uint16 cliffMonths;
        uint16 periods;
        bool revocable;
        Account futureRecipient;
        uint256 settledVested;
        uint256 paid;
        uint256[2] credit;
        WalletProposal[2] proposals;
    }
    struct SystemView {
        IERC20 token;
        TGERegistry registry;
        address governance;
        address pendingGovernance;
        address foundationWallet;
        address upgradeTimelock;
        address emergencyPauser;
        LIFEEmissionVault emission;
        TGEDistributionVault distribution;
        bool isSealed;
        uint256[4] allocated;
        uint256 totalAllocated;
        uint256 totalPaid;
        uint256 grantCount;
    }
    /// @custom:storage-location erc7201:life.storage.SharedVesting
    struct SharedStorage {
        SystemView info;
        mapping(bytes32 => Grant) grants;
        bytes32[] ids;
        mapping(address => bool) implementations;
        mapping(address => bool) reservedWallets;
        mapping(bytes32 => uint64) explicitGrantStarts;
        uint256 nextAutoGrantId;
    }
    uint256 public constant VESTING_BUDGET = 5_000_000_000e18;
    bytes32 private constant STORAGE_LOCATION = keccak256(abi.encode(uint256(keccak256("life.storage.SharedVesting")) - 1)) & ~bytes32(uint256(0xff));
    error InvalidConfiguration();
    error Unauthorized();
    error InvalidAccount();
    error InvalidState();
    error InvalidProposal();
    error GrantIdExhausted();
    event Claimed(bytes32 indexed grantId, Account indexed account, address indexed recipient, uint256 amount);

    function _state() internal pure returns (SharedStorage storage s) {
        bytes32 slot = STORAGE_LOCATION;
        assembly { s.slot := slot }
    }

    function _grant(bytes32 id) internal view returns (Grant storage g) {
        g = _state().grants[id];
        if (g.allocation == 0) revert InvalidGrant();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(InitParams calldata p) external initializer {
        if (address(p.token).code.length == 0 || p.upgradeTimelock.code.length == 0) revert InvalidConfiguration();
        if (p.governance == address(0) || p.emergencyPauser == address(0) || p.governance == p.emergencyPauser) revert InvalidConfiguration();
        if (p.foundationWallet == address(0) || p.foundationWallet == address(this) || p.foundationWallet == address(p.token) || p.foundationWallet == p.upgradeTimelock) revert InvalidConfiguration();
        if (p.foundationWallet == ERC1967Utils.getImplementation()) revert InvalidConfiguration();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        SystemView storage s = _state().info;
        s.token = p.token;
        s.governance = p.governance;
        s.foundationWallet = p.foundationWallet;
        s.upgradeTimelock = p.upgradeTimelock;
        s.emergencyPauser = p.emergencyPauser;
        _state().implementations[ERC1967Utils.getImplementation()] = true;
        _state().reservedWallets[p.foundationWallet] = true;
    }

    error InvalidGrant();
    error AllocationExceeded();
    error InsufficientFunding();
    event Configured(address indexed registry, address indexed emission, address indexed distribution);
    event GrantCreated(bytes32 indexed grantId, uint8 indexed category, address indexed beneficiary, uint256 allocation);
    event GrantStartAssigned(bytes32 indexed grantId, uint64 startTimestamp);
    event Sealed();

    function configure(TGERegistry r, LIFEEmissionVault e, TGEDistributionVault d) external onlyGovernance whenNotPaused {
        SystemView storage s = _state().info;
        if (address(s.registry) != address(0)) revert InvalidState();
        if (address(r).code.length == 0 || address(e).code.length == 0 || address(d).code.length == 0) revert InvalidConfiguration();
        if (address(r.readiness()) != address(this) || r.owner() != s.governance || r.tge() != 0) revert InvalidConfiguration();
        if (address(e.registry()) != address(r) || address(d.registry()) != address(r) || address(e.token()) != address(s.token) || address(d.token()) != address(s.token) || d.configurator() != s.governance) revert InvalidConfiguration();
        s.registry = r;
        s.emission = e;
        s.distribution = d;
        if (_forbiddenWallet(s.foundationWallet)) revert InvalidConfiguration();
        if (_forbiddenWallet(e.recipient()) || e.pendingRecipient() != address(0) || d.totalAllocated() != 0 || d.isSealed()) revert InvalidConfiguration();
        emit Configured(address(r), address(e), address(d));
    }

    function cap(uint8 category) public pure returns (uint256) {
        if (category == 0) return 2_000_000_000e18;
        if (category == 1) return 500_000_000e18;
        if (category == 2) return 1_000_000_000e18;
        if (category == 3) return 1_500_000_000e18;
        revert InvalidGrant();
    }

    /// @notice Create an initial grant with a contract-assigned sequential ID (recommended API).
    function createGrant(uint8 category, address beneficiary, uint256 amount)
        external onlyGovernance whenNotPaused returns (bytes32 id)
    {
        id = nextGrantId();
        _createInitialGrant(id, category, beneficiary, amount);
        _advanceGrantId(id);
    }

    function _createInitialGrant(bytes32 id, uint8 category, address beneficiary, uint256 amount) internal {
        SystemView storage s = _state().info;
        if (address(s.registry) == address(0) || s.isSealed || s.registry.tge() != 0) revert InvalidState();
        _createGrant(id, category, beneficiary, amount);
    }

    /// @notice Assign an unused Investor/Advisor reserve with an immutable, non-backdated start.
    function createGrantWithStart(bytes32 id, uint8 category, address beneficiary, uint256 amount, uint64 startTimestamp)
        external onlyGovernance whenNotPaused
    {
        _createGrantWithStart(id, category, beneficiary, amount, startTimestamp);
    }

    /// @notice Assign a reserve with a contract-assigned sequential ID (recommended API).
    function createGrantWithStart(uint8 category, address beneficiary, uint256 amount, uint64 startTimestamp)
        external onlyGovernance whenNotPaused returns (bytes32 id)
    {
        id = nextGrantId();
        _createGrantWithStart(id, category, beneficiary, amount, startTimestamp);
        _advanceGrantId(id);
    }

    /// @notice Preview the next unused automatic ID; manual IDs may occupy sequence values.
    /// @dev Zero cursor also supports proxies predating automatic IDs. Scan only collisions
    ///      from the cursor; no additional per-grant index or migration is required.
    function nextGrantId() public view returns (bytes32) {
        SharedStorage storage st = _state();
        uint256 candidate = st.nextAutoGrantId;
        if (candidate == 0) candidate = 1;
        while (st.grants[bytes32(candidate)].allocation != 0) {
            if (candidate == type(uint256).max) revert GrantIdExhausted();
            ++candidate;
        }
        return bytes32(candidate);
    }

    function _advanceGrantId(bytes32 id) internal {
        uint256 assigned = uint256(id);
        // Keep max as an occupied sentinel after its one successful allocation.
        _state().nextAutoGrantId = assigned == type(uint256).max ? assigned : assigned + 1;
    }

    function _createGrantWithStart(bytes32 id, uint8 category, address beneficiary, uint256 amount, uint64 startTimestamp) internal {
        SystemView storage s = _state().info;
        if (!s.isSealed || s.registry.tge() == 0 || block.timestamp < s.registry.tge()) revert InvalidState();
        if (category >= 2 || startTimestamp < block.timestamp) revert InvalidGrant();
        _createGrant(id, category, beneficiary, amount);
        _state().explicitGrantStarts[id] = startTimestamp;
        emit GrantStartAssigned(id, startTimestamp);
    }

    function _createGrant(bytes32 id, uint8 category, address beneficiary, uint256 amount) internal {
        SharedStorage storage st = _state();
        SystemView storage s = st.info;
        if (id == bytes32(0) || st.grants[id].allocation != 0 || amount == 0) revert InvalidGrant();
        uint256 budget = cap(category);
        if (amount > budget - s.allocated[category]) revert AllocationExceeded();
        bool revocable_ = category < 2;
        if (_forbiddenWallet(beneficiary) || (revocable_ && beneficiary == s.foundationWallet)) revert InvalidConfiguration();
        uint256 newTotal = s.totalAllocated + amount;
        if (s.token.balanceOf(address(this)) < VESTING_BUDGET - s.totalPaid) revert InsufficientFunding();
        st.reservedWallets[beneficiary] = true;
        Grant storage g = st.grants[id];
        g.category = category;
        g.wallets = [beneficiary, revocable_ ? s.foundationWallet : address(0)];
        g.allocation = amount;
        g.cliffMonths = revocable_ ? 12 : 3;
        g.periods = revocable_ ? 48 : 120;
        g.revocable = revocable_;
        s.allocated[category] += amount;
        s.totalAllocated = newTotal;
        st.ids.push(id);
        ++s.grantCount;
        emit GrantCreated(id, category, beneficiary, amount);
    }

    function seal() external onlyGovernance whenNotPaused {
        SystemView storage s = _state().info;
        if (address(s.registry) == address(0) || s.isSealed || s.registry.tge() != 0) revert InvalidState();
        for (uint8 i = 2; i < 4; ++i) {
            if (s.allocated[i] != cap(i)) revert InvalidState();
        }
        if (s.token.balanceOf(address(this)) < VESTING_BUDGET - s.totalPaid) revert InsufficientFunding();
        s.isSealed = true;
        emit Sealed();
    }

    function isReady() external view returns (bool) {
        SystemView storage s = _state().info;
        return s.isSealed && !paused() && s.token.balanceOf(address(this)) >= VESTING_BUDGET - s.totalPaid && s.emission.isReady() && s.distribution.isReady();
    }

    /// @notice Unassigned capacity is cumulative and never replenished by payouts or donations.
    function remainingBudget(uint8 category) public view returns (uint256) {
        uint256 budget = cap(category);
        return budget - _state().info.allocated[category];
    }

    /// @notice Zero stored start identifies initial/legacy grants anchored to global TGE.
    function grantStart(bytes32 id) public view returns (uint64) {
        _grant(id);
        uint64 start = _state().explicitGrantStarts[id];
        return start == 0 ? _state().info.registry.tge() : start;
    }

    function _forbiddenWallet(address w) internal view returns (bool) {
        SystemView storage s = _state().info;
        return w == address(0) || w == address(this) || w == address(s.token) || w == s.upgradeTimelock || w == address(s.registry) || w == address(s.emission) || w == address(s.distribution) || w == ERC1967Utils.getImplementation() || _state().implementations[w];
    }

    /// @notice System-module recipients are forbidden; configuration must be complete.
    function isRecipientAllowed(address w) external view returns (bool) {
        return address(_state().info.registry) != address(0) && !_forbiddenWallet(w);
    }

    function _checkAccount(bytes32 id, Account a) internal view {
        if (a == Account.Foundation && !_grant(id).revocable) revert InvalidAccount();
    }

    function _checkpoint(bytes32 id) internal {
        Grant storage s = _grant(id);
        uint256 v = vestedAt(id, uint64(block.timestamp));
        s.credit[uint256(s.futureRecipient)] += v - s.settledVested;
        s.settledVested = v;
    }

    function claim(bytes32 id, Account a) external whenNotPaused nonReentrant returns (uint256 amount) {
        _checkAccount(id, a);
        _checkpoint(id);
        Grant storage s = _grant(id);
        amount = s.credit[uint256(a)];
        if (amount == 0) return 0;
        s.credit[uint256(a)] = 0;
        s.paid += amount;
        _state().info.totalPaid += amount;
        _state().info.token.safeTransfer(s.wallets[uint256(a)], amount);
        emit Claimed(id, a, s.wallets[uint256(a)], amount);
    }

    function claimable(bytes32 id, Account a) external view returns (uint256 amount) {
        _checkAccount(id, a);
        Grant storage s = _grant(id);
        amount = s.credit[uint256(a)];
        if (a == s.futureRecipient) amount += vestedAt(id, uint64(block.timestamp)) - s.settledVested;
    }

    function vestedAt(bytes32 id, uint64 t) public view returns (uint256) {
        Grant storage s = _grant(id);
        uint64 tge = _state().info.registry.tge();
        if (tge == 0 || t < tge) return 0;
        return VestingMath.monthlyVested(s.allocation, grantStart(id), t, s.cliffMonths, s.periods);
    }

    function _authorizeUpgrade(address next) internal override whenPaused {
        SharedStorage storage st = _state();
        SystemView storage s = st.info;
        if (msg.sender != s.upgradeTimelock) revert Unauthorized();
        // Reserve wallet history rather than scanning an unbounded grant list at upgrade time.
        if (_forbiddenWallet(next) || st.reservedWallets[next]) revert InvalidConfiguration();
        if (address(s.registry) != address(0)) {
            if (s.distribution.allocations(next) != 0 || s.emission.recipient() == next || s.emission.pendingRecipient() == next) revert InvalidConfiguration();
        }
        st.implementations[ERC1967Utils.getImplementation()] = true;
        st.implementations[next] = true;
    }

    function details(bytes32 id) external view returns (Grant memory) { return _grant(id); }
    function system() external view returns (SystemView memory) { return _state().info; }
    function grantIdAt(uint256 index) external view returns (bytes32) { return _state().ids[index]; }
    event EntitlementRedirected(bytes32 indexed grantId, uint256 reclaimed, bool reclaimVested, bytes32 reasonHash, uint256 timestamp);
    event FutureRestored(bytes32 indexed grantId, bytes32 reasonHash, uint256 timestamp);
    event WalletChangeProposed(bytes32 indexed grantId,
        Account indexed account, address oldWallet, address indexed newWallet, uint256 nonce
    );
    event WalletChanged(bytes32 indexed grantId, Account indexed account, address oldWallet, address indexed newWallet, uint256 nonce);
    event WalletChangeCancelled(bytes32 indexed grantId, Account indexed account, uint256 nonce);
    event GovernanceProposed(address indexed oldGovernance, address indexed newGovernance);
    event GovernanceChanged(address indexed oldGovernance, address indexed newGovernance);
    modifier onlyGovernance() {
        if (msg.sender != _state().info.governance) revert Unauthorized();
        _;
    }

    function redirectToFoundation(bytes32 id, bool reclaimVested, bytes32 reasonHash) external onlyGovernance whenNotPaused {
        Grant storage s = _grant(id);
        if (!s.revocable || s.futureRecipient != Account.Investor) revert InvalidState();
        _checkpoint(id);
        uint256 reclaimed;
        if (reclaimVested) {
            reclaimed = s.credit[0];
            s.credit[0] = 0;
            s.credit[1] += reclaimed;
        }
        s.futureRecipient = Account.Foundation;
        emit EntitlementRedirected(id, reclaimed, reclaimVested, reasonHash, block.timestamp);
    }

    function restoreFutureToInvestor(bytes32 id, bytes32 reasonHash) external onlyGovernance whenNotPaused {
        Grant storage s = _grant(id);
        if (!s.revocable || s.futureRecipient != Account.Foundation) revert InvalidState();
        _checkpoint(id);
        s.futureRecipient = Account.Investor;
        emit FutureRestored(id, reasonHash, block.timestamp);
    }

    function _validateWallet(bytes32 id, Account a, address w) internal view {
        Grant storage s = _grant(id);
        if (
            _forbiddenWallet(w) || w == s.wallets[1 - uint256(a)]
                || w == s.wallets[uint256(a)]
        ) revert InvalidConfiguration();
    }

    function proposeWalletChange(bytes32 id, Account a, address w) external whenNotPaused {
        _checkAccount(id, a);
        Grant storage s = _grant(id);
        if (msg.sender != s.wallets[uint256(a)]) revert Unauthorized();
        _validateWallet(id, a, w);
        _checkpoint(id);
        WalletProposal storage p = s.proposals[uint256(a)];
        _state().reservedWallets[w] = true;
        p.wallet = w;
        ++p.nonce;
        emit WalletChangeProposed(id, a, msg.sender, w, p.nonce);
    }

    function acceptWalletChange(bytes32 id, Account a, uint256 nonce) external whenNotPaused {
        _checkAccount(id, a);
        Grant storage s = _grant(id);
        WalletProposal storage p = s.proposals[uint256(a)];
        if (p.wallet == address(0) || p.wallet != msg.sender || p.nonce != nonce) revert InvalidProposal();
        _validateWallet(id, a, msg.sender);
        _checkpoint(id);
        address old = s.wallets[uint256(a)];
        s.wallets[uint256(a)] = msg.sender;
        p.wallet = address(0);
        emit WalletChanged(id, a, old, msg.sender, nonce);
    }

    function cancelWalletChange(bytes32 id, Account a, uint256 nonce) external whenNotPaused {
        _checkAccount(id, a);
        Grant storage s = _grant(id);
        if (msg.sender != s.wallets[uint256(a)]) revert Unauthorized();
        WalletProposal storage p = s.proposals[uint256(a)];
        if (p.wallet == address(0) || p.nonce != nonce) revert InvalidProposal();
        _checkpoint(id);
        p.wallet = address(0);
        emit WalletChangeCancelled(id, a, nonce);
    }

    function proposeGovernance(address next) external onlyGovernance {
        SystemView storage s = _state().info;
        if (next == address(0) || next == s.emergencyPauser) revert InvalidConfiguration();
        s.pendingGovernance = next;
        emit GovernanceProposed(s.governance, next);
    }

    function acceptGovernance() external {
        SystemView storage s = _state().info;
        if (msg.sender != s.pendingGovernance) revert Unauthorized();
        // proposeGovernance and setEmergencyPauser prevent overlap with pending governance.
        address old = s.governance;
        s.governance = msg.sender;
        s.pendingGovernance = address(0);
        emit GovernanceChanged(old, msg.sender);
    }
    event EmergencyPauserChanged(address indexed previous, address indexed current);

    function pause() external {
        if (msg.sender != _state().info.emergencyPauser) revert Unauthorized();
        _pause();
    }

    function unpause() external {
        if (msg.sender != _state().info.upgradeTimelock) revert Unauthorized();
        _unpause();
    }

    function setEmergencyPauser(address next) external {
        SystemView storage s = _state().info;
        if (msg.sender != s.upgradeTimelock) revert Unauthorized();
        if (next == address(0) || next == s.governance || next == s.pendingGovernance) revert InvalidConfiguration();
        address old = s.emergencyPauser;
        s.emergencyPauser = next;
        emit EmergencyPauserChanged(old, next);
    }
}
