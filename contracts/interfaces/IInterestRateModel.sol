// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILiquidity.sol";

/**
 * @title Interface to an Interest Rate Model
 */
interface IInterestRateModel {
    /**
     * Get interest rate model name
     * @return Interest rate model name
     */
    function name() external view returns (string memory);

    /**
     * Get interest rate
     * @return Interest per second
     */
    function rate() external view returns (uint256);

    /**
     * Distribute amount and interest to liquidity
     * @param amount Amount to distribute
     * @param interest Interest to distribute
     * @param nodes Liquidity nodes
     * @param count Liquidity node count
     * @return Liquidity nodes, Liquidity node count
     */
    function distribute(
        uint256 amount,
        uint256 interest,
        ILiquidity.NodeSource[] memory nodes,
        uint16 count
    ) external view returns (ILiquidity.NodeSource[] memory, uint16);

    /**
     * Utilization updated handler
     * @param utilization Utilization as a fixed-point, 18 decimal fraction
     */
    function onUtilizationUpdated(uint256 utilization) external;
}
