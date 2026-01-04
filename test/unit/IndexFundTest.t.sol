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

    function testOwnerIsFund() public view {
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

    function testGetUsdValue() public view {
        uint256 expectedUsd = 2000;
        // this test assumes we're in anvil chain
        uint256 usdValue = indexFund.getUsdValue(weth, 1);
        assertEq(expectedUsd, usdValue);
    }

    function testUserCanDepositWbtc() public {
        // 1. Arrange
        uint256 deposit_amount = 1e8;

        // 2. Act
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(indexFund), deposit_amount);
        indexFund.depositAndMintdIDX(wbtc, deposit_amount, deposit_amount / 2);
        vm.stopPrank();

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
        vm.startPrank(USER);
        indexFund.mintIndexToken(USER, indexFund.getUsdValue(weth, DEPOSIT_AMOUNT) / 2);
        console2.log("USER BALANCE", token.balanceOf(USER));
        indexFund.redeemCollateral(weth, DEPOSIT_AMOUNT, indexFund.getUsdValue(weth, DEPOSIT_AMOUNT) / 2);
        vm.stopPrank();

        // 3. Assert
        // Contract should have no weth left
        uint256 expectedFundBalance = 0;
        uint256 indexFundBalance = ERC20Mock(weth).balanceOf(address(indexFund));
        assertEq(expectedFundBalance, indexFundBalance);
    }

    function testDepositRevertsWithUnapprovedToken() public {
        ERC20Mock randToken = new ERC20Mock("RAND", "RAND", USER, 1000e8, 18);
        
        vm.startPrank(USER);

        vm.expectRevert(abi.encodeWithSelector(IndexFund.IndexFund__TokenNotAllowed.selector, address(randToken)));
        indexFund.depositCollateral(address(randToken), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }
}
