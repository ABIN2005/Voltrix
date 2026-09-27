// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { AquaSwapVMRouter } from "@1inch/swap-vm/contracts/routers/AquaSwapVMRouter.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { XYCSwap } from "@1inch/swap-vm/contracts/instructions/XYCSwap.sol";
import { Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/contracts/libs/TakerTraits.sol";
import { MockTaker } from "@1inch/swap-vm/test/solidity/mocks/MockTaker.sol";

import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { OptionSeries } from "../../src/options/OptionSeries.sol";

interface IntegrationVm {
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
}

/// @notice AquaVol-owned evidence for the pinned, unmodified Aqua/SwapVM path.
/// @dev Aqua — © Degensoft Ltd 2025. SwapVM — © Degensoft Ltd 2025.
contract AquaSwapVMBaselineTest {
    IntegrationVm private constant VM =
        IntegrationVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant INITIAL_CALL = 10e18;
    uint256 private constant INITIAL_USDC = 5_000e6;
    uint256 private constant CALL_TO_BUY = 1e18;
    address private constant WRITER = address(0xA11CE);

    Aqua private aqua;
    AquaSwapVMRouter private router;
    MockTaker private taker;
    MockERC20 private weth;
    MockERC20 private usdc;
    OptionSeries private series;
    ISwapVM.Order private order;
    bytes32 private strategyHash;

    function setUp() public {
        aqua = new Aqua();
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        router = new AquaSwapVMRouter(
            address(aqua), address(weth), address(this), "AquaVol SwapVM", "1"
        );
        taker = new MockTaker(aqua, router, address(this));

        series = new OptionSeries(
            WRITER,
            address(weth),
            address(usdc),
            4_000e18,
            block.timestamp + 7 days,
            24 hours,
            "AquaVol WETH 4000 Call",
            "avWETH-4000-C"
        );

        weth.mint(WRITER, INITIAL_CALL);
        usdc.mint(WRITER, INITIAL_USDC);
        VM.startPrank(WRITER);
        weth.approve(address(series), type(uint256).max);
        series.write(INITIAL_CALL);
        series.approve(address(aqua), type(uint256).max);
        usdc.approve(address(aqua), type(uint256).max);
        VM.stopPrank();

        order = _buildOrder();
        strategyHash = _ship(order);
    }

    function testExactOutputCallBuyReconcilesRealAndVirtualBalances() public {
        bytes memory quoteData = _takerData(0, block.timestamp + 60);
        (uint256 quotedUsdc, uint256 quotedCall, bytes32 quotedHash) =
            router.asView().quote(order, CALL_TO_BUY, quoteData);
        require(quotedUsdc == 555_555_556, "unexpected baseline quote");
        require(quotedCall == CALL_TO_BUY, "wrong quoted CALL");
        require(quotedHash == strategyHash, "wrong quoted strategy hash");

        usdc.mint(address(taker), quotedUsdc);
        uint256 collateralBefore = weth.balanceOf(address(series));
        bytes memory executionData = _takerData(quotedUsdc, block.timestamp + 60);

        (uint256 paidUsdc, uint256 receivedCall) = taker.swap(order, CALL_TO_BUY, executionData);

        require(paidUsdc == quotedUsdc, "quote and swap input differ");
        require(receivedCall == quotedCall, "quote and swap output differ");
        require(usdc.balanceOf(address(taker)) == 0, "trader USDC delta");
        require(series.balanceOf(address(taker)) == CALL_TO_BUY, "trader CALL delta");
        require(usdc.balanceOf(WRITER) == INITIAL_USDC + quotedUsdc, "maker USDC delta");
        require(series.balanceOf(WRITER) == INITIAL_CALL - CALL_TO_BUY, "maker CALL delta");

        (uint256 virtualCall, uint256 virtualUsdc) = _virtualBalances();
        require(virtualCall == INITIAL_CALL - CALL_TO_BUY, "virtual CALL delta");
        require(virtualUsdc == INITIAL_USDC + quotedUsdc, "virtual USDC delta");
        require(weth.balanceOf(address(series)) == collateralBefore, "collateral moved");
        require(weth.balanceOf(address(series)) == series.totalSupply(), "backing changed");
    }

    function testAlteredStrategyBytesCannotUseShippedBalances() public {
        ISwapVM.Order memory alteredOrder = order;
        alteredOrder.data = bytes.concat(order.data, hex"00");
        bytes memory takerData = _takerData(type(uint256).max, block.timestamp + 60);
        usdc.mint(address(taker), INITIAL_USDC);

        uint256 writerCallBefore = series.balanceOf(WRITER);
        uint256 writerUsdcBefore = usdc.balanceOf(WRITER);
        try taker.swap(alteredOrder, CALL_TO_BUY, takerData) {
            revert("altered strategy executed");
        } catch { }

        require(series.balanceOf(WRITER) == writerCallBefore, "maker CALL changed");
        require(usdc.balanceOf(WRITER) == writerUsdcBefore, "maker USDC changed");
        (uint256 virtualCall, uint256 virtualUsdc) = _virtualBalances();
        require(virtualCall == INITIAL_CALL, "virtual CALL changed");
        require(virtualUsdc == INITIAL_USDC, "virtual USDC changed");
    }

    function testInsufficientCallLiquidityRevertsWithoutPartialSettlement() public {
        uint256 excessiveCall = INITIAL_CALL + 1;
        bytes memory takerData = _takerData(type(uint256).max, block.timestamp + 60);
        usdc.mint(address(taker), INITIAL_USDC * 10);

        uint256 collateralBefore = weth.balanceOf(address(series));
        uint256 traderUsdcBefore = usdc.balanceOf(address(taker));
        try taker.swap(order, excessiveCall, takerData) {
            revert("excessive swap executed");
        } catch { }

        require(usdc.balanceOf(address(taker)) == traderUsdcBefore, "trader USDC changed");
        require(series.balanceOf(address(taker)) == 0, "trader received CALL");
        require(weth.balanceOf(address(series)) == collateralBefore, "collateral changed");
        (uint256 virtualCall, uint256 virtualUsdc) = _virtualBalances();
        require(virtualCall == INITIAL_CALL, "virtual CALL changed");
        require(virtualUsdc == INITIAL_USDC, "virtual USDC changed");
    }

    function _buildOrder() private view returns (ISwapVM.Order memory) {
        (address tokenA, address tokenB) = _sortedTokens();
        bytes memory program = bytes.concat(XYCSwap.build(), Salt.build(uint64(1)));
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: WRITER,
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
        amounts[0] = tokenA == address(series) ? INITIAL_CALL : INITIAL_USDC;
        amounts[1] = tokenB == address(series) ? INITIAL_CALL : INITIAL_USDC;

        VM.prank(WRITER);
        shippedHash = aqua.ship(address(router), abi.encode(shippedOrder), tokens, amounts);
        require(shippedHash == router.hash(shippedOrder), "ship/hash bytes differ");
    }

    function _takerData(uint256 maxUsdc, uint256 deadline) private view returns (bytes memory) {
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
                isAToB: tokenA == address(usdc),
                allowPartialFill: false,
                usePermit2: false,
                threshold: maxUsdc == 0 ? bytes("") : abi.encode(maxUsdc),
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
        tokenB = address(usdc);
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    }

    function _virtualBalances() private view returns (uint256 callBalance, uint256 usdcBalance) {
        return
            aqua.safeBalances(WRITER, address(router), strategyHash, address(series), address(usdc));
    }
}
