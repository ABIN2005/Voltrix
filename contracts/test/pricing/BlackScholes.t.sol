// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BlackScholes } from "../../src/pricing/BlackScholes.sol";
import { NormalCDF } from "../../src/pricing/NormalCDF.sol";

interface PricingVm {
    function parseJsonString(string calldata json, string calldata key)
        external
        pure
        returns (string memory value);

    function parseJsonUint(string calldata json, string calldata key)
        external
        pure
        returns (uint256 value);

    function readFile(string calldata path) external view returns (string memory data);
}

contract PricingMathHarness {
    function cdf(int256 xWad) external pure returns (uint256) {
        return NormalCDF.cdf(xWad);
    }

    function callPrice(
        uint256 spotWad,
        uint256 strikeWad,
        uint256 timeSeconds,
        uint256 volatilityWad
    ) external pure returns (uint256) {
        return BlackScholes.callPrice(spotWad, strikeWad, timeSeconds, volatilityWad);
    }

    function calculate(
        uint256 spotWad,
        uint256 strikeWad,
        uint256 timeSeconds,
        uint256 volatilityWad
    ) external pure returns (BlackScholes.Result memory) {
        return BlackScholes.calculate(spotWad, strikeWad, timeSeconds, volatilityWad);
    }
}

contract BlackScholesTest {
    PricingVm private constant VM =
        PricingVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant WAD = 1e18;
    uint256 private constant MAX_PRICE_WAD = 1_000_000e18;
    uint256 private constant MIN_VOLATILITY_WAD = 0.0001e18;
    uint256 private constant MAX_VOLATILITY_WAD = 5e18;
    uint256 private constant MAX_TIME_SECONDS = 366 days;
    uint256 private constant ABSOLUTE_PRICE_TOLERANCE = 0.1e18;
    uint256 private constant CDF_TOLERANCE = 0.000002e18;

    PricingMathHarness private harness;
    string private vectors;

    function setUp() public {
        harness = new PricingMathHarness();
        vectors = VM.readFile("../test/vectors/black_scholes-v1.json");
    }

    function testConsumesCommittedCdfVectorsWithinTolerance() public view {
        for (uint256 i = 0; i < 7; ++i) {
            string memory prefix = string.concat(".cdf_cases[", _toString(i), "]");
            int256 xWad =
                _parseSignedDecimalWad(VM.parseJsonString(vectors, string.concat(prefix, ".x")));
            uint256 expectedWad = uint256(
                _parseSignedDecimalWad(
                    VM.parseJsonString(vectors, string.concat(prefix, ".expected"))
                )
            );
            uint256 actualWad = harness.cdf(xWad);
            require(_absoluteDifference(actualWad, expectedWad) <= CDF_TOLERANCE, "CDF error");
        }
    }

    function testConsumesAllCommittedCallVectorsWithinTolerance() public view {
        for (uint256 i = 0; i < 13; ++i) {
            string memory prefix = string.concat(".call_cases[", _toString(i), "]");
            uint256 spotWad = _parseUint(
                VM.parseJsonString(vectors, string.concat(prefix, ".normalized.spot_wad"))
            );
            uint256 strikeWad = _parseUint(
                VM.parseJsonString(vectors, string.concat(prefix, ".normalized.strike_wad"))
            );
            uint256 timeSeconds =
                VM.parseJsonUint(vectors, string.concat(prefix, ".inputs.time_seconds"));
            uint256 volatilityWad = _parseUint(
                VM.parseJsonString(vectors, string.concat(prefix, ".normalized.volatility_wad"))
            );
            uint256 expectedWad = _parseUint(
                VM.parseJsonString(vectors, string.concat(prefix, ".expected.call_value_wad"))
            );

            uint256 actualWad = harness.callPrice(spotWad, strikeWad, timeSeconds, volatilityWad);
            uint256 relativeTolerance = expectedWad / 1000; // 10 basis points.
            uint256 tolerance = relativeTolerance > ABSOLUTE_PRICE_TOLERANCE
                ? relativeTolerance
                : ABSOLUTE_PRICE_TOLERANCE;
            require(_absoluteDifference(actualWad, expectedWad) <= tolerance, "call error");
        }
    }

    function testCanonicalIntermediatesRemainCloseToReference() public view {
        BlackScholes.Result memory result = harness.calculate(3800e18, 4000e18, 7 days, 0.64e18);
        require(_absoluteSignedDifference(result.d1Wad, -0.534417527725e18) <= 1e7, "d1");
        require(_absoluteSignedDifference(result.d2Wad, -0.623047897609e18) <= 1e7, "d2");
        require(_absoluteDifference(result.cdfD1Wad, 0.296526347441e18) <= CDF_TOLERANCE, "cdf d1");
        require(_absoluteDifference(result.cdfD2Wad, 0.266626523401e18) <= CDF_TOLERANCE, "cdf d2");
    }

    function testCdfSaturatesAtTailsAndForExtremeIntegers() public view {
        require(harness.cdf(-8e18) == 0, "negative boundary");
        require(harness.cdf(8e18) == WAD, "positive boundary");
        require(harness.cdf(type(int256).min) == 0, "negative extreme");
        require(harness.cdf(type(int256).max) == WAD, "positive extreme");
    }

    function testFuzzCdfSymmetryAndRange(uint256 seed) public view {
        int256 xWad = int256(seed % (uint256(8e18) + 1));
        uint256 positive = harness.cdf(xWad);
        uint256 negative = harness.cdf(-xWad);
        require(positive <= WAD && negative <= WAD, "CDF range");
        require(_absoluteDifference(positive + negative, WAD) <= 1, "CDF symmetry");
    }

    function testFuzzCdfIsMonotonic(uint256 seedA, uint256 seedB) public view {
        int256 a = int256(seedA % (uint256(16e18) + 1)) - 8e18;
        int256 b = int256(seedB % (uint256(16e18) + 1)) - 8e18;
        if (a > b) (a, b) = (b, a);
        require(harness.cdf(a) <= harness.cdf(b), "CDF not monotonic");
    }

    function testZeroTimeAndZeroVolatilityReturnIntrinsicValue() public view {
        require(harness.callPrice(4500e18, 4000e18, 0, 0.64e18) == 500e18, "expiry ITM");
        require(harness.callPrice(3800e18, 4000e18, 0, 0.64e18) == 0, "expiry OTM");
        require(harness.callPrice(4500e18, 4000e18, 7 days, 0) == 500e18, "zero volatility ITM");
        require(harness.callPrice(3800e18, 4000e18, 7 days, 0) == 0, "zero volatility OTM");
    }

    function testAcceptsMaximumDomains() public view {
        uint256 premium =
            harness.callPrice(MAX_PRICE_WAD, MAX_PRICE_WAD, MAX_TIME_SECONDS, MAX_VOLATILITY_WAD);
        require(premium <= MAX_PRICE_WAD, "maximum premium");
    }

    function testAcceptsMinimumNonzeroDomains() public view {
        uint256 premium = harness.callPrice(1, 1, 1, MIN_VOLATILITY_WAD);
        require(premium <= 1, "minimum premium");
    }

    function testClampsUnderstoodApproximationShortfallToIntrinsic() public view {
        uint256 spotWad = 693_489_819_137_642_534_988_250;
        uint256 strikeWad = 693_240_919_226_679_868_131_296;
        uint256 intrinsicWad = spotWad - strikeWad;
        uint256 premiumWad =
            harness.callPrice(spotWad, strikeWad, 6_663_196, MIN_VOLATILITY_WAD + 4216);
        require(premiumWad == intrinsicWad, "shortfall not clamped");
    }

    function testRejectsOneUnitOutsideEachDomain() public view {
        _expectCallRevert(0, 1e18, 1, MIN_VOLATILITY_WAD, BlackScholes.SpotOutsideDomain.selector);
        _expectCallRevert(
            MAX_PRICE_WAD + 1, 1e18, 1, MIN_VOLATILITY_WAD, BlackScholes.SpotOutsideDomain.selector
        );
        _expectCallRevert(1e18, 0, 1, MIN_VOLATILITY_WAD, BlackScholes.StrikeOutsideDomain.selector);
        _expectCallRevert(
            1e18,
            MAX_PRICE_WAD + 1,
            1,
            MIN_VOLATILITY_WAD,
            BlackScholes.StrikeOutsideDomain.selector
        );
        _expectCallRevert(
            1e18,
            1e18,
            MAX_TIME_SECONDS + 1,
            MIN_VOLATILITY_WAD,
            BlackScholes.TimeOutsideDomain.selector
        );
        _expectCallRevert(
            1e18, 1e18, 1, MIN_VOLATILITY_WAD - 1, BlackScholes.VolatilityOutsideDomain.selector
        );
        _expectCallRevert(
            1e18, 1e18, 1, MAX_VOLATILITY_WAD + 1, BlackScholes.VolatilityOutsideDomain.selector
        );
    }

    function testFuzzFairValueBounds(
        uint128 spotSeed,
        uint128 strikeSeed,
        uint64 timeSeed,
        uint128 volatilitySeed
    ) public view {
        uint256 spotWad = WAD + (uint256(spotSeed) % MAX_PRICE_WAD);
        if (spotWad > MAX_PRICE_WAD) spotWad = MAX_PRICE_WAD;
        uint256 strikeWad = WAD + (uint256(strikeSeed) % MAX_PRICE_WAD);
        if (strikeWad > MAX_PRICE_WAD) strikeWad = MAX_PRICE_WAD;
        uint256 timeSeconds = 1 + (uint256(timeSeed) % MAX_TIME_SECONDS);
        uint256 volatilityWad = MIN_VOLATILITY_WAD
            + (uint256(volatilitySeed) % (MAX_VOLATILITY_WAD - MIN_VOLATILITY_WAD + 1));

        uint256 premiumWad = harness.callPrice(spotWad, strikeWad, timeSeconds, volatilityWad);
        uint256 intrinsicWad = spotWad > strikeWad ? spotWad - strikeWad : 0;
        require(premiumWad >= intrinsicWad, "below intrinsic");
        require(premiumWad <= spotWad, "above spot");
    }

    function _expectCallRevert(
        uint256 spotWad,
        uint256 strikeWad,
        uint256 timeSeconds,
        uint256 volatilityWad,
        bytes4 expectedSelector
    ) private view {
        (bool success, bytes memory reason) = address(harness)
            .staticcall(
                abi.encodeCall(
                    PricingMathHarness.callPrice, (spotWad, strikeWad, timeSeconds, volatilityWad)
                )
            );
        require(!success, "pricing succeeded");
        _requireSelector(reason, expectedSelector);
    }

    function _parseUint(string memory value) private pure returns (uint256 result) {
        bytes memory characters = bytes(value);
        require(characters.length != 0, "empty integer");
        for (uint256 i = 0; i < characters.length; ++i) {
            uint8 character = uint8(characters[i]);
            require(character >= 48 && character <= 57, "invalid integer");
            result = result * 10 + character - 48;
        }
    }

    function _parseSignedDecimalWad(string memory value) private pure returns (int256 result) {
        bytes memory characters = bytes(value);
        require(characters.length != 0, "empty decimal");
        bool negative = characters[0] == "-";
        uint256 start = negative ? 1 : 0;
        uint256 whole;
        uint256 fraction;
        uint256 fractionDigits;
        bool afterDecimal;

        for (uint256 i = start; i < characters.length; ++i) {
            bytes1 character = characters[i];
            if (character == ".") {
                require(!afterDecimal, "multiple decimals");
                afterDecimal = true;
                continue;
            }
            uint8 digit = uint8(character);
            require(digit >= 48 && digit <= 57, "invalid decimal");
            if (afterDecimal) {
                require(fractionDigits < 18, "too many decimals");
                fraction = fraction * 10 + digit - 48;
                ++fractionDigits;
            } else {
                whole = whole * 10 + digit - 48;
            }
        }
        while (fractionDigits < 18) {
            fraction *= 10;
            ++fractionDigits;
        }
        uint256 absolute = whole * WAD + fraction;
        result = negative ? -int256(absolute) : int256(absolute);
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temporary = value;
        uint256 digits;
        while (temporary != 0) {
            ++digits;
            temporary /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    function _absoluteDifference(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _absoluteSignedDifference(int256 a, int256 b) private pure returns (uint256) {
        int256 difference = a - b;
        return uint256(difference < 0 ? -difference : difference);
    }

    function _requireSelector(bytes memory reason, bytes4 expectedSelector) private pure {
        require(reason.length >= 4, "missing revert selector");
        bytes4 actualSelector;
        assembly ("memory-safe") {
            actualSelector := mload(add(reason, 0x20))
        }
        require(actualSelector == expectedSelector, "wrong revert selector");
    }
}
