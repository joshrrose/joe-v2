// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";
import "src/libraries/Math512Bits.sol";

contract LiquidityBinPairFeesTest is TestHelper {
    using Math512Bits for uint256;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(ILBFactory(DEV), IJoeFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testClaimFeesY() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 5, 0);

        (uint256 amountYInForSwap, uint256 feesFromGetSwapIn) = router.getSwapIn(pair, amountXOutForSwap, false);

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(false, DEV);

        (, uint256 feesYTotal, , uint256 feesYProtocol) = pair.getGlobalFees();
        assertEq(feesYTotal, feesFromGetSwapIn);

        uint256 accumulatedYFees = feesYTotal - feesYProtocol;

        uint256[] memory orderedIds = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            orderedIds[i] = startId - 2 + i;
        }

        (uint256 feeX, uint256 feeY) = pair.pendingFees(DEV, orderedIds);

        assertApproxEqAbs(accumulatedYFees, feeY, 1);

        uint256 balanceBefore = token18D.balanceOf(DEV);
        pair.collectFees(DEV, orderedIds);
        assertEq(feeY, token18D.balanceOf(DEV) - balanceBefore);

        // Trying to claim a second time
        balanceBefore = token18D.balanceOf(DEV);
        (feeX, feeY) = pair.pendingFees(DEV, orderedIds);
        assertEq(feeY, 0);

        (feeX, feeY) = pair.pendingFees(address(0), orderedIds);
        assertEq(feeY, 0);
        assertEq(feeX, 0);
        (feeX, feeY) = pair.pendingFees(address(pair), orderedIds);
        assertEq(feeY, 0);
        assertEq(feeX, 0);

        pair.collectFees(DEV, orderedIds);
        assertEq(token18D.balanceOf(DEV), balanceBefore);
    }

    function testClaimFeesX() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYOutForSwap = 1e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 5, 0);

        (uint256 amountXInForSwap, uint256 feesFromGetSwapIn) = router.getSwapIn(pair, amountYOutForSwap, true);

        token6D.mint(address(pair), amountXInForSwap);
        vm.prank(ALICE);
        pair.swap(true, DEV);

        (uint256 feesXTotal, , uint256 feesXProtocol, ) = pair.getGlobalFees();
        assertEq(feesXTotal, feesFromGetSwapIn);
        uint256 accumulatedXFees = feesXTotal - feesXProtocol;

        uint256[] memory orderedIds = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            orderedIds[i] = startId - 2 + i;
        }

        (uint256 feeX, uint256 feeY) = pair.pendingFees(DEV, orderedIds);

        assertApproxEqAbs(accumulatedXFees, feeX, 1);

        uint256 balanceBefore = token6D.balanceOf(DEV);
        pair.collectFees(DEV, orderedIds);
        assertEq(feeX, token6D.balanceOf(DEV) - balanceBefore);

        // Trying to claim a second time
        balanceBefore = token6D.balanceOf(DEV);
        (feeX, feeY) = pair.pendingFees(DEV, orderedIds);
        assertEq(feeX, 0);

        (feeX, feeY) = pair.pendingFees(address(0), orderedIds);
        assertEq(feeY, 0);
        assertEq(feeX, 0);

        (feeX, feeY) = pair.pendingFees(address(pair), orderedIds);
        assertEq(feeY, 0);
        assertEq(feeX, 0);

        pair.collectFees(DEV, orderedIds);
        assertEq(token6D.balanceOf(DEV), balanceBefore);
    }

    function testFeesOnTokenTransfer() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYForSwap = 1e6;
        uint24 startId = ID_ONE;

        (uint256[] memory _ids, , , ) = addLiquidity(amountYInLiquidity, startId, 5, 0);

        token18D.mint(address(pair), amountYForSwap);

        pair.swap(false, ALICE);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }

        pair.safeBatchTransferFrom(DEV, BOB, _ids, amounts);

        token18D.mint(address(pair), amountYForSwap);
        pair.swap(false, ALICE);

        (uint256 feesForDevX, uint256 feesForDevY) = pair.pendingFees(DEV, _ids);
        (uint256 feesForBobX, uint256 feesForBobY) = pair.pendingFees(BOB, _ids);

        assertGt(feesForDevY, 0, "DEV should have fees on token Y");
        assertGt(feesForBobY, 0, "BOB should also have fees on token Y");

        (, uint256 feesYTotal, , uint256 feesYProtocol) = pair.getGlobalFees();

        uint256 accumulatedYFees = feesYTotal - feesYProtocol;

        assertApproxEqAbs(feesForDevY + feesForBobY, accumulatedYFees, 1, "Sum of users fees = accumulated fees");

        uint256 balanceBefore = token18D.balanceOf(DEV);
        pair.collectFees(DEV, _ids);
        assertEq(
            feesForDevY,
            token18D.balanceOf(DEV) - balanceBefore,
            "DEV gets the expected amount when withdrawing fees"
        );

        balanceBefore = token18D.balanceOf(BOB);
        pair.collectFees(BOB, _ids);
        assertEq(
            feesForBobY,
            token18D.balanceOf(BOB) - balanceBefore,
            "BOB gets the expected amount when withdrawing fees"
        );
    }

    struct FeeInfo {
        uint256 feeXTotal;
        uint256 feeYTotal;
        uint256 feeXProtocol;
        uint256 feeYProtocol;
    }

    function _getGlobalFees() internal view returns (FeeInfo memory) {
        (uint256 feesXTotal, uint256 feesYTotal, uint256 feesXProtocol, uint256 feesYProtocol) = pair.getGlobalFees();
        return FeeInfo(feesXTotal, feesYTotal, feesXProtocol, feesYProtocol);
    }

    function testClaimProtocolFees() public {
        addLiquidity(100e18, ID_ONE, 5, 0);

        // Add Y fees
        (uint256 amountIn, uint256 feesIn) = router.getSwapIn(pair, 1e6, false);
        token18D.mint(address(pair), amountIn);

        vm.prank(ALICE);
        pair.swap(false, DEV);

        // Claiming rewards for Y
        FeeInfo memory feesBefore = _getGlobalFees();

        assertEq(feesBefore.feeXTotal, 0);
        assertEq(feesBefore.feeXProtocol, 0);

        assertGt(feesBefore.feeYTotal, 0);
        assertEq(feesBefore.feeYTotal, feesIn);

        assertGt(feesBefore.feeYProtocol, 0);
        assertLt(feesBefore.feeYProtocol, feesBefore.feeYTotal);

        address protocolFeesReceiver = factory.feeRecipient();
        uint256 balanceBefore = token18D.balanceOf(protocolFeesReceiver);

        vm.prank(protocolFeesReceiver);
        pair.collectProtocolFees();

        assertEq(token18D.balanceOf(protocolFeesReceiver) - balanceBefore, feesBefore.feeYProtocol - 1);

        FeeInfo memory feesAfter = _getGlobalFees();

        assertEq(feesAfter.feeXTotal, 0);
        assertEq(feesAfter.feeXProtocol, 0);

        assertGt(feesAfter.feeYTotal, 0);
        assertEq(feesAfter.feeYTotal, feesBefore.feeYTotal - (feesBefore.feeYProtocol - 1));
        assertEq(feesAfter.feeYProtocol, 1);

        // Claiming twice
        pair.collectProtocolFees();
        assertEq(token18D.balanceOf(protocolFeesReceiver) - balanceBefore, feesBefore.feeYProtocol - 1);

        FeeInfo memory feesAfter2 = _getGlobalFees();

        assertEq(feesAfter2.feeXTotal, feesAfter.feeXTotal);
        assertEq(feesAfter2.feeXProtocol, feesAfter.feeXProtocol);

        assertEq(feesAfter2.feeYTotal, feesAfter.feeYTotal);
        assertEq(feesAfter2.feeYProtocol, feesAfter.feeYProtocol);

        // Add X fees
        (amountIn, feesIn) = router.getSwapIn(pair, 1e18, true);
        token6D.mint(address(pair), amountIn);

        vm.prank(ALICE);
        pair.swap(true, DEV);

        // Claiming rewards for X
        feesBefore = _getGlobalFees();

        assertEq(feesBefore.feeYTotal, feesAfter2.feeYTotal);
        assertEq(feesBefore.feeYProtocol, feesAfter2.feeYProtocol);

        assertGt(feesBefore.feeXTotal, 0);
        assertEq(feesBefore.feeXTotal, feesIn);

        assertGt(feesBefore.feeXProtocol, 0);
        assertLt(feesBefore.feeXProtocol, feesBefore.feeXTotal);

        balanceBefore = token6D.balanceOf(protocolFeesReceiver);

        vm.prank(protocolFeesReceiver);
        pair.collectProtocolFees();

        assertEq(token6D.balanceOf(protocolFeesReceiver) - balanceBefore, feesBefore.feeXProtocol - 1);

        feesAfter = _getGlobalFees();

        assertEq(feesAfter.feeYTotal, feesBefore.feeYTotal);
        assertEq(feesAfter.feeYProtocol, feesBefore.feeYProtocol);

        assertGt(feesAfter.feeXTotal, 0);
        assertEq(feesAfter.feeXTotal, feesBefore.feeXTotal - (feesBefore.feeXProtocol - 1));

        assertGt(feesAfter.feeXProtocol, 0);
        assertEq(feesAfter.feeXProtocol, 1);

        // Claiming twice
        pair.collectProtocolFees();
        assertEq(token6D.balanceOf(protocolFeesReceiver) - balanceBefore, feesBefore.feeXProtocol - 1);

        FeeInfo memory feesAfter2X = _getGlobalFees();

        assertEq(feesAfter2X.feeXTotal, feesAfter.feeXTotal);
        assertEq(feesAfter2X.feeXProtocol, feesAfter.feeXProtocol);

        assertEq(feesAfter2X.feeXTotal, feesAfter.feeXTotal);
        assertEq(feesAfter2X.feeXProtocol, feesAfter.feeXProtocol);

        assertEq(feesAfter2X.feeYTotal, feesAfter.feeYTotal);
        assertEq(feesAfter2X.feeYProtocol, feesAfter.feeYProtocol);
    }

    function testForceDecay() public {
        uint256 amountYInLiquidity = 100e18;
        uint24 startId = ID_ONE;

        FeeHelper.FeeParameters memory _feeParameters = pair.feeParameters();
        addLiquidity(amountYInLiquidity, startId, 51, 5);

        (uint256 amountYInForSwap, ) = router.getSwapIn(pair, amountYInLiquidity / 4, true);
        token6D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(true, ALICE);

        vm.warp(block.timestamp + 90);

        (amountYInForSwap, ) = router.getSwapIn(pair, amountYInLiquidity / 4, true);
        token6D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(true, ALICE);

        _feeParameters = pair.feeParameters();
        uint256 referenceBeforeForceDecay = _feeParameters.volatilityReference;
        uint256 referenceAfterForceDecayExpected = (uint256(_feeParameters.reductionFactor) *
            referenceBeforeForceDecay) / Constants.BASIS_POINT_MAX;

        factory.forceDecay(pair);

        _feeParameters = pair.feeParameters();
        uint256 referenceAfterForceDecay = _feeParameters.volatilityReference;
        assertEq(referenceAfterForceDecay, referenceAfterForceDecayExpected);
    }

    function testClaimFeesComplex(uint256 amountY, uint256 amountX) public {
        vm.assume(amountY < 10e18);
        vm.assume(amountY > 1);
        vm.assume(amountX < 10e18);
        vm.assume(amountX > 1);

        uint256 amountYInLiquidity = 100e18;
        uint256 totalFeesFromGetSwapX;
        uint256 totalFeesFromGetSwapY;

        addLiquidity(amountYInLiquidity, ID_ONE, 5, 0);

        //swap X -> Y and accrue X fees
        (uint256 amountXInForSwap, uint256 feesXFromGetSwap) = router.getSwapIn(pair, amountY, true);
        totalFeesFromGetSwapX += feesXFromGetSwap;

        token6D.mint(address(pair), amountXInForSwap);
        vm.prank(ALICE);
        pair.swap(true, DEV);
        (uint256 feesXTotal, , uint256 feesXProtocol, ) = pair.getGlobalFees();
        assertEq(feesXTotal, totalFeesFromGetSwapX);

        //swap Y -> X and accrue Y fees
        (uint256 amountYInForSwap, uint256 feesYFromGetSwap) = router.getSwapIn(pair, amountX, false);
        totalFeesFromGetSwapY += feesYFromGetSwap;
        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(false, DEV);

        (, uint256 feesYTotal, , uint256 feesYProtocol) = pair.getGlobalFees();
        assertEq(feesYTotal, totalFeesFromGetSwapY);

        //swap Y -> X and accrue Y fees
        (, feesYFromGetSwap) = router.getSwapOut(pair, amountY, false);
        totalFeesFromGetSwapY += feesYFromGetSwap;
        token18D.mint(address(pair), amountY);
        vm.prank(ALICE);
        pair.swap(false, DEV);

        (, feesYTotal, , feesYProtocol) = pair.getGlobalFees();
        assertEq(feesYTotal, totalFeesFromGetSwapY);

        //swap X -> Y and accrue X fees
        (, feesXFromGetSwap) = router.getSwapOut(pair, amountX, true);
        totalFeesFromGetSwapX += feesXFromGetSwap;
        token6D.mint(address(pair), amountX);
        vm.prank(ALICE);
        pair.swap(true, DEV);

        (feesXTotal, , feesXProtocol, ) = pair.getGlobalFees();
        assertEq(feesXTotal, totalFeesFromGetSwapX);
    }

    function testFeesForPairOrZeroAddress() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e18;
        uint256 amountYOutForSwap = 1e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 5, 0);

        (uint256 amountYInForSwap, ) = router.getSwapIn(pair, amountXOutForSwap, false);

        // setup non-zero Y fees
        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(false, DEV);

        // setup non-zero X fees
        (uint256 amountXInForSwap, ) = router.getSwapIn(pair, amountYOutForSwap, true);
        token6D.mint(address(pair), amountXInForSwap);
        vm.prank(ALICE);
        pair.swap(true, DEV);

        uint256[] memory orderedIds = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            orderedIds[i] = startId - 2 + i;
        }

        (uint256 feeX, uint256 feeY) = pair.pendingFees(DEV, orderedIds);
        assertGt(feeY, 0);
        (feeX, feeY) = pair.pendingFees(address(0), orderedIds);
        assertEq(feeY, 0);
        assertEq(feeX, 0);
        (feeX, feeY) = pair.pendingFees(address(pair), orderedIds);
        assertEq(feeY, 0);
        assertEq(feeX, 0);

        vm.expectRevert(LBPair__AddressZeroOrThis.selector);
        pair.collectFees(address(pair), orderedIds);
        vm.expectRevert(LBPair__AddressZeroOrThis.selector);
        pair.collectFees(address(0), orderedIds);

        pair.collectFees(DEV, orderedIds);
    }
}
