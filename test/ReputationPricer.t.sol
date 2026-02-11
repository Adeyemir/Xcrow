// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ReputationPricer} from "../src/core/ReputationPricer.sol";
import {XcrowTypes} from "../src/libraries/XcrowTypes.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";
import {MockReputationRegistry} from "./mocks/MockReputationRegistry.sol";

contract ReputationPricerTest is Test {
    ReputationPricer public pricer;
    MockIdentityRegistry public identityReg;
    MockReputationRegistry public reputationReg;

    address public agentOwner = makeAddr("agentOwner");
    address public agentWallet = makeAddr("agentWallet");
    address public reviewer1 = makeAddr("reviewer1");
    address public reviewer2 = makeAddr("reviewer2");

    uint256 public agentId;

    uint256 public constant MAX_PREMIUM_BPS = 20000; // 2x max premium
    uint256 public constant MAX_REP_SCORE = 100;
    uint64 public constant MIN_REVIEWS = 3;
    uint256 public constant PROTOCOL_FEE_BPS = 250;

    function setUp() public {
        identityReg = new MockIdentityRegistry();
        reputationReg = new MockReputationRegistry(address(identityReg));

        pricer = new ReputationPricer(
            address(reputationReg),
            address(identityReg),
            MAX_PREMIUM_BPS,
            MAX_REP_SCORE,
            MIN_REVIEWS,
            "starred"
        );

        // Register agent
        agentId = identityReg.mockRegisterAgent(agentOwner, agentWallet, "ipfs://agent");

        // Set base rate: 10 USDC
        vm.prank(agentOwner);
        pricer.setBaseRate(agentId, 10e6);

        // Add trusted reviewers
        pricer.addTrustedReviewer(reviewer1);
        pricer.addTrustedReviewer(reviewer2);
    }

    // =========================================
    // setBaseRate tests
    // =========================================

    function test_setBaseRate_byOwner() public {
        vm.prank(agentOwner);
        pricer.setBaseRate(agentId, 50e6);
        assertEq(pricer.agentBaseRates(agentId), 50e6);
    }

    function test_setBaseRate_byWallet() public {
        vm.prank(agentWallet);
        pricer.setBaseRate(agentId, 25e6);
        assertEq(pricer.agentBaseRates(agentId), 25e6);
    }

    function test_setBaseRate_revert_unauthorized() public {
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert("Not agent owner or wallet");
        pricer.setBaseRate(agentId, 10e6);
    }

    function test_setBaseRate_revert_zero() public {
        vm.prank(agentOwner);
        vm.expectRevert("Rate must be > 0");
        pricer.setBaseRate(agentId, 0);
    }

    // =========================================
    // getReputationMultiplier tests
    // =========================================

    function test_multiplier_noReviews_returns1x() public view {
        // No mock summary set, count = 0
        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 0);
        assertEq(mult, 10000); // 1x
    }

    function test_multiplier_belowMinReviews_returns1x() public {
        // Only 2 reviews, need 3
        reputationReg.mockSetSummary(agentId, 2, 85, 0);

        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 0);
        assertEq(mult, 10000); // 1x
    }

    function test_multiplier_perfectScore() public {
        // 100/100 with enough reviews
        reputationReg.mockSetSummary(agentId, 10, 100, 0);

        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 100);
        // multiplier = 10000 + (100 * 20000) / 100 = 10000 + 20000 = 30000 (3x)
        assertEq(mult, 30000);
    }

    function test_multiplier_halfScore() public {
        reputationReg.mockSetSummary(agentId, 5, 50, 0);

        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 50);
        // multiplier = 10000 + (50 * 20000) / 100 = 10000 + 10000 = 20000 (2x)
        assertEq(mult, 20000);
    }

    function test_multiplier_withDecimals() public {
        // Score of 8577 with 2 decimals = 85.77 → truncates to 85
        reputationReg.mockSetSummary(agentId, 5, 8577, 2);

        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 85);
        // multiplier = 10000 + (85 * 20000) / 100 = 10000 + 17000 = 27000 (2.7x)
        assertEq(mult, 27000);
    }

    function test_multiplier_cappedAtMax() public {
        // Score above max (150 > 100)
        reputationReg.mockSetSummary(agentId, 10, 150, 0);

        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 100); // Capped
        assertEq(mult, 30000); // 3x max
    }

    function test_multiplier_negativeScore_penalty() public {
        // Negative score: -50 with enough reviews
        reputationReg.mockSetSummary(agentId, 10, -50, 0);

        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 0);
        // penalty = (50 * 20000) / 100 = 10000 → capped, so multiplier = 1000 (0.1x floor)
        // Wait: 10000 >= 9000, so floor at 1000
        assertEq(mult, 1000); // 0.1x floor
    }

    function test_multiplier_slightlyNegativeScore() public {
        // Small negative: -20 with enough reviews
        reputationReg.mockSetSummary(agentId, 5, -20, 0);

        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 0);
        // penalty = (20 * 20000) / 100 = 4000
        // multiplier = 10000 - 4000 = 6000 (0.6x)
        assertEq(mult, 6000);
    }

    // =========================================
    // getQuote tests
    // =========================================

    function test_getQuote_noReputation() public view {
        // No reviews = 1x multiplier
        XcrowTypes.PriceQuote memory q = pricer.getQuote(agentId, PROTOCOL_FEE_BPS);

        assertEq(q.baseRate, 10e6);
        assertEq(q.effectiveRate, 10e6); // 1x
        assertEq(q.multiplier, 10000);
        // platformFee = 10e6 * 250 / 10000 = 0.25 USDC
        assertEq(q.platformFee, 250_000);
        assertEq(q.totalCost, 10e6 + 250_000);
    }

    function test_getQuote_withReputation() public {
        reputationReg.mockSetSummary(agentId, 10, 80, 0);

        XcrowTypes.PriceQuote memory q = pricer.getQuote(agentId, PROTOCOL_FEE_BPS);

        // multiplier = 10000 + (80 * 20000) / 100 = 26000 (2.6x)
        assertEq(q.multiplier, 26000);
        // effectiveRate = 10e6 * 26000 / 10000 = 26e6
        assertEq(q.effectiveRate, 26e6);
        // platformFee = 26e6 * 250 / 10000 = 650_000
        assertEq(q.platformFee, 650_000);
        assertEq(q.totalCost, 26e6 + 650_000);
    }

    function test_getQuote_revert_noBaseRate() public {
        // New agent with no rate set
        uint256 newAgent = identityReg.mockRegisterAgent(agentOwner, agentWallet, "ipfs://new");

        vm.expectRevert("Agent has no base rate");
        pricer.getQuote(newAgent, PROTOCOL_FEE_BPS);
    }

    // =========================================
    // Trusted reviewer management
    // =========================================

    function test_addTrustedReviewer() public {
        address newReviewer = makeAddr("new");
        pricer.addTrustedReviewer(newReviewer);
        assertTrue(pricer.isTrustedReviewer(newReviewer));
    }

    function test_addTrustedReviewer_revert_duplicate() public {
        vm.expectRevert("Already trusted");
        pricer.addTrustedReviewer(reviewer1);
    }

    function test_removeTrustedReviewer() public {
        pricer.removeTrustedReviewer(reviewer1);
        assertFalse(pricer.isTrustedReviewer(reviewer1));
    }

    function test_removeTrustedReviewer_revert_notTrusted() public {
        address rando = makeAddr("rando");
        vm.expectRevert("Not trusted");
        pricer.removeTrustedReviewer(rando);
    }

    function test_noTrustedReviewers_returns1x() public {
        // Remove all reviewers
        pricer.removeTrustedReviewer(reviewer1);
        pricer.removeTrustedReviewer(reviewer2);

        // Even with high reputation, no trusted reviewers = 1x
        reputationReg.mockSetSummary(agentId, 100, 100, 0);
        (uint256 score, uint256 mult) = pricer.getReputationMultiplier(agentId);
        assertEq(score, 0);
        assertEq(mult, 10000);
    }
}
