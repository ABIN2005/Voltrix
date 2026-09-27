// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol Base Sepolia fork rehearsal added 2026-09-26.

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/contracts/libs/TakerTraits.sol";
import { MockTaker } from "@1inch/swap-vm/test/solidity/mocks/MockTaker.sol";

import { BaseSepoliaConfig } from "../../src/deployment/BaseSepoliaConfig.sol";
import { BaseSepoliaPreflight } from "../../src/deployment/BaseSepoliaPreflight.sol";
import { UniswapV3DeploymentMath } from "../../src/deployment/UniswapV3DeploymentMath.sol";
import {
    INonfungiblePositionManagerMinimal,
    ISwapRouter02Minimal,
    IUniswapV3PoolDeployment,
    IWETH9Minimal
} from "../../src/deployment/interfaces/IUniswapV3Deployment.sol";
import { VolatilityRegistry } from "../../src/oracles/VolatilityRegistry.sol";
import { UniswapV3TwapOracle } from "../../src/oracles/uniswap/UniswapV3TwapOracle.sol";
import { OptionSeries } from "../../src/options/OptionSeries.sol";
import { AquaVolFairValue } from "../../src/swapvm/AquaVolFairValue.sol";
import { AquaVolInventorySkew } from "../../src/swapvm/AquaVolInventorySkew.sol";
import { AquaVolSwapVMRouter } from "../../src/swapvm/AquaVolSwapVMRouter.sol";
import { AquaVolPricingEngine } from "../../src/swapvm/AquaVolPricingEngine.sol";
import { AquaVolDemoUSDC } from "../../src/tokens/AquaVolDemoUSDC.sol";

interface DeploymentRehearsalVm {
    function createSelectFork(string calldata urlOrAlias, uint256 blockNumber)
        external
        returns (uint256 forkId);

    function deal(address account, uint256 newBalance) external;

    function envOr(string calldata name, bool defaultValue) external view returns (bool value);

    function envString(string calldata name) external view returns (string memory value);

    function warp(uint256 newTimestamp) external;
}

