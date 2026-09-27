// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import {
    IUniswapV3FactoryMinimal,
    IUniswapV3PoolMinimal
} from "../../../src/oracles/uniswap/interfaces/IUniswapV3Minimal.sol";

contract MockDecimalsToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract MockUniswapV3Factory is IUniswapV3FactoryMinimal {
    mapping(bytes32 key => address pool) private _pools;

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        _pools[_poolKey(tokenA, tokenB, fee)] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee)
        external
        view
        returns (address pool)
    {
        pool = _pools[_poolKey(tokenA, tokenB, fee)];
    }

    function _poolKey(address tokenA, address tokenB, uint24 fee) private pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1, fee));
    }
}

contract MockUniswapV3Pool is IUniswapV3PoolMinimal {
    address public override token0;
    address public override token1;
    uint24 public override fee;
    uint128 public override liquidity;

    uint160 public sqrtPriceX96 = uint160(1 << 96);
    int24 public currentTick;
    uint16 public observationIndex;
    uint16 public observationCardinality;
    uint32 public latestObservationTime;
    bool public latestObservationInitialized;
    uint32 public availableHistory;
    int56 public tickCumulativeStart;
    int56 public tickCumulativeEnd;
    uint160 public secondsPerLiquidityStart;
    uint160 public secondsPerLiquidityEnd;
    bool public malformedObservationResponse;

    error HistoryUnavailable(uint32 requested, uint32 available);

    constructor(address tokenA, address tokenB, uint24 fee_) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        fee = fee_;
    }

    function setIdentity(address token0_, address token1_, uint24 fee_) external {
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
    }

    function setSlot0(int24 tick_, uint16 index_, uint16 cardinality_) external {
        currentTick = tick_;
        observationIndex = index_;
        observationCardinality = cardinality_;
    }

    function setSqrtPriceX96(uint160 sqrtPriceX96_) external {
        sqrtPriceX96 = sqrtPriceX96_;
    }

    function setLiquidity(uint128 liquidity_) external {
        liquidity = liquidity_;
    }

    function setLatestObservation(uint32 timestamp, bool initialized) external {
        latestObservationTime = timestamp;
        latestObservationInitialized = initialized;
    }

    function setObservationWindow(
        uint32 availableHistory_,
        int56 tickCumulativeStart_,
        int56 tickCumulativeEnd_,
        uint160 secondsPerLiquidityStart_,
        uint160 secondsPerLiquidityEnd_
    ) external {
        availableHistory = availableHistory_;
        tickCumulativeStart = tickCumulativeStart_;
        tickCumulativeEnd = tickCumulativeEnd_;
        secondsPerLiquidityStart = secondsPerLiquidityStart_;
        secondsPerLiquidityEnd = secondsPerLiquidityEnd_;
    }

    function setMalformedObservationResponse(bool malformed) external {
        malformedObservationResponse = malformed;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (
            sqrtPriceX96,
            currentTick,
            observationIndex,
            observationCardinality,
            observationCardinality,
            0,
            true
        );
    }

    function observations(uint256 index) external view returns (uint32, int56, uint160, bool) {
        if (index != observationIndex) return (0, 0, 0, false);
        return (
            latestObservationTime,
            tickCumulativeEnd,
            secondsPerLiquidityEnd,
            latestObservationInitialized
        );
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        )
    {
        if (secondsAgos.length != 2 || secondsAgos[0] > availableHistory || secondsAgos[1] != 0) {
            uint32 requested = secondsAgos.length == 0 ? 0 : secondsAgos[0];
            revert HistoryUnavailable(requested, availableHistory);
        }

        uint256 responseLength = malformedObservationResponse ? 1 : 2;
        tickCumulatives = new int56[](responseLength);
        secondsPerLiquidityCumulativeX128s = new uint160[](responseLength);
        tickCumulatives[0] = tickCumulativeStart;
        secondsPerLiquidityCumulativeX128s[0] = secondsPerLiquidityStart;
        if (responseLength == 2) {
            tickCumulatives[1] = tickCumulativeEnd;
            secondsPerLiquidityCumulativeX128s[1] = secondsPerLiquidityEnd;
        }
    }
}
