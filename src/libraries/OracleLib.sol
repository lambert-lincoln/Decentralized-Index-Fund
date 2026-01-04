// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
// import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";

library OracleLib {
    error OracleLib__NegativePrice();
    error OracleLib__StalePrice();

    int256 public constant DECIMALS_PRECISION = 1e10;
    uint256 public constant TIMEOUT = 3600 seconds;
    uint256 public constant VOLATILE_TIMEOUT = 300 seconds;

    function getAssetPrice(AggregatorV3Interface priceFeed, bool isVolatile) public view returns (uint256) {
        (uint80 roundId, int256 answer,/* uint256 startedAt */, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 timeout = isVolatile ? VOLATILE_TIMEOUT : TIMEOUT;

        // if answer < 0, Chainlink Price Feed Oracle might be malfunctioning
        if (answer < 0) {
            revert OracleLib__NegativePrice();
        }

        // if does not update within the heartbeat/interval, then revert
        if (block.timestamp - updatedAt > timeout) {
            revert OracleLib__StalePrice();
        }

        // if ansewredInRound < roundId or updatedAt == 0, also revert stale price
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }

        uint8 feedDecimals = priceFeed.decimals();
        uint256 normalizedPrice;

            if (feedDecimals < 18) {
                normalizedPrice = uint256(answer) * 10 ** (18 - feedDecimals);
            } else if (feedDecimals > 18) {
                normalizedPrice = uint256(answer) / 10 ** (feedDecimals - 18);
            } else {
                normalizedPrice = uint256(answer);
            }
            
        return normalizedPrice;
    }
}