/// @notice Opt-in rehearsal of the complete AquaVol deployment on a pinned Base Sepolia fork.
/// @dev Every state change is local to the disposable fork. This test never broadcasts.
contract BaseSepoliaDeploymentRehearsalTest {
    DeploymentRehearsalVm private constant VM =
        DeploymentRehearsalVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant FORK_BLOCK = 47_324_978;
    uint256 private constant OPERATOR_ETH = 20 ether;
    uint256 private constant POOL_WETH = 1 ether;
    uint256 private constant POOL_QUOTE = 3_800e6;
    uint256 private constant INITIAL_CALL = 10e18;
    uint256 private constant INITIAL_QUOTE = 5_000e6;
    uint256 private constant ONE_CALL = 1e18;
    uint256 private constant STRIKE_WAD = 4_000e18;
    uint256 private constant VOLATILITY_WAD = 0.64e18;
    uint256 private constant GAMMA_WAD = 0.2e18;
    uint256 private constant HALF_SPREAD_WAD = 0.01e18;
    uint256 private constant SWAP_TO_WRITE_OBSERVATION = 1e6;
    uint32 private constant MAXIMUM_OBSERVATION_AGE = 2 minutes;
    uint24 private constant MAXIMUM_TICK_DEVIATION = 500;
    int24 private constant MIN_FULL_RANGE_TICK = -887_220;
    int24 private constant MAX_FULL_RANGE_TICK = 887_220;

    AquaVolDemoUSDC private quote;
    IWETH9Minimal private weth;
    Aqua private aqua;
    AquaVolSwapVMRouter private router;
    MockTaker private taker;
    OptionSeries private series;
    UniswapV3TwapOracle private oracle;
    VolatilityRegistry private registry;
    ISwapVM.Order private order;
    bytes32 private strategyHash;

    event log_string(string value);
    event log_named_address(string key, address value);
    event log_named_bytes32(string key, bytes32 value);
    event log_named_uint(string key, uint256 value);

    function testPinnedForkRehearsesCompleteDeploymentAndTrade() public {
        if (!VM.envOr("RUN_BASE_SEPOLIA_REHEARSAL", false)) {
            emit log_string("Base Sepolia deployment rehearsal skipped (explicit opt-in required)");
            return;
        }

        VM.createSelectFork(VM.envString("BASE_SEPOLIA_RPC_URL"), FORK_BLOCK);
        VM.deal(address(this), OPERATOR_ETH);

        BaseSepoliaConfig.ExternalContracts memory externalContracts =
            BaseSepoliaConfig.officialContracts();
        BaseSepoliaPreflight.Report memory preflight =
            BaseSepoliaPreflight.validate(address(this), 0.01 ether, externalContracts);
        require(preflight.chainId == BaseSepoliaConfig.CHAIN_ID, "preflight chain");

        weth = IWETH9Minimal(externalContracts.weth);
        quote = new AquaVolDemoUSDC(address(this));
        address pool = _bootstrapSpotMarket(externalContracts);
        _matureObservation(externalContracts, pool);

        oracle = new UniswapV3TwapOracle(
            externalContracts.factory,
            pool,
            address(weth),
            address(quote),
            BaseSepoliaConfig.POOL_FEE,
            BaseSepoliaConfig.TWAP_WINDOW,
            1,
            MAXIMUM_OBSERVATION_AGE,
            MAXIMUM_TICK_DEVIATION
        );
        UniswapV3TwapOracle.Observation memory spot = oracle.read();
        require(spot.priceWad > 3_700e18 && spot.priceWad < 3_900e18, "unexpected TWAP");

        _deployPosition();
        uint256 firstQuote = _quoteBuy(ONE_CALL);
        quote.mint(address(taker), firstQuote);
        (uint256 paid, uint256 received) = taker.swap(
            order, ONE_CALL, _takerData(address(quote), firstQuote, block.timestamp + 60)
        );
        uint256 nextQuote = _quoteBuy(ONE_CALL);

        require(paid == firstQuote, "trade input");
        require(received == ONE_CALL, "trade output");
        require(nextQuote > firstQuote, "inventory did not reprice");
        require(series.balanceOf(address(taker)) == ONE_CALL, "trader CALL");
        require(quote.balanceOf(address(taker)) == 0, "trader quote");
        require(weth.balanceOf(address(series)) == INITIAL_CALL, "collateral moved");
        require(series.totalSupply() == INITIAL_CALL, "CALL supply changed");
        require(router.hash(order) == strategyHash, "strategy changed");

        (uint256 virtualCall, uint256 virtualQuote) = aqua.safeBalances(
            address(this), address(router), strategyHash, address(series), address(quote)
        );
        require(virtualCall == INITIAL_CALL - ONE_CALL, "virtual CALL");
        require(virtualQuote == INITIAL_QUOTE + firstQuote, "virtual quote");

        _emitSummary(pool, spot.priceWad, firstQuote, nextQuote, virtualCall, virtualQuote);
    }

    function _bootstrapSpotMarket(BaseSepoliaConfig.ExternalContracts memory externalContracts)
        private
        returns (address pool)
    {
        weth.deposit{ value: 12 ether }();
        quote.mint(address(this), 9_000e6);

        address token0 = address(weth) < address(quote) ? address(weth) : address(quote);
        address token1 = address(weth) < address(quote) ? address(quote) : address(weth);
        uint256 amount0ForPrice = token0 == address(weth) ? 1e18 : 3_800e6;
        uint256 amount1ForPrice = token1 == address(quote) ? 3_800e6 : 1e18;
        uint160 sqrtPriceX96 =
            UniswapV3DeploymentMath.encodeSqrtRatioX96(amount1ForPrice, amount0ForPrice);

        INonfungiblePositionManagerMinimal manager =
            INonfungiblePositionManagerMinimal(externalContracts.positionManager);
        pool = manager.createAndInitializePoolIfNecessary(
            token0, token1, BaseSepoliaConfig.POOL_FEE, sqrtPriceX96
        );
        IUniswapV3PoolDeployment(pool).increaseObservationCardinalityNext(16);

        require(weth.approve(address(manager), POOL_WETH), "WETH approval");
        require(quote.approve(address(manager), POOL_QUOTE), "quote approval");

        uint256 amount0Desired = token0 == address(weth) ? POOL_WETH : POOL_QUOTE;
        uint256 amount1Desired = token1 == address(quote) ? POOL_QUOTE : POOL_WETH;
        (, uint128 liquidity, uint256 amount0, uint256 amount1) = manager.mint(
            INonfungiblePositionManagerMinimal.MintParams({
                token0: token0,
                token1: token1,
                fee: BaseSepoliaConfig.POOL_FEE,
                tickLower: MIN_FULL_RANGE_TICK,
                tickUpper: MAX_FULL_RANGE_TICK,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 60
            })
        );
        require(liquidity != 0, "zero minted liquidity");
        require(amount0 != 0 && amount1 != 0, "one-sided initial liquidity");
    }

    function _matureObservation(
        BaseSepoliaConfig.ExternalContracts memory externalContracts,
        address pool
    ) private {
        VM.warp(block.timestamp + BaseSepoliaConfig.TWAP_WINDOW);
        require(
            quote.approve(externalContracts.swapRouter, SWAP_TO_WRITE_OBSERVATION),
            "router approval"
        );
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 amountOut = ISwapRouter02Minimal(externalContracts.swapRouter)
            .exactInputSingle(
                ISwapRouter02Minimal.ExactInputSingleParams({
                    tokenIn: address(quote),
                    tokenOut: address(weth),
                    fee: BaseSepoliaConfig.POOL_FEE,
                    recipient: address(this),
                    amountIn: SWAP_TO_WRITE_OBSERVATION,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        require(amountOut != 0, "observation swap output");
        require(weth.balanceOf(address(this)) == wethBefore + amountOut, "observation swap balance");

        // The pool is used by the oracle constructor immediately after this write.
        require(pool.code.length != 0, "pool disappeared");
    }

    function _deployPosition() private {
        aqua = new Aqua();
        AquaVolPricingEngine pricingEngine = new AquaVolPricingEngine();
        router = new AquaVolSwapVMRouter(
            address(aqua),
            address(weth),
            address(this),
            address(pricingEngine),
            "AquaVol SwapVM",
            "1"
        );
        taker = new MockTaker(aqua, router, address(this));
        registry = new VolatilityRegistry(address(this));
        series = new OptionSeries(
            address(this),
            address(weth),
            address(quote),
            STRIKE_WAD,
            block.timestamp + 7 days,
            24 hours,
            "AquaVol WETH 4000 Call",
            "avWETH-4000-C"
        );
        registry.setVolatility(address(series), VOLATILITY_WAD);

        require(weth.approve(address(series), INITIAL_CALL), "series WETH approval");
        series.write(INITIAL_CALL);
        require(series.approve(address(aqua), type(uint256).max), "CALL Aqua approval");
        require(quote.approve(address(aqua), type(uint256).max), "quote Aqua approval");

        order = _buildOrder();
        strategyHash = _ship(order);
    }

    function _buildOrder() private view returns (ISwapVM.Order memory) {
        bytes memory program = bytes.concat(
            AquaVolFairValue.build(
                address(series), address(quote), address(oracle), address(registry), 1 hours
            ),
            AquaVolInventorySkew.build(
                address(series),
                address(quote),
                address(oracle),
                INITIAL_CALL,
                GAMMA_WAD,
                HALF_SPREAD_WAD
            ),
            Salt.build(uint64(4))
        );
        (address tokenA, address tokenB) = _sortedTokens();
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: address(this),
                receiver: address(0),
                tokenA: tokenA,
                tokenB: tokenB,
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                usePermit2: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );
    }

    function _ship(ISwapVM.Order memory shippedOrder) private returns (bytes32 shippedHash) {
        (address tokenA, address tokenB) = _sortedTokens();
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        amounts[0] = tokenA == address(series) ? INITIAL_CALL : INITIAL_QUOTE;
        amounts[1] = tokenB == address(series) ? INITIAL_CALL : INITIAL_QUOTE;

        shippedHash = aqua.ship(address(router), abi.encode(shippedOrder), tokens, amounts);
        require(shippedHash == router.hash(shippedOrder), "ship/hash mismatch");
    }

    function _quoteBuy(uint256 quantity) private view returns (uint256 quoteAmount) {
        uint256 callAmount;
        bytes32 quotedHash;
        (quoteAmount, callAmount, quotedHash) = router.asView()
            .quote(order, quantity, _takerData(address(quote), 0, block.timestamp + 60));
        require(callAmount == quantity, "quoted CALL changed");
        require(quotedHash == strategyHash, "quoted strategy hash");
    }

    function _takerData(address tokenIn, uint256 threshold, uint256 deadline)
        private
        view
        returns (bytes memory)
    {
        (address tokenA,) = _sortedTokens();
        require(deadline <= type(uint40).max, "deadline overflow");
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: false,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                isAToB: tokenIn == tokenA,
                allowPartialFill: false,
                usePermit2: false,
                threshold: threshold == 0 ? bytes("") : abi.encode(threshold),
                to: address(0),
                // The preceding bound check makes this narrowing conversion safe.
                // forge-lint: disable-next-line(unsafe-typecast)
                deadline: uint40(deadline),
                hasPreTransferInCallback: true,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }

    function _sortedTokens() private view returns (address tokenA, address tokenB) {
        tokenA = address(series);
        tokenB = address(quote);
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    }

    function _emitSummary(
        address pool,
        uint256 spotPriceWad,
        uint256 firstQuote,
        uint256 nextQuote,
        uint256 virtualCall,
        uint256 virtualQuote
    ) private {
        emit log_named_uint("pinned Base Sepolia block", FORK_BLOCK);
        emit log_named_address("DemoUSDC", address(quote));
        emit log_named_address("WETH/DemoUSDC pool", pool);
        emit log_named_address("Uniswap TWAP oracle", address(oracle));
        emit log_named_address("OptionSeries", address(series));
        emit log_named_address("official Aqua", address(aqua));
        emit log_named_address("AquaVol SwapVM router", address(router));
        emit log_named_bytes32("strategy hash", strategyHash);
        emit log_named_uint("TWAP price WAD", spotPriceWad);
        emit log_named_uint("first one-CALL ask", firstQuote);
        emit log_named_uint("next one-CALL ask", nextQuote);
        emit log_named_uint("post-trade virtual CALL", virtualCall);
        emit log_named_uint("post-trade virtual quote", virtualQuote);
        emit log_string("All deployments and transactions above exist only on the local fork");
    }
}
