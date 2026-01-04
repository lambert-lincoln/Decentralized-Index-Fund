// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IndexToken} from "./IndexToken.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Test.sol";

using OracleLib for AggregatorV3Interface;

/// @title Index Fund
/// @author l@mb
/// @notice This is the Index Fund Vault/Engine where all the logic is stored
contract IndexFund is ReentrancyGuard {
    /* errors */

    error IndexFund__MustBeMoreThanZero();
    error IndexFund__DepositFailed();
    error IndexFund__TokenNotAllowed(address token);
    error IndexFund__MintFailed();
    error IndexFund__BurnFailed();
    error IndexFund__TransferFailed(address from, address to, uint256 amount);
    error IndexFund__TokenCollateralAddressesAndPriceFeedAddressesLengthDontMatch(
        uint256 tokenAddressesLength, uint256 priceFeedAddressesLength
    );
    error IndexFund__BreaksHealthFactor();
    error IndexFund__UserIsHealthy();
    error IndexFund__HealthFactorNotImproved();

    /* Type Declarations */

    /* State Variables */

    IndexToken public immutable i_indexToken;

    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_IndexFundMinted;

    address[] public s_collateralTokens;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_MULTIPLIER = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; /// @dev 200% overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.0
    uint256 private constant LIQUIDATION_BONUS = 10; // incentive for liquidating other users with bad health factor
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /* Events */

    event DepositSuccessful(address indexed from, uint256 amount);
    event TokenMinted(address indexed to, uint256 mintedAmount);
    event UserLiquidated(
        address indexed liquidated,
        address indexed liquidator,
        address indexed tokenCollateralAddress,
        uint256 collateralRewarded,
        uint256 debtCovered
    );
    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed tokenCollateralAddress, uint256 amountRedeemed
    );

    /* Modifiers */

    /// @notice checks if associated amount is more than zero
    /// @param amount - amount associated with the transaction
    modifier moreThanZero(uint256 amount) {
        // if amount is less than zero, revert
        if (amount <= 0) {
            revert IndexFund__MustBeMoreThanZero();
        }
        _;
    }

    /// @notice check if token is allowed or not
    /// @param tokenCollateralAddress - address of the token
    modifier isAllowedToken(address tokenCollateralAddress) {
        /// @dev should also implement logic for deposits that are not WBTC, WETH or LINK
        if (s_priceFeeds[tokenCollateralAddress] == address(0)) {
            revert IndexFund__TokenNotAllowed(tokenCollateralAddress);
        }
        _;
    }

    /* Constructor */

    constructor(address[] memory tokenCollateralAddresses, address[] memory priceFeedAddresses, address dIDX) {
        if (tokenCollateralAddresses.length != priceFeedAddresses.length) {
            revert IndexFund__TokenCollateralAddressesAndPriceFeedAddressesLengthDontMatch(
                tokenCollateralAddresses.length, priceFeedAddresses.length
            );
        }

        for (uint256 i = 0; i < tokenCollateralAddresses.length; i++) {
            s_collateralTokens.push(tokenCollateralAddresses[i]);
            s_priceFeeds[tokenCollateralAddresses[i]] = priceFeedAddresses[i];
        }
        i_indexToken = IndexToken(dIDX);
    }

    /* External Functions */

    function depositAndMintdIDX(address tokenCollateralAddress, uint256 collateralAmount, uint256 amountToMint)
        external
    {
        // Deposit
        depositCollateral(tokenCollateralAddress, collateralAmount);

        // Minting Logic
        /// @notice This contract assumes 1 dIDX = $1
        mintIndexToken(msg.sender, amountToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(collateralAmount)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert IndexFund__DepositFailed();
        }
        emit DepositSuccessful(msg.sender, collateralAmount);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount, uint256 amountToBurn)
        external
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // valuation
        uint256 usdValue = _getUsdValue(tokenCollateralAddress, collateralAmount); // = amountToBurn
        console.log("USD Value: ", usdValue);

        // burn
        _burn(msg.sender, amountToBurn);

        // give collateral back to user
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, collateralAmount);
    }

    function mintIndexToken(address to, uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
       _mintIndexTokens(to, amountToMint);
        _revertIfHealthFactorIsBroken(to);
    }

    function liquidate(
        address tokenCollateralAddress,
        address user,
        /* <- violator */
        uint256 debtToCover
    )
        external
        moreThanZero(debtToCover)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // check if user is unhealthy
        if (_healthFactor(user) > MIN_HEALTH_FACTOR) {
            revert IndexFund__UserIsHealthy();
        }
        // debtToCover is in USD, therefore debtToCover = burnAmount
        _burn(msg.sender, debtToCover);

        // update state variable
        s_IndexFundMinted[user] -= debtToCover;

        // Rewarding liquidator
        uint256 bonusCollateralInUsd = (debtToCover * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralAwardedInUsd = debtToCover + bonusCollateralInUsd;
        uint256 totalCollateralAwarded = _getTokenAmountFromUsd(tokenCollateralAddress, totalCollateralAwardedInUsd);
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, totalCollateralAwarded);

        uint256 endingHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingHealthFactor < MIN_HEALTH_FACTOR) {
            revert IndexFund__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);

        emit UserLiquidated(user, msg.sender, tokenCollateralAddress, totalCollateralAwarded, debtToCover);
    }

    function getUsdValue(address token, uint256 amount)
        external
        view
        moreThanZero(amount)
        isAllowedToken(token)
        returns (uint256)
    {
        return _getUsdValue(token, amount);
    }

    function burn(address from, uint256 amountIndexTokensToBurn) external moreThanZero(amountIndexTokensToBurn) {
        _burn(from, amountIndexTokensToBurn);
    }

    /* internal & private view & pure functions */

    function _getUsdValue(address token, uint256 amount) private view returns (uint256 usdValue) {
        uint256 standardizedPrice = OracleLib.getAssetPrice(AggregatorV3Interface(s_priceFeeds[token]));

        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        uint256 normalizedAmount;
        if (tokenDecimals < 18) {
            // Example with WBTC (8 decimals)
            // 1 WBTC = 1e8
            // Normalized Amount = 1e8 * 10^(18-8) = 1e18
            normalizedAmount = amount * 10 ** (18 - tokenDecimals);
        } else if (tokenDecimals > 18) {
            // Example with token with 20 decimals
            // 1 egToken = 1e20
            // Normalized Amount = 1e20 / * 10^(20-18) = 1e18
            normalizedAmount = amount / (10 ** (tokenDecimals - 18));
        } else {
            normalizedAmount = amount;
        }

        usdValue = (normalizedAmount * standardizedPrice) / PRECISION;
        return usdValue;
    }

    function _getTokenAmountFromUsd(address token, uint256 usdAmountInWei) private view returns (uint256) {
        uint256 standardizedPrice = OracleLib.getAssetPrice(AggregatorV3Interface(s_priceFeeds[token]));
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        uint256 normalizedAmount = (usdAmountInWei * PRECISION) / (standardizedPrice);

        if (tokenDecimals < 18) {
            return normalizedAmount / 10 ** (18 - tokenDecimals);
        } else if (tokenDecimals > 18) {
            return normalizedAmount * 10 ** (tokenDecimals - 18);
        } else {
            return normalizedAmount;
        }
    }

    function _burn(address from, uint256 amountIndexTokensToBurn) private {
        bool burnSuccess = i_indexToken.burn(from, amountIndexTokensToBurn);
        if (!burnSuccess) {
            revert IndexFund__BurnFailed();
        }
    }

    function _mintIndexTokens(address to, uint256 amountToMint) private {
        s_IndexFundMinted[to] += amountToMint;
        bool success = i_indexToken.mint(to, amountToMint);
        if (!success) {
            revert IndexFund__MintFailed();
        }
        emit TokenMinted(to, amountToMint);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 collateralAmount)
        private
    {
        // removes deposit from user
        s_collateralDeposited[from][tokenCollateralAddress] -= collateralAmount;

        // transfers collateral to redeemer or liquidator
        bool transferSuccess = IERC20(tokenCollateralAddress).transfer(to, collateralAmount);
        if (!transferSuccess) {
            revert IndexFund__TransferFailed(from, to, collateralAmount);
        }
        emit CollateralRedeemed(from, to, tokenCollateralAddress, collateralAmount);
    }

    /// @notice Calculates the safety of a borrow position. Remember that we want this protocol to be overcollateralized
    /// @dev Health Factor = (Total Collateral Value * Weighted Average Liquidation Threshold) / Total Borrow Value
    /// @param user - The address of the user
    /// @return healthFactor - The health factor of the user
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        uint256 totalCollateralValueInUsd = getAccountCollateralValue(user);
        uint256 totalMintedValueInUsd = getTotalMintedValue(user);
        if (totalMintedValueInUsd == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        healthFactor = (collateralAdjustedForThreshold * 1e18) / totalMintedValueInUsd;
    }

    /// @notice Checks a user's health factor and revert the transaction if they are below the minimum health factor
    /// @notice Acts as a bouncer
    /// @param user - Address of user
    function _revertIfHealthFactorIsBroken(address user) internal view {
        if (_healthFactor(user) < MIN_HEALTH_FACTOR) {
            revert IndexFund__BreaksHealthFactor();
        }
    }

    /* external & public view & pure functions */

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            totalCollateralValueInUsd += _getUsdValue(
                s_collateralTokens[i], s_collateralDeposited[user][s_collateralTokens[i]]
            );
        }
        return totalCollateralValueInUsd;
    }

    function getTotalMintedValue(address user) public view returns (uint256) {
        // recall that 1 dIDX = $1
        return s_IndexFundMinted[user];
    }

    function getAccountInformation(address user) external view returns (uint256, uint256) {
        return (getTotalMintedValue(user), getAccountCollateralValue(user));
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) external view returns (uint256) {
        return _getTokenAmountFromUsd(token, usdAmountInWei);
    }
}
