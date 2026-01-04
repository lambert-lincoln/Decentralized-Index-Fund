// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {IndexToken} from "../src/IndexToken.sol";
import {IndexFund} from "../src/IndexFund.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployIndexFund is Script {
    IndexToken token;
    IndexFund indexFund;
    HelperConfig helperConfig;

    function run() external returns (IndexToken, IndexFund, HelperConfig) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast(config.deployerKey);

        token = new IndexToken(config.deployerAddress);
        indexFund = new IndexFund(config.tokenCollateralAddresses, config.priceFeedAddresses, address(token));
        token.transferOwnership(address(indexFund)); // transferring ownership to the Decentralized Index Fund

        vm.stopBroadcast();

        return (token, indexFund, helperConfig);
    }
}
