// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaTypes } from "../types/ArcadiaTypes.sol";

/// @notice Small fixed point math library used by the protocol accounting layer.
library FixedPointMath {
    uint256 internal constant WAD = ArcadiaTypes.WAD;
    uint256 internal constant BPS = ArcadiaTypes.BPS;

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function zeroFloorSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return ((a - 1) / b) + 1;
    }

    function mulDivDown(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 z)
    {
        assembly ("memory-safe") {
            if iszero(denominator) { revert(0, 0) }
            let mm := mulmod(x, y, not(0))
            let prod0 := mul(x, y)
            let prod1 := sub(sub(mm, prod0), lt(mm, prod0))

            if iszero(prod1) {
                z := div(prod0, denominator)
            }

            if prod1 {
                if iszero(gt(denominator, prod1)) { revert(0, 0) }
                let remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
                let twos := and(denominator, sub(0, denominator))
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
                prod0 := or(prod0, mul(prod1, twos))

                let inverse := xor(mul(3, denominator), 2)
                inverse := mul(inverse, sub(2, mul(denominator, inverse)))
                inverse := mul(inverse, sub(2, mul(denominator, inverse)))
                inverse := mul(inverse, sub(2, mul(denominator, inverse)))
                inverse := mul(inverse, sub(2, mul(denominator, inverse)))
                inverse := mul(inverse, sub(2, mul(denominator, inverse)))
                inverse := mul(inverse, sub(2, mul(denominator, inverse)))
                z := mul(prod0, inverse)
            }
        }
    }

    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        uint256 z = mulDivDown(x, y, denominator);
        if (mulmod(x, y, denominator) != 0) z += 1;
        return z;
    }

    function wadMul(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    function wadDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    function bpsOf(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return mulDivDown(amount, bps, BPS);
    }

    function bpsOfUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return mulDivUp(amount, bps, BPS);
    }

    function ratioBps(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return 0;
        return mulDivDown(numerator, BPS, denominator);
    }

    function pricePerShare(uint256 assets, uint256 shares) internal pure returns (uint256) {
        if (shares == 0) return WAD;
        return mulDivDown(assets, WAD, shares);
    }

    function sharesForAssets(uint256 assets, uint256 priceWad) internal pure returns (uint256) {
        if (assets == 0) return 0;
        return mulDivDown(assets, WAD, priceWad);
    }

    function assetsForShares(uint256 shares, uint256 priceWad) internal pure returns (uint256) {
        if (shares == 0) return 0;
        return mulDivDown(shares, priceWad, WAD);
    }
}
