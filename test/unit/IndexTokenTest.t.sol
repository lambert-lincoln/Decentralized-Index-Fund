// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {IndexToken} from "../../src/IndexToken.sol";
import {DeployIndexFund} from "../../script/DeployIndexFund.s.sol";

contract IndexTokenTest is Test {
    DeployIndexFund deployer;
    IndexToken token;
    
    function setUp() public {
        deployer = new DeployIndexFund();
        (token, , ) = deployer.run();
    }
}
