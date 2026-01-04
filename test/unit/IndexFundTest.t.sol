// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DeployIndexFund} from "../../script/DeployIndexFund.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IndexToken} from "../../src/IndexToken.sol";
import {IndexFund} from "../../src/IndexFund.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";

contract IndexFundTest is Test {
    DeployIndexFund deployer;
    HelperConfig config;
    IndexToken token;
    IndexFund indexFund;

    address[] tokenCollateralAddress;
    address[] priceFeedAddresses;
    uint256 deployerKey;

    address public USER = makeAddr("USER");
    uint256 public constant STARTING_USER_BALANCE = 1e5 ether;
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;

    address weth;
    address wbtc;
    address link;

    function setUp() public {
        deployer = new DeployIndexFund();
        (token, indexFund, config) = deployer.run();

        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();
        tokenCollateralAddress = networkConfig.tokenCollateralAddresses;
        weth = tokenCollateralAddress[0];
        wbtc = tokenCollateralAddress[1];
        link = tokenCollateralAddress[2];
        priceFeedAddresses = networkConfig.priceFeedAddresses;
        deployerKey = networkConfig.deployerKey;

        ERC20Mock(tokenCollateralAddress[0]).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(tokenCollateralAddress[1]).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(tokenCollateralAddress[2]).mint(USER, STARTING_USER_BALANCE);
    }

    function testOwnerIsFund() public {
        assertEq(token.owner(), address(indexFund));
    }

    modifier depositedCollateral(address collateralAddress) {
        vm.startPrank(USER);
        // The Fund cannot pull tokens unless the User approves it first
        ERC20Mock(collateralAddress).approve(address(indexFund), DEPOSIT_AMOUNT);
        indexFund.depositCollateral(collateralAddress, DEPOSIT_AMOUNT);

        vm.stopPrank();
        _;
    }

    function testUserCanDepositCollateral() public depositedCollateral(weth) {
        // 3. Assert
        // User's balance should go down whereas Fund's balance should be the deposit amount
        uint256 finalUserBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 expectedUserBalance = STARTING_USER_BALANCE - DEPOSIT_AMOUNT;
        assertEq(finalUserBalance, expectedUserBalance);

        uint256 indexFundWethBalance = ERC20Mock(weth).balanceOf(address(indexFund));
        assertEq(indexFundWethBalance, DEPOSIT_AMOUNT);
    }

    function testGetUsdValue() public {
        uint256 expectedUsd = 2000;
        // this test assumes we're in anvil chain
        uint256 usdValue = indexFund.getUsdValue(weth, 1);
        assertEq(expectedUsd, usdValue);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral(weth) {
        (uint256 totalMintedValue, uint256 totalCollateralValueInUsd) = indexFund.getAccountInformation(USER);
        uint256 expectedCollateral = indexFund.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assertEq(totalMintedValue, 0);
        assertEq(expectedCollateral, DEPOSIT_AMOUNT / uint256(OracleLib.DECIMALS_PRECISION));
    }

    function testUserCanDepositWbtc() public {
        // 1. Arrange
        uint256 deposit_amount = 1e8;

        // 2. Act
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(indexFund), deposit_amount);
        indexFund.depositAndMintdIDX(wbtc, deposit_amount);

        // 3. Assert
        // The Math:
        // 1 WBTC = $100,000
        // We expect 100,000 Tokens, BUT scaled to 18 decimals standard
        uint256 userIDXBalance = token.balanceOf(USER);
        uint256 expectedIDXBalance = 100000 ether;
        assertEq(userIDXBalance, expectedIDXBalance);
    }

    function testUserCanRedeemCollateral() public depositedCollateral(weth) {
        // 2. Act
        indexFund.mintIndexToken(USER, weth, DEPOSIT_AMOUNT);
        console2.log("USER BALANCE" ,token.balanceOf(USER));
        indexFund.redeemCollateral(weth, DEPOSIT_AMOUNT);

        // 3. Assert
        // Contract should have no weth left
        uint256 expectedFundBalance = 0;
        uint256 indexFundBalance = ERC20Mock(weth).balanceOf(address(indexFund));
        assertEq(expectedFundBalance, indexFundBalance);
    }
}
