// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    /* Chain IDs */
    uint256 public immutable SEPOLIA_ETH_CHAINID = 11155111;
    uint256 public immutable MAINNET_CHAINID = 1;

    /* Token Variables */
    uint8 public constant DECIMALS = 8;
    uint256 public constant MOCK_ETH_USD_PRICE = 2000e8;
    uint256 public constant MOCK_BTC_USD_PRICE = 100000e8;
    uint256 public constant MOCK_LINK_USD_PRICE = 10e8;
    uint256 public constant INITIAL_BALANCE = 1000e8;
    uint8 public constant VOLATILE_DECIMALS = 18;

    struct NetworkConfig {
        address[] tokenCollateralAddresses;
        address[] priceFeedAddresses; // corresponding price feed addresses of collateral tokens
        uint256 deployerKey;
        address deployerAddress;
    }

    address public DEFAULT_ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public DEFAULT_SEPOLIA_ADDRESS = 0x12d98Fbe714E6C4538D94821930aE12523a1538c;
    address public DEFAULT_MAINNET_ADDRESS = address(0);
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == SEPOLIA_ETH_CHAINID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == MAINNET_CHAINID) {
            activeNetworkConfig = getMainnetEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /// @notice push addresses into fixed size array since we can't just pass [..] into structs
    /// @notice Only use it if collateral takes in many types of collateral
    /// @param addresses - an address type array containing addresses
    /// @return - address array
    function _pushAddresses(address[] memory addresses) internal returns (address[] memory) {
        address[] memory temp = new address[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            temp[i] = addresses[i];
        }
        return temp;
    }

    function getSepoliaEthConfig() public returns (NetworkConfig memory) {
        address[] memory tokenAddresses = new address[](3); // temporary token addresses
        tokenAddresses[0] = 0x7B79995E5F793a0CbA39242d0dB57f56F2F37199; // WETH
        tokenAddresses[1] = 0x922D6956C99E12DFeB3224DEA977D0939758A1Fe; // WTBC
        tokenAddresses[2] = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // LINK

        address[] memory feedAddresses = new address[](3); // temporary price feed addresses
        feedAddresses[0] = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // WETH / USD
        feedAddresses[1] = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // WBTC / USD
        feedAddresses[2] = 0xc59E3633BAAC79493d908e63626716e204A45EdF; // LINK / USD

        return NetworkConfig({
            tokenCollateralAddresses: tokenAddresses,
            priceFeedAddresses: feedAddresses,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY"),
            deployerAddress: DEFAULT_SEPOLIA_ADDRESS
        });
    }

    function getMainnetEthConfig() public returns (NetworkConfig memory) {
        address[] memory tokenAddresses = new address[](3); // temporary token Addresses
        tokenAddresses[0] = 0x7B79995E5F793a0CbA39242d0dB57f56F2F37199; // WETH
        tokenAddresses[1] = 0x922D6956C99E12DFeB3224DEA977D0939758A1Fe; // WTBC
        tokenAddresses[2] = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // LINK

        address[] memory feedAddresses = new address[](3); // temporary price feed addresses
        feedAddresses[0] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        feedAddresses[1] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
        feedAddresses[2] = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;

        return NetworkConfig({
            tokenCollateralAddresses: tokenAddresses,
            priceFeedAddresses: feedAddresses,
            deployerKey: vm.envUint("MAINNET_PRIVATE_KEY"), // its 0 lol u thought
            deployerAddress: DEFAULT_MAINNET_ADDRESS
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();

        address[] memory tokenAddresses = new address[](3); // temporary token Addresses
        address[] memory feedAddresses = new address[](3); // temporary price feed addresses

        // WETH/USD
        MockV3Aggregator ethFeed = new MockV3Aggregator(DECIMALS, int256(MOCK_ETH_USD_PRICE));
        ERC20Mock wethMock = new ERC20Mock("Mock Wrapped Ethereum", "WETH", msg.sender, 1000e8, VOLATILE_DECIMALS);
        tokenAddresses[0] = address(wethMock);
        feedAddresses[0] = address(ethFeed);

        // WBTC/USD Price Feed
        MockV3Aggregator btcFeed = new MockV3Aggregator(DECIMALS, int256(MOCK_BTC_USD_PRICE));
        ERC20Mock wbtcMock = new ERC20Mock("Mock Wrapped Bitcoin", "WBTC", msg.sender, 1000e8, DECIMALS);
        tokenAddresses[1] = address(wbtcMock);
        feedAddresses[1] = address(btcFeed);

        // LINK/USD Prce Feed
        MockV3Aggregator linkFeed = new MockV3Aggregator(DECIMALS, int256(MOCK_LINK_USD_PRICE));
        ERC20Mock linkMock = new ERC20Mock("Mock Chainlink Token ", "LINK", msg.sender, 1000e8, VOLATILE_DECIMALS);
        tokenAddresses[2] = address(linkMock);
        feedAddresses[2] = address(linkFeed);

        vm.stopBroadcast();

        return NetworkConfig({
            tokenCollateralAddresses: tokenAddresses,
            priceFeedAddresses: feedAddresses,
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY,
            deployerAddress: DEFAULT_ANVIL_ADDRESS
        });
    }

    function getActiveNetworkConfig() external returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
