// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrincipalProtectedRWAVault (Solution A Prototype)
 * @notice ERC-4626 style Principal-Protected RWA + Yield-in-Arrears Option Vault
 * @dev Holds 100% of user principal in Tier-1 Accumulating RWA Treasury tokens (e.g., sUSDS / USDY / USYC).
 *      Only newly accrued Treasury yield above `protectedPrincipalUSD` can ever be skimmed to purchase options.
 *      Winning option payouts are swept back into the RWA reserve and RATCHET UP the protected principal floor.
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Standard ERC-4626 interface for accumulating Tier-1 RWA tokens (e.g. Sky sUSDS, Circle USYC, wrapped USDY)
interface IRWATreasuryVault is IERC20 {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
    function convertToShares(uint256 assets) external view returns (uint256 shares);
}

/// @notice Interface for the Quantitative Option Execution Module (Derive / Hyperliquid / IBKR Bridge)
interface IOptionExecutionEngine {
    function executeMonthlyOptionBuy(uint256 usdcBudget, bytes calldata optionOrderData) external returns (bytes32 positionId);
}

contract PrincipalProtectedRWAVault {
    // --- Immutable Core Assets ---
    IERC20 public immutable usdc;
    IRWATreasuryVault public immutable rwaTreasury; // e.g., sUSDS or USYC (ERC-4626 accumulating T-Bill token)

    // --- Roles & Governance ---
    address public owner;
    address public optionEngine;
    address public feeRecipient;

    // --- Accounting & Principal Floor State ---
    uint256 public totalShares;
    mapping(address => uint256) public balanceOf;

    /// @notice The hard USD floor (in USDC 6 decimals) that can NEVER be touched for option purchases.
    /// @dev Increases on user deposits, decreases proportionally on user withdrawals, and RATCHETS UP on option wins!
    uint256 public protectedPrincipalUSD;

    // --- Fee Configuration (in basis points, 10000 = 100%) ---
    uint256 public performanceFeeBps = 1500; // 15% performance fee on net option profits
    uint256 public managementFeeBps = 50;    // 0.5% annual fee taken only from excess yield
    uint256 public currentEpochId;

    // --- Events ---
    event Deposit(address indexed user, uint256 usdcAmount, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 sharesBurned, uint256 usdcReceived);
    event YieldHarvestedForOptions(uint256 indexed epochId, uint256 yieldSkimmedUSDC, uint256 remainingProtectedFloor);
    event OptionProfitRatcheted(uint256 indexed epochId, uint256 grossProfitUSDC, uint256 netAddedToPrincipalFloor);

    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }

    constructor(address _usdc, address _rwaTreasury, address _optionEngine, address _feeRecipient) {
        usdc = IERC20(_usdc);
        rwaTreasury = IRWATreasuryVault(_rwaTreasury);
        optionEngine = _optionEngine;
        feeRecipient = _feeRecipient;
        owner = msg.sender;

        usdc.approve(_rwaTreasury, type(uint256).max);
    }

    // =========================================================================
    // 1. VIEW FUNCTIONS: NAV, PROTECTED FLOOR, & HARVESTABLE YIELD
    // =========================================================================

    /// @notice Total current USD value (in USDC terms) held inside the Tier-1 RWA Treasury token
    function totalRWAValueUSD() public view returns (uint256) {
        uint256 rwaShares = rwaTreasury.balanceOf(address(this));
        return rwaTreasury.convertToAssets(rwaShares);
    }

    /// @notice Returns the exact amount of accrued Treasury interest available to buy options right now
    function harvestableOptionBudgetUSD() public view returns (uint256) {
        uint256 currentVal = totalRWAValueUSD();
        if (currentVal <= protectedPrincipalUSD) {
            return 0;
        }
        return currentVal - protectedPrincipalUSD;
    }

    /// @notice Exchange rate of 1 Vault Share in USD (scaled by 1e18)
    function sharePriceUSD() public view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return (totalRWAValueUSD() * 1e18) / totalShares;
    }

    // =========================================================================
    // 2. USER DEPOSIT & 100% LIQUID WITHDRAWAL
    // =========================================================================

    /// @notice Deposit USDC -> 100% routed into Tier-1 RWA Treasury token -> Protected Floor increases 1:1
    function deposit(uint256 usdcAmount) external returns (uint256 shares) {
        require(usdcAmount > 0, "ZERO_DEPOSIT");

        uint256 currentNav = totalRWAValueUSD();
        if (totalShares == 0 || currentNav == 0) {
            shares = usdcAmount;
        } else {
            // Mint shares at current total NAV so existing accrued yield isn't diluted
            shares = (usdcAmount * totalShares) / currentNav;
        }

        require(usdc.transferFrom(msg.sender, address(this), usdcAmount), "TRANSFER_FAILED");

        // Route 100% of USDC into the Tier-1 RWA Treasury Vault
        rwaTreasury.deposit(usdcAmount, address(this));

        // Lock the new principal into the untouchable floor
        protectedPrincipalUSD += usdcAmount;
        totalShares += shares;
        balanceOf[msg.sender] += shares;

        emit Deposit(msg.sender, usdcAmount, shares);
    }

    /// @notice Withdraw anytime with zero lockup: burns shares and redeems underlying RWA into USDC
    function withdraw(uint256 shares) external returns (uint256 usdcOut) {
        require(shares > 0 && balanceOf[msg.sender] >= shares, "INVALID_SHARES");

        uint256 rwaSharesToRedeem = (rwaTreasury.balanceOf(address(this)) * shares) / totalShares;
        uint256 principalReduction = (protectedPrincipalUSD * shares) / totalShares;

        balanceOf[msg.sender] -= shares;
        totalShares -= shares;
        protectedPrincipalUSD -= principalReduction;

        // Redeem RWA shares directly to the user in USDC
        usdcOut = rwaTreasury.redeem(rwaSharesToRedeem, msg.sender, address(this));

        emit Withdraw(msg.sender, shares, usdcOut);
    }

    // =========================================================================
    // 3. YIELD-IN-ARREARS OPTION HARVESTING (ZERO PRINCIPAL TOUCHED)
    // =========================================================================

    /// @notice Skims ONLY the newly accrued RWA Treasury interest and sends it to the Option Engine
    function harvestYieldToOptionEngine(bytes calldata optionOrderData) external onlyOwner returns (uint256 optionBudgetUSDC) {
        optionBudgetUSDC = harvestableOptionBudgetUSD();
        require(optionBudgetUSDC > 0, "NO_ACCRUED_YIELD_AVAILABLE");

        // Convert the exact accrued yield amount into RWA shares to redeem
        uint256 rwaSharesToSkim = rwaTreasury.convertToShares(optionBudgetUSDC);
        uint256 redeemedUSDC = rwaTreasury.redeem(rwaSharesToSkim, address(this), address(this));

        // HARD INVARIANT CHECK: Remaining RWA value must ALWAYS be >= 100% of Protected Principal Floor!
        require(totalRWAValueUSD() + 1 >= protectedPrincipalUSD, "INVARIANT_BREACH: PRINCIPAL_FLOOR_VIOLATED");

        currentEpochId++;

        // Approve and route the skimmed interest to the Option Execution Engine
        usdc.approve(optionEngine, redeemedUSDC);
        IOptionExecutionEngine(optionEngine).executeMonthlyOptionBuy(redeemedUSDC, optionOrderData);

        emit YieldHarvestedForOptions(currentEpochId, redeemedUSDC, protectedPrincipalUSD);
    }

    // =========================================================================
    // 4. HIGH-WATER-MARK RATCHET: LOCKING IN OPTION WINNINGS
    // =========================================================================

    /// @notice Called when monthly options expire ITM; sweeps USDC payout into RWA & ratchets principal floor up!
    function settleOptionPayout(uint256 grossPayoutUSDC) external {
        require(grossPayoutUSDC > 0, "NO_PAYOUT");
        require(usdc.transferFrom(msg.sender, address(this), grossPayoutUSDC), "PAYOUT_TRANSFER_FAILED");

        // Deduct protocol performance fee (15%) on option winnings
        uint256 perfFee = (grossPayoutUSDC * performanceFeeBps) / 10000;
        uint256 netCompoundedProfit = grossPayoutUSDC - perfFee;

        if (perfFee > 0) {
            usdc.transfer(feeRecipient, perfFee);
        }

        // Deposit net option winnings back into the Tier-1 RWA Treasury token
        rwaTreasury.deposit(netCompoundedProfit, address(this));

        // RATCHET UP THE PROTECTED PRINCIPAL FLOOR!
        // Past option gains now become permanently protected principal that generates future T-Bill yield!
        protectedPrincipalUSD += netCompoundedProfit;

        emit OptionProfitRatcheted(currentEpochId, grossPayoutUSDC, netCompoundedProfit);
    }
}
