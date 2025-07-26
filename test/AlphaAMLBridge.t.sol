// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AlphaAMLBridge} from "../contracts/AlphaAMLBridge.sol";
import {MockERC20} from "./tokens/MockERC20.sol";
import {Safe as Multisig} from "./multisig/Safe.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Enum} from "lib/safe-contracts/contracts/libraries/Enum.sol";
import {Vm} from "forge-std/Vm.sol";

/**
 * @title AlphaAMLBridgeTest
 * @dev Test suite for AlphaAMLBridge contract using Forge
 */
contract AlphaAMLBridgeTest is Test {
    AlphaAMLBridge public bridge;
    MockERC20 public token;
    Multisig public oracle;
    Multisig public owner;

    address public feeRecipient = makeAddr("feeRecipient");
    address public gasPaymentsRecipient = makeAddr("gasPaymentsRecipient");
    address public sender = makeAddr("sender");
    address public recipient = makeAddr("recipient");

    Vm.Wallet public signer1 = vm.createWallet("signer1");
    Vm.Wallet public signer2 = vm.createWallet("signer2");
    Vm.Wallet public signer3 = vm.createWallet("signer3");

    address public unrelatedAddress = makeAddr("unrelatedAddress");

    uint256 public constant GAS_DEPOSIT = 0.01 ether;
    uint256 public constant ONE_THOUSAND = 1000 ether;
    uint256 public constant BASIS_POINTS = 10_000; // 100%
    uint256 public constant MAX_FEE_BP = 1000; // 10%
    uint256 public constant MAX_RISK_SCORE = 100; // 100%

    /*//////////////////////////////////////////////////////////////
                             SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Mock Token", "MTK");

        // Deploy multisigs
        owner = new Multisig();
        oracle = new Multisig();

        // Setup multisigs
        address[] memory signers = new address[](3);
        signers[0] = signer1.addr;
        signers[1] = signer2.addr;
        signers[2] = signer3.addr;

        owner.setup(signers, 3, address(0), "", address(0), address(0), 0, payable(address(0)));

        oracle.setup(signers, 3, address(0), "", address(0), address(0), 0, payable(address(0)));

        // Deploy bridge contract
        bridge = new AlphaAMLBridge(address(owner), address(oracle), GAS_DEPOSIT, feeRecipient, gasPaymentsRecipient);

        // Set up token support
        vm.prank(address(owner));
        bridge.setSupportedToken(address(token), true);

        // Add users to whitelist
        vm.prank(address(owner));
        bridge.addToSendersWhitelist(sender);
        vm.prank(address(owner));
        bridge.addToRecipientsWhitelist(recipient);

        // Give users some tokens and ETH
        vm.deal(sender, 1 ether);
        token.mint(sender, 10 * ONE_THOUSAND);
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        assertEq(bridge.gasDeposit(), GAS_DEPOSIT);
        assertEq(bridge.feeRecipient(), feeRecipient);
        assertEq(bridge.gasPaymentsRecipient(), gasPaymentsRecipient);
        assertEq(bridge.feeBP(), 10); // 0.1%
        assertEq(bridge.riskThreshold(), 50);
        assertEq(bridge.oracle(), address(oracle));
        assertEq(bridge.owner(), address(owner));
        assertEq(bridge.supportedTokensLength(), 1);
        assertEq(bridge.getSupportedTokens()[0], address(token));
        assertEq(bridge.sendersWhitelistLength(), 1);
        assertEq(bridge.recipientsWhitelistLength(), 1);
        assertEq(bridge.getRecipientWhitelist()[0], recipient);
        assertEq(bridge.getSendersWhitelist()[0], sender);
        assertEq(bridge.getSupportedTokensWithIndices(0, 0)[0], address(token));
        assertEq(bridge.getSendersWhitelistWithIndices(0, 0)[0], sender);
        assertEq(bridge.getRecipientsWhitelistWithIndices(0, 0)[0], recipient);
    }

    function testDeploymentWithZeroAddresses() public {
        vm.expectRevert("Oracle=0");
        new AlphaAMLBridge(address(owner), address(0), GAS_DEPOSIT, feeRecipient, gasPaymentsRecipient);

        vm.expectRevert("FeeRecipient=0");
        new AlphaAMLBridge(address(owner), address(oracle), GAS_DEPOSIT, address(0), gasPaymentsRecipient);

        vm.expectRevert("GasDeposit=0");
        new AlphaAMLBridge(address(owner), address(oracle), 0, feeRecipient, gasPaymentsRecipient);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AlphaAMLBridge(address(0), address(oracle), GAS_DEPOSIT, feeRecipient, gasPaymentsRecipient);

        vm.expectRevert("GasPaymentsRecipient=0");
        new AlphaAMLBridge(address(owner), address(oracle), GAS_DEPOSIT, feeRecipient, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetOracle() public {
        address newOracle = makeAddr("newOracle");

        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.OracleChanged(address(oracle), newOracle);
        bridge.setOracle(newOracle);

        assertEq(bridge.oracle(), newOracle);
    }

    function testSetOracleOnlyOwner() public {
        address newOracle = makeAddr("newOracle");

        vm.expectRevert();
        vm.prank(unrelatedAddress);
        bridge.setOracle(newOracle);
    }

    function testSetFeeBP() public {
        uint256 newFeeBP = 50; // 0.5%

        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.FeeBPUpdated(10, newFeeBP);
        bridge.setFeeBP(newFeeBP);

        assertEq(bridge.feeBP(), newFeeBP);
    }

    function testSetFeeBPTooHigh() public {
        vm.expectRevert("Fee too high");
        vm.prank(address(owner));
        bridge.setFeeBP(1001); // > 10%
    }

    function testSetFeeBPOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.setFeeBP(1001);
    }

    function testSetFeeRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.FeeRecipientUpdated(feeRecipient, newFeeRecipient);
        bridge.setFeeRecipient(newFeeRecipient);
        vm.assertEq(bridge.feeRecipient(), newFeeRecipient);
    }

    function testSetFeeRecipientOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.setFeeRecipient(makeAddr("newFeeRecipient"));
    }

    function testSetFeeRecipientZeroAddress() public {
        vm.expectRevert("FeeRecipient=0");
        vm.prank(address(owner));
        bridge.setFeeRecipient(address(0));
    }

    function testSetGasDeposit() public {
        uint256 newGasDeposit = 0.02 ether;
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.GasDepositUpdated(GAS_DEPOSIT, newGasDeposit);
        bridge.setGasDeposit(newGasDeposit);
        vm.assertEq(bridge.gasDeposit(), newGasDeposit);
    }

    function testSetGasDepositOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.setGasDeposit(0.02 ether);
    }

    function testSetGasPaymentsRecipient() public {
        address newGasPaymentsRecipient = makeAddr("newGasPaymentsRecipient");
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.GasPaymentsRecipientUpdated(gasPaymentsRecipient, newGasPaymentsRecipient);
        bridge.setGasPaymentsRecipient(newGasPaymentsRecipient);
        vm.assertEq(bridge.gasPaymentsRecipient(), newGasPaymentsRecipient);
    }

    function testSetGasPaymentsRecipientOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.setGasPaymentsRecipient(makeAddr("newGasPaymentsRecipient"));
    }

    function testSetGasPaymentsRecipientZeroAddress() public {
        vm.expectRevert("GasPaymentsRecipient=0");
        vm.prank(address(owner));
        bridge.setGasPaymentsRecipient(address(0));
    }

    function testSetRiskThreshold() public {
        uint256 newRiskThreshold = 75;
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.RiskThresholdUpdated(newRiskThreshold);
        bridge.setRiskThreshold(newRiskThreshold);
        vm.assertEq(bridge.riskThreshold(), newRiskThreshold);
    }

    function testSetRiskThresholdOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.setRiskThreshold(75);
    }

    function testSetRiskThresholdOutOfRange() public {
        vm.expectRevert("Threshold out of range");
        vm.prank(address(owner));
        bridge.setRiskThreshold(101);
    }

    function testSetSupportedToken() public {
        // this token is unvetted by the contract and it is expected
        // owners should be vetting new tokens before setting
        address newToken = makeAddr("newToken");
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.TokenSupportUpdated(newToken, true);
        bridge.setSupportedToken(newToken, true);
        vm.assertEq(bridge.supportedTokens(newToken), true);
    }

    function testSetSupportedTokenOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.setSupportedToken(makeAddr("newToken"), true);
    }

    function testSetSupportedTokenZeroAddress() public {
        vm.expectRevert("Token=0");
        vm.prank(address(owner));
        bridge.setSupportedToken(address(0), true);
    }

    function testSetSupportedTokenBatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("newToken1");
        tokens[1] = makeAddr("newToken2");
        bool[] memory supported = new bool[](2);
        supported[0] = true;
        supported[1] = true;

        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.TokenSupportUpdated(tokens[0], true);
        emit AlphaAMLBridge.TokenSupportUpdated(tokens[1], true);
        bridge.setSupportedTokenBatch(tokens, supported);
        vm.assertEq(bridge.supportedTokens(tokens[0]), true);
        vm.assertEq(bridge.supportedTokens(tokens[1]), true);
    }

    function testSetSupportedTokenBatchOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.setSupportedTokenBatch(new address[](0), new bool[](0));
    }

    function testSetSupportedTokenBatchArrayLengthMismatch() public {
        vm.expectRevert("Array length mismatch");
        vm.prank(address(owner));
        bridge.setSupportedTokenBatch(new address[](1), new bool[](2));
    }

    function testSetSupportedTokenBatchZeroAddress() public {
        vm.expectRevert("Token=0");
        vm.prank(address(owner));
        bridge.setSupportedTokenBatch(new address[](1), new bool[](1));
    }

    function testSetSupportedTokenAlreadySupported() public {
        vm.expectRevert("Token already set");
        vm.prank(address(owner));
        bridge.setSupportedToken(address(token), true);
    }

    function testSetSupportedTokenBatchAlreadySupported() public {
        address token2 = makeAddr("token2");
        address token3 = makeAddr("token3");
        vm.prank(address(owner));
        bridge.setSupportedToken(address(token2), true);
        vm.prank(address(owner));
        bridge.setSupportedToken(address(token3), true);

        vm.recordLogs();
        address[] memory tokens = new address[](3);
        tokens[0] = address(token);
        tokens[1] = address(token2);
        tokens[2] = address(token3);
        bool[] memory supported = new bool[](3);
        supported[0] = true;
        supported[1] = true;
        supported[2] = true;
        vm.assertEq(bridge.supportedTokens(address(token)), true);
        vm.prank(address(owner));
        bridge.setSupportedTokenBatch(tokens, supported);
        assertEq(vm.getRecordedLogs().length, 0, "No events should be emitted");
        vm.assertEq(bridge.supportedTokens(address(token)), true);
    }

    function testAddToSendersWhitelist() public {
        address newSender = makeAddr("newSender");
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.SendersWhitelistUpdated(newSender, true);
        bridge.addToSendersWhitelist(newSender);
        vm.assertEq(bridge.sendersWhitelist(newSender), true);
    }

    function testAddToSendersWhitelistOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.addToSendersWhitelist(sender);
    }

    function testAddToSendersWhitelistZeroAddress() public {
        vm.expectRevert("User=0");
        vm.prank(address(owner));
        bridge.addToSendersWhitelist(address(0));
    }

    function testAddToSendersWhitelistAlreadyInWhitelist() public {
        vm.expectRevert("User already in whitelist");
        vm.prank(address(owner));
        bridge.addToSendersWhitelist(sender);
    }

    function testAddToRecipientsWhitelist() public {
        address newRecipient = makeAddr("newRecipient");
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.RecipientsWhitelistUpdated(newRecipient, true);
        bridge.addToRecipientsWhitelist(newRecipient);
        vm.assertEq(bridge.recipientsWhitelist(newRecipient), true);
    }

    function testAddToRecipientsWhitelistOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.addToRecipientsWhitelist(recipient);
    }

    function testAddToRecipientsWhitelistZeroAddress() public {
        vm.expectRevert("User=0");
        vm.prank(address(owner));
        bridge.addToRecipientsWhitelist(address(0));
    }

    function testAddToRecipientsWhitelistAlreadyInWhitelist() public {
        vm.expectRevert("User already in whitelist");
        vm.prank(address(owner));
        bridge.addToRecipientsWhitelist(recipient);
    }

    function testAddToSendersWhitelistBatch() public {
        address[] memory users = new address[](2);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.SendersWhitelistUpdated(users[0], true);
        emit AlphaAMLBridge.SendersWhitelistUpdated(users[1], true);
        bridge.addToSendersWhitelistBatch(users);
        vm.assertEq(bridge.sendersWhitelist(users[0]), true);
        vm.assertEq(bridge.sendersWhitelist(users[1]), true);
    }

    function testAddToSendersWhitelistBatchOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.addToSendersWhitelistBatch(new address[](0));
    }

    function testAddToSendersWhitelistBatchZeroAddress() public {
        vm.expectRevert("User=0");
        vm.prank(address(owner));
        bridge.addToSendersWhitelistBatch(new address[](1));
    }

    function testAddToSendersWhitelistBatchAlreadyInWhitelist() public {
        vm.recordLogs();
        address[] memory users = new address[](1);
        users[0] = sender;
        vm.assertEq(bridge.sendersWhitelist(sender), true);
        vm.prank(address(owner));
        bridge.addToSendersWhitelistBatch(users);
        assertEq(vm.getRecordedLogs().length, 0, "No events should be emitted");
        vm.assertEq(bridge.sendersWhitelist(sender), true);
    }

    function testAddToRecipientsWhitelistBatch() public {
        address[] memory users = new address[](2);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.RecipientsWhitelistUpdated(users[0], true);
        emit AlphaAMLBridge.RecipientsWhitelistUpdated(users[1], true);
        bridge.addToRecipientsWhitelistBatch(users);
        vm.assertEq(bridge.recipientsWhitelist(users[0]), true);
        vm.assertEq(bridge.recipientsWhitelist(users[1]), true);
    }

    function testAddToRecipientsWhitelistBatchOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.addToRecipientsWhitelistBatch(new address[](0));
    }

    function testAddToRecipientsWhitelistBatchZeroAddress() public {
        vm.expectRevert("User=0");
        vm.prank(address(owner));
        bridge.addToRecipientsWhitelistBatch(new address[](1));
    }

    function testAddToRecipientsWhitelistBatchAlreadyInWhitelist() public {
        vm.recordLogs();
        address[] memory users = new address[](1);
        users[0] = recipient;
        vm.assertEq(bridge.recipientsWhitelist(recipient), true);
        vm.prank(address(owner));
        bridge.addToRecipientsWhitelistBatch(users);
        assertEq(vm.getRecordedLogs().length, 0, "No events should be emitted");
        vm.assertEq(bridge.recipientsWhitelist(recipient), true);
    }

    function testClearSendersWhitelist() public {
        address[] memory users = new address[](1);
        users[0] = sender;
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.SendersWhitelistUpdated(sender, false);
        bridge.clearSendersWhitelist(users);
        vm.assertEq(bridge.sendersWhitelist(sender), false);
    }

    function testClearSendersWhitelistOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.clearSendersWhitelist(new address[](0));
    }

    function testClearSendersWhitelistNotInWhitelist() public {
        vm.recordLogs();
        address[] memory users = new address[](1);
        users[0] = makeAddr("user");
        vm.prank(address(owner));
        bridge.clearSendersWhitelist(users);
        assertEq(vm.getRecordedLogs().length, 0, "No events should be emitted");
        vm.assertEq(bridge.sendersWhitelist(users[0]), false);
    }

    function testClearRecipientsWhitelist() public {
        address[] memory users = new address[](1);
        users[0] = recipient;
        vm.prank(address(owner));
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.RecipientsWhitelistUpdated(recipient, false);
        bridge.clearRecipientsWhitelist(users);
        vm.assertEq(bridge.recipientsWhitelist(recipient), false);
    }

    function testClearRecipientsWhitelistOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unrelatedAddress));
        vm.prank(unrelatedAddress);
        bridge.clearRecipientsWhitelist(new address[](0));
    }

    function testClearRecipientsWhitelistNotInWhitelist() public {
        vm.recordLogs();
        address[] memory users = new address[](1);
        users[0] = makeAddr("user");
        vm.prank(address(owner));
        bridge.clearRecipientsWhitelist(users);
        assertEq(vm.getRecordedLogs().length, 0, "No events should be emitted");
        vm.assertEq(bridge.recipientsWhitelist(users[0]), false);
    }

    /*//////////////////////////////////////////////////////////////
                         INITIATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitiate() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        // Approve tokens
        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);

        // Get initial balances
        uint256 initialUserBalance = token.balanceOf(sender);
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));
        uint256 initialGasRecipientBalance = gasPaymentsRecipient.balance;

        // get request id
        uint256 requestId = 1;

        // Initiate transfer
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.Initiated(
            requestId, sender, address(token), ONE_THOUSAND + expectedFee, expectedFee, recipient
        );
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        // Check request was created
        AlphaAMLBridge.Request memory request = bridge.requests(requestId);

        assertEq(request.sender, sender);
        assertTrue(request.status == AlphaAMLBridge.Status.Initiated);
        assertEq(request.token, address(token));
        assertEq(request.riskScore, 0); // risk score is not set yet
        assertEq(request.recipient, recipient);
        assertEq(request.amountFromSender, ONE_THOUSAND + expectedFee);
        assertEq(request.amountToRecipient, ONE_THOUSAND);
        assertEq(request.fee, expectedFee);
        assertEq(request.depositEth, GAS_DEPOSIT);

        // Check balances
        assertEq(token.balanceOf(sender), initialUserBalance - request.amountFromSender);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance + request.amountFromSender);
        assertEq(gasPaymentsRecipient.balance, initialGasRecipientBalance + request.depositEth);
    }

    function testInitiateWrongGasDeposit() public {
        vm.expectRevert("Wrong gas deposit");
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT - 1}(address(token), ONE_THOUSAND, recipient);
    }

    function testInitiateZeroAmount() public {
        vm.expectRevert("Amount>0");
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), 0, recipient);
    }

    function testInitiateNotWhitelistedSender() public {
        vm.expectRevert("Sender not whitelisted");
        vm.deal(unrelatedAddress, 1 ether);
        vm.prank(unrelatedAddress);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);
    }

    function testInitiateNotWhitelistedRecipient() public {
        vm.expectRevert("Recipient not whitelisted");
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, unrelatedAddress);
    }

    function testInitiateUnsupportedToken() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS");
        uint256 amount = 100 * 10 ** 18;

        vm.expectRevert("Token not supported");
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(unsupportedToken), amount, recipient);
    }

    /*//////////////////////////////////////////////////////////////
                         ORACLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetRiskScore() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.RiskScoreSet(1, 30);
        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);

        // Check risk score was set
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(request.riskScore, 30);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Pending));
    }

    function testSetRiskScoreOnlyOracle() public {
        // First initiate a request
        uint256 amount = 100 * 10 ** 18;
        vm.prank(sender);
        token.approve(address(bridge), amount + (amount * 10) / BASIS_POINTS);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), amount, recipient);

        // Non-oracle tries to set risk score
        vm.expectRevert("Caller is not oracle");
        vm.prank(unrelatedAddress);
        bridge.setRiskScore(1, 30);
    }

    function testSetRiskScoreNotInitiated() public {
        assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.None));
        vm.expectRevert("Not initiated");
        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);
    }

    /*//////////////////////////////////////////////////////////////
                         EXECUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function testExecuteApproved() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);

        // Get initial balances
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));
        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        // anyone can execute
        vm.prank(unrelatedAddress);
        bridge.execute(1);

        // Check execution results
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Executed));

        // Check balances
        assertEq(token.balanceOf(recipient), initialRecipientBalance + request.amountToRecipient);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance + request.fee);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountToRecipient - request.fee);
    }

    function testExecuteRejected() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(address(oracle));
        // set higher than the threshold
        bridge.setRiskScore(1, 80);

        // Get initial balances
        uint256 initialUserBalance = token.balanceOf(sender);
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));

        // anyone can execute
        vm.prank(unrelatedAddress);
        bridge.execute(1);

        // Check execution results
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Executed));

        // Check user got refund
        assertEq(token.balanceOf(sender), initialUserBalance + request.amountFromSender);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountFromSender);
    }

    function testExecuteNotPending() public {
        vm.assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.None));
        vm.expectRevert("Not pending");
        vm.prank(unrelatedAddress);
        bridge.execute(1);
    }

    function testExecuteInitiatedButNotPending() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.Initiated));
        vm.expectRevert("Not pending");
        vm.prank(unrelatedAddress);
        bridge.execute(1);
    }

    function testExecuteWorksAfterSenderWhitelistChange() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(address(owner));
        address[] memory users = new address[](1);
        users[0] = sender;
        bridge.clearSendersWhitelist(users);

        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);

        // Get initial balances
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));
        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        vm.prank(unrelatedAddress);
        bridge.execute(1);

        // Check execution results
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Executed));

        // Check balances
        assertEq(token.balanceOf(recipient), initialRecipientBalance + request.amountToRecipient);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance + request.fee);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountToRecipient - request.fee);
    }

    function testExecuteWorksAfterRecipientWhitelistChange() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(address(owner));
        address[] memory users = new address[](1);
        users[0] = recipient;
        bridge.clearRecipientsWhitelist(users);

        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);

        // Get initial balances
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));
        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        vm.prank(unrelatedAddress);
        bridge.execute(1);

        // Check execution results
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Executed));

        // Check balances
        assertEq(token.balanceOf(recipient), initialRecipientBalance + request.amountToRecipient);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance + request.fee);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountToRecipient - request.fee);
    }

    function testExecuteCanNotBeExecutedAgain() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);

        // Get initial balances
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));
        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        // anyone can execute
        vm.prank(unrelatedAddress);
        bridge.execute(1);

        // Check execution results
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Executed));

        // Check balances
        assertEq(token.balanceOf(recipient), initialRecipientBalance + request.amountToRecipient);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance + request.fee);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountToRecipient - request.fee);

        // can not be executed again
        vm.expectRevert("Not pending");
        vm.prank(unrelatedAddress);
        bridge.execute(1);
    }

    function testCancelAfterInitiated() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        // Get initial balances
        uint256 initialUserBalance = token.balanceOf(sender);
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));

        assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.Initiated));

        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.Cancelled(1);
        vm.prank(sender);
        bridge.cancel(1);

        // Check request was cancelled
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Cancelled));

        // Check balances
        assertEq(token.balanceOf(sender), initialUserBalance + request.amountFromSender);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountFromSender);
    }

    function testCancelAfterPending() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);

        // Get initial balances
        uint256 initialUserBalance = token.balanceOf(sender);
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));

        assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.Pending));

        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.Cancelled(1);
        vm.prank(sender);
        bridge.cancel(1);

        // Check request was cancelled
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Cancelled));

        // Check balances
        assertEq(token.balanceOf(sender), initialUserBalance + request.amountFromSender);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountFromSender);
    }

    function testCancelNotAuthorized() public {
        vm.expectRevert("Not authorized");
        vm.prank(unrelatedAddress);
        bridge.cancel(1);
    }

    function testCancelByOwner() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        // Get initial balances
        uint256 initialUserBalance = token.balanceOf(sender);
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));

        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.Cancelled(1);
        vm.prank(address(owner));
        bridge.cancel(1);

        // Check request was cancelled
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Cancelled));

        // Check balances
        assertEq(token.balanceOf(sender), initialUserBalance + request.amountFromSender);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountFromSender);
    }

    function testCancelNotInitiatedAndNotPending() public {
        assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.None));
        vm.expectRevert("Not pending nor initiated");
        vm.prank(address(owner));
        bridge.cancel(1);
    }

    function testCancelCancelled() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(sender);
        bridge.cancel(1);

        assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.Cancelled));

        vm.expectRevert("Not pending nor initiated");
        vm.prank(sender);
        bridge.cancel(1);
    }

    function testCancelExecuted() public {
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        vm.prank(address(oracle));
        bridge.setRiskScore(1, 30);

        vm.prank(unrelatedAddress);
        bridge.execute(1);

        assertEq(uint8(bridge.requests(1).status), uint8(AlphaAMLBridge.Status.Executed));

        vm.expectRevert("Not pending nor initiated");
        vm.prank(sender);
        bridge.cancel(1);
    }

    /*//////////////////////////////////////////////////////////////
                           FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Fuzz test for initiate function with various amounts
     * @param amount The fuzzed amount to test (will be bounded)
     */
    function testFuzzInitiate(uint256 amount) public {
        // Bound the amount to reasonable values to avoid overflow and ensure we have enough tokens
        amount = bound(amount, 1 ether, 500_000 ether); // 1 to 500,000 tokens

        // Calculate expected fee
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (amount * feePercent) / BASIS_POINTS;
        uint256 totalAmount = amount + expectedFee;

        // Ensure sender has enough tokens
        token.mint(sender, totalAmount); // Add some buffer

        // Approve tokens
        vm.prank(sender);
        token.approve(address(bridge), totalAmount);

        // Get initial balances
        uint256 initialSenderBalance = token.balanceOf(sender);
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));
        uint256 initialGasRecipientBalance = gasPaymentsRecipient.balance;

        // Get expected request ID
        uint256 expectedRequestId = bridge.nextRequestId();

        // Initiate transfer
        vm.expectEmit(true, true, true, true);
        emit AlphaAMLBridge.Initiated(expectedRequestId, sender, address(token), totalAmount, expectedFee, recipient);

        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), amount, recipient);

        // Verify request was created correctly
        AlphaAMLBridge.Request memory request = bridge.requests(expectedRequestId);

        assertEq(request.sender, sender, "Request sender should match");
        assertTrue(request.status == AlphaAMLBridge.Status.Initiated, "Request should be initiated");
        assertEq(request.token, address(token), "Request token should match");
        assertEq(request.riskScore, 0, "Risk score should be unset");
        assertEq(request.recipient, recipient, "Request recipient should match");
        assertEq(request.amountFromSender, totalAmount, "Amount from sender should include fee");
        assertEq(request.amountToRecipient, amount, "Amount to recipient should be original amount");
        assertEq(request.fee, expectedFee, "Fee should be calculated correctly");
        assertEq(request.depositEth, GAS_DEPOSIT, "ETH deposit should match gas deposit");

        // Verify balances changed correctly
        assertEq(
            token.balanceOf(sender),
            initialSenderBalance - totalAmount,
            "Sender balance should decrease by total amount"
        );
        assertEq(
            token.balanceOf(address(bridge)),
            initialBridgeBalance + totalAmount,
            "Bridge balance should increase by total amount"
        );
        assertEq(
            gasPaymentsRecipient.balance, initialGasRecipientBalance + GAS_DEPOSIT, "Gas recipient should receive ETH"
        );

        // Verify the math: amount + fee = totalAmount
        assertEq(request.amountToRecipient + request.fee, totalAmount, "Amount plus fee should equal total amount");
    }

    /**
     * @dev Fuzz test for initiate with edge case amounts
     * @param amount The fuzzed amount to test (smaller bounds for edge cases)
     */
    function testFuzzInitiateEdgeCases(uint256 amount) public {
        // Test with smaller amounts to catch edge cases in fee calculation
        amount = bound(amount, 1, 10000); // 1 wei to 10000 wei

        // For very small amounts, fee might be 0 due to integer division
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (amount * feePercent) / BASIS_POINTS;
        uint256 totalAmount = amount + expectedFee;

        // Ensure sender has enough tokens
        token.mint(sender, totalAmount + 1 ether); // Extra buffer for small amounts

        // Approve tokens
        vm.prank(sender);
        token.approve(address(bridge), totalAmount);

        // Get initial state
        uint256 initialSenderBalance = token.balanceOf(sender);
        uint256 expectedRequestId = bridge.nextRequestId();

        // Initiate transfer - should work even with tiny amounts
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), amount, recipient);

        // Verify request was created
        AlphaAMLBridge.Request memory request = bridge.requests(expectedRequestId);

        assertEq(request.amountToRecipient, amount, "Amount to recipient should match input");
        assertEq(request.fee, expectedFee, "Fee should be calculated correctly even for small amounts");
        assertEq(request.amountFromSender, totalAmount, "Total amount should be sum of amount and fee");

        // Verify balances
        assertEq(
            token.balanceOf(sender), initialSenderBalance - totalAmount, "Sender balance should decrease correctly"
        );

        // For very small amounts, fee could be 0
        if (expectedFee == 0) {
            assertEq(totalAmount, amount, "When fee is 0, total amount equals original amount");
        } else {
            assertGt(totalAmount, amount, "When fee > 0, total amount should be greater than original amount");
        }
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZ TESTS ARRAY INDICES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Fuzz test for getSupportedTokensWithIndices with various index combinations
     * @param fromIdx Starting index for the range
     * @param toIdx Ending index for the range
     */
    function testFuzzGetSupportedTokensWithIndices(uint256 fromIdx, uint256 toIdx) public {
        vm.startPrank(address(owner));
        bridge.setSupportedToken(makeAddr("token2"), true);
        bridge.setSupportedToken(makeAddr("token3"), true);
        bridge.setSupportedToken(makeAddr("token4"), true);
        vm.stopPrank();

        uint256 totalTokens = bridge.supportedTokensLength();
        fromIdx = bound(fromIdx, 0, totalTokens - 1);
        toIdx = bound(toIdx, fromIdx, totalTokens - 1);

        // This should not revert for valid indices
        address[] memory tokens = bridge.getSupportedTokensWithIndices(fromIdx, toIdx);

        // Verify the returned array has correct length
        uint256 expectedLength = toIdx - fromIdx + 1;
        assertEq(tokens.length, expectedLength, "Returned array should have correct length");

        // Verify all returned addresses are valid (non-zero)
        for (uint256 i = 0; i < tokens.length; i++) {
            assertTrue(tokens[i] != address(0), "Token address should not be zero");
            assertTrue(bridge.supportedTokens(tokens[i]), "Returned token should be supported");
        }
    }

    /**
     * @dev Fuzz test for getSendersWhitelistWithIndices
     * @param fromIdx Starting index
     * @param toIdx Ending index
     */
    function testFuzzGetSendersWhitelistWithIndices(uint256 fromIdx, uint256 toIdx) public {
        // Add more users to whitelist
        vm.startPrank(address(owner));
        bridge.addToSendersWhitelist(makeAddr("user2"));
        bridge.addToSendersWhitelist(makeAddr("user3"));
        bridge.addToSendersWhitelist(makeAddr("user4"));
        vm.stopPrank();

        uint256 totalUsers = bridge.sendersWhitelistLength();
        fromIdx = bound(fromIdx, 0, totalUsers - 1);
        toIdx = bound(toIdx, fromIdx, totalUsers - 1);

        address[] memory users = bridge.getSendersWhitelistWithIndices(fromIdx, toIdx);

        uint256 expectedLength = toIdx - fromIdx + 1;
        assertEq(users.length, expectedLength, "Returned array should have correct length");

        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(users[i] != address(0), "User address should not be zero");
            assertTrue(bridge.sendersWhitelist(users[i]), "Returned user should be whitelisted");
        }
    }

    /**
     * @dev Fuzz test for getRecipientsWhitelistWithIndices
     * @param fromIdx Starting index
     * @param toIdx Ending index
     */
    function testFuzzGetRecipientsWhitelistWithIndices(uint256 fromIdx, uint256 toIdx) public {
        // Add more recipients to whitelist
        vm.startPrank(address(owner));
        bridge.addToRecipientsWhitelist(makeAddr("recipient2"));
        bridge.addToRecipientsWhitelist(makeAddr("recipient3"));
        bridge.addToRecipientsWhitelist(makeAddr("recipient4"));
        vm.stopPrank();

        uint256 totalRecipients = bridge.recipientsWhitelistLength();
        fromIdx = bound(fromIdx, 0, totalRecipients - 1);
        toIdx = bound(toIdx, fromIdx, totalRecipients - 1);

        address[] memory recipients = bridge.getRecipientsWhitelistWithIndices(fromIdx, toIdx);

        uint256 expectedLength = toIdx - fromIdx + 1;
        assertEq(recipients.length, expectedLength, "Returned array should have correct length");

        for (uint256 i = 0; i < recipients.length; i++) {
            assertTrue(recipients[i] != address(0), "Recipient address should not be zero");
            assertTrue(bridge.recipientsWhitelist(recipients[i]), "Returned recipient should be whitelisted");
        }
    }

    /**
     * @dev Fuzz test for array indices that should fail
     * @param fromIdx Starting index
     * @param toIdx Ending index
     */
    function testFuzzArrayIndicesInvalid(uint256 fromIdx, uint256 toIdx) public {
        uint256 totalTokens = bridge.supportedTokensLength();

        // Test cases that should revert
        bool shouldRevert = false;

        if (totalTokens == 0) {
            shouldRevert = true;
        } else if (fromIdx >= totalTokens || toIdx >= totalTokens) {
            shouldRevert = true;
        } else if (fromIdx > toIdx) {
            shouldRevert = true;
        }

        vm.assume(shouldRevert);

        // This should revert for invalid parameters
        vm.expectRevert();
        bridge.getSupportedTokensWithIndices(fromIdx, toIdx);
    }

    /**
     * @dev Fuzz test for setRiskScore with various risk scores
     * @param riskScore The fuzzed risk score to test
     */
    function testFuzzSetRiskScore(uint96 riskScore) public {
        // Create a request first
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        // Risk score should be settable to any value (no validation in contract)
        vm.prank(address(oracle));
        bridge.setRiskScore(1, riskScore);

        // Verify the risk score was set correctly
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(request.riskScore, riskScore, "Risk score should be set correctly");
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Pending), "Status should be Pending");
    }

    /**
     * @dev Fuzz test for setRiskThreshold with various thresholds
     * @param threshold The fuzzed threshold to test
     */
    function testFuzzSetRiskThreshold(uint256 threshold) public {
        // Bound threshold to valid range (1-100)
        threshold = bound(threshold, 1, MAX_RISK_SCORE);

        vm.prank(address(owner));
        bridge.setRiskThreshold(threshold);

        assertEq(bridge.riskThreshold(), threshold, "Risk threshold should be set correctly");
    }

    /**
     * @dev Fuzz test for invalid risk thresholds that should fail
     * @param invalidThreshold Invalid threshold values
     */
    function testFuzzSetRiskThresholdInvalid(uint256 invalidThreshold) public {
        // Test values outside valid range
        vm.assume(invalidThreshold == 0 || invalidThreshold > MAX_RISK_SCORE);

        vm.expectRevert("Threshold out of range");
        vm.prank(address(owner));
        bridge.setRiskThreshold(invalidThreshold);
    }

    /**
     * @dev Fuzz test for setFeeBP with various fee percentages
     * @param feeBP The fuzzed fee basis points
     */
    function testFuzzSetFeeBP(uint256 feeBP) public {
        // Bound to valid range (0-1000)
        feeBP = bound(feeBP, 0, MAX_FEE_BP);

        vm.prank(address(owner));
        bridge.setFeeBP(feeBP);

        assertEq(bridge.feeBP(), feeBP, "Fee BP should be set correctly");
    }

    /**
     * @dev Fuzz test for invalid fee BPs that should fail
     * @param invalidFeeBP Invalid fee basis points
     */
    function testFuzzSetFeeBPInvalid(uint256 invalidFeeBP) public {
        // Test values above maximum
        vm.assume(invalidFeeBP > MAX_FEE_BP);
        vm.assume(invalidFeeBP <= type(uint256).max / 2); // Avoid ridiculous values

        vm.expectRevert("Fee too high");
        vm.prank(address(owner));
        bridge.setFeeBP(invalidFeeBP);
    }

    /**
     * @dev Fuzz test for execute function with various risk scores and thresholds
     * @param riskScore Risk score to test (0-200 to test boundary conditions)
     * @param threshold Risk threshold to test (1-100)
     */
    function testFuzzExecuteRiskLogic(uint96 riskScore, uint256 threshold) public {
        // Bound threshold to valid range
        threshold = bound(threshold, 1, MAX_RISK_SCORE);

        // Set the risk threshold
        vm.prank(address(owner));
        bridge.setRiskThreshold(threshold);

        // Create a request
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        // Set risk score
        vm.prank(address(oracle));
        bridge.setRiskScore(1, riskScore);

        // Get initial balances
        uint256 initialSenderBalance = token.balanceOf(sender);
        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        // Execute the request
        vm.prank(unrelatedAddress); // Anyone can execute
        bridge.execute(1);

        // Verify the execution logic
        AlphaAMLBridge.Request memory request = bridge.requests(1);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Executed), "Request should be executed");

        // Check if it was approved based on risk logic
        bool shouldBeApproved = riskScore < threshold;

        if (shouldBeApproved) {
            // Should transfer to recipient and fee recipient
            assertEq(
                token.balanceOf(recipient),
                initialRecipientBalance + request.amountToRecipient,
                "Recipient should receive tokens"
            );
            assertEq(
                token.balanceOf(feeRecipient),
                initialFeeRecipientBalance + request.fee,
                "Fee recipient should receive fee"
            );
            assertEq(token.balanceOf(sender), initialSenderBalance, "Sender should not get refund");
        } else {
            // Should refund to sender
            assertEq(
                token.balanceOf(sender),
                initialSenderBalance + request.amountFromSender,
                "Sender should get full refund"
            );
            assertEq(token.balanceOf(recipient), initialRecipientBalance, "Recipient should receive nothing");
            assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance, "Fee recipient should receive nothing");
        }
    }

    /**
     * @dev Fuzz test for fee calculation with various amounts and fee percentages
     * @param amount Transfer amount to test
     * @param feeBP Fee basis points to test
     */
    function testFuzzFeeCalculation(uint256 amount, uint256 feeBP) public {
        // Bound inputs to reasonable ranges
        amount = bound(amount, 1 ether, 10000 ether);
        feeBP = bound(feeBP, 100, MAX_FEE_BP);

        // Set the fee
        vm.prank(address(owner));
        bridge.setFeeBP(feeBP);

        // Calculate expected fee
        uint256 expectedFee = (amount * feeBP) / BASIS_POINTS;
        uint256 totalAmount = amount + expectedFee;

        // Ensure sender has enough tokens
        token.mint(sender, totalAmount + 100 ether);

        // Approve and initiate
        vm.prank(sender);
        token.approve(address(bridge), totalAmount);

        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), amount, recipient);

        // Verify the fee calculation
        AlphaAMLBridge.Request memory request = bridge.requests(bridge.nextRequestId() - 1);

        assertEq(request.fee, expectedFee, "Fee should be calculated correctly");
        assertEq(request.amountToRecipient, amount, "Amount to recipient should match input");
        assertEq(request.amountFromSender, totalAmount, "Total amount should include fee");

        // Verify fee percentage is correct (avoid division by zero)
        if (amount > 0) {
            uint256 actualFeePercent = (request.fee * BASIS_POINTS) / amount;
            assertApproxEqAbs(actualFeePercent, feeBP, 1, "Fee percentage should be exact");
        }

        // Verify the math
        assertEq(request.amountToRecipient + request.fee, request.amountFromSender, "Math should be consistent");
    }

    /*//////////////////////////////////////////////////////////////
                        Test with Multisig
    //////////////////////////////////////////////////////////////*/

    function testMultisigExecuteWithApprovedRiskScore() public {
        // First, create a request that needs risk scoring
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        uint256 requestId = bridge.nextRequestId();

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        uint96 riskScore = 25; // Low risk score

        // Verify initial state - request should be Initiated
        AlphaAMLBridge.Request memory initialRequest = bridge.requests(requestId);
        assertEq(uint8(initialRequest.status), uint8(AlphaAMLBridge.Status.Initiated));
        assertEq(initialRequest.riskScore, 0);

        // Prepare the transaction data for setRiskScore call
        bytes memory txData = abi.encodeWithSelector(AlphaAMLBridge.setRiskScore.selector, requestId, riskScore);

        // Transaction details for Gnosis Safe
        address to = address(bridge);
        uint256 value = 0;
        bytes memory data = txData;
        Enum.Operation operation = Enum.Operation.Call; // CALL operation
        uint256 safeTxGas = 200000;
        uint256 baseGas = 200000;
        uint256 gasPrice = 0;
        address gasToken = address(0);
        address payable refundReceiver = payable(address(0));
        uint256 nonce = oracle.nonce();

        // Get the transaction hash that needs to be signed
        bytes32 txHash = oracle.getTransactionHash(
            to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce
        );

        // Create signatures from all 3 signers
        // Signer 1
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signer1, txHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        // Signer 2
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signer2, txHash);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        // Signer 3
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(signer3, txHash);
        bytes memory signature3 = abi.encodePacked(r3, s3, v3);

        // Concatenate signatures in the correct order (addresses must be sorted)
        // For Gnosis Safe, signatures must be sorted by signer address
        address[] memory signerAddresses = new address[](3);
        signerAddresses[0] = signer1.addr;
        signerAddresses[1] = signer2.addr;
        signerAddresses[2] = signer3.addr;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature1;
        signatures[1] = signature2;
        signatures[2] = signature3;

        // Sort signers and signatures by address too avoid FS026
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 2 - i; j++) {
                if (signerAddresses[j] > signerAddresses[j + 1]) {
                    // Swap addresses
                    address tempAddr = signerAddresses[j];
                    signerAddresses[j] = signerAddresses[j + 1];
                    signerAddresses[j + 1] = tempAddr;

                    // Swap corresponding signatures
                    bytes memory tempSig = signatures[j];
                    signatures[j] = signatures[j + 1];
                    signatures[j + 1] = tempSig;
                }
            }
        }

        // Concatenate all signatures
        bytes memory combinedSignatures = abi.encodePacked(signatures[0], signatures[1], signatures[2]);

        // // Execute the multisig transaction
        // // This should succeed because we have all 3 required signatures
        // vm.expectEmit(true, true, true, true);
        // emit AlphaAMLBridge.RiskScoreSet(requestId, riskScore);

        bool success = oracle.execTransaction(
            to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, combinedSignatures
        );

        assertTrue(success, "Multisig transaction should succeed");

        // Verify the risk score was set correctly
        AlphaAMLBridge.Request memory finalRequest = bridge.requests(requestId);
        assertEq(finalRequest.riskScore, riskScore, "Risk score should be set correctly");
        assertEq(uint8(finalRequest.status), uint8(AlphaAMLBridge.Status.Pending), "Status should be Pending");

        // Verify nonce was incremented
        assertEq(oracle.nonce(), nonce + 1, "Nonce should be incremented");
    }

    function testMultisigWithInsufficientSignatures() public {
        // Create a request first
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        uint256 requestId = 1;
        uint96 riskScore = 25;

        // Prepare transaction data
        bytes memory txData = abi.encodeWithSelector(AlphaAMLBridge.setRiskScore.selector, requestId, riskScore);

        address to = address(bridge);
        uint256 value = 0;
        bytes memory data = txData;
        Enum.Operation operation = Enum.Operation.Call;
        uint256 safeTxGas = 200000;
        uint256 baseGas = 200000;
        uint256 gasPrice = 0;
        address gasToken = address(0);
        address payable refundReceiver = payable(address(0));
        uint256 nonce = oracle.nonce();

        bytes32 txHash = oracle.getTransactionHash(
            to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce
        );

        // Only get 2 signatures (insufficient for 3-of-3 multisig)
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signer1, txHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signer2, txHash);

        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        bytes memory insufficientSignatures = abi.encodePacked(signature1, signature2);

        // This should fail due to insufficient signatures
        vm.expectRevert();
        oracle.execTransaction(
            to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, insufficientSignatures
        );

        // Verify the risk score was NOT set
        AlphaAMLBridge.Request memory request = bridge.requests(requestId);
        assertEq(request.riskScore, 0, "Risk score should remain unset");
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Initiated), "Status should remain Initiated");
    }

    function testMultisigExecuteRefundsAfterRiskScore() public {
        // Full workflow: Initiate -> Multisig SetRiskScore -> Execute
        uint256 feePercent = bridge.feeBP();
        uint256 expectedFee = (ONE_THOUSAND * feePercent) / BASIS_POINTS;

        // Step 1: Initiate transfer
        vm.prank(sender);
        token.approve(address(bridge), ONE_THOUSAND + expectedFee);
        vm.prank(sender);
        bridge.initiate{value: GAS_DEPOSIT}(address(token), ONE_THOUSAND, recipient);

        uint256 requestId = 1;
        uint96 riskScore = 61; // Above threshold (50)

        // Step 2: Multisig sets risk score (same as testMultisig but condensed)
        bytes memory txData = abi.encodeWithSelector(AlphaAMLBridge.setRiskScore.selector, requestId, riskScore);

        address to = address(bridge);
        uint256 value = 0;
        Enum.Operation operation = Enum.Operation.Call;
        uint256 safeTxGas = 200000;
        uint256 baseGas = 200000;
        uint256 gasPrice = 0;
        address gasToken = address(0);
        address payable refundReceiver = payable(address(0));
        uint256 nonce = oracle.nonce();

        bytes32 txHash = oracle.getTransactionHash(
            to, value, txData, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce
        );

        // Create signatures from all 3 signers
        // Signer 1
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signer1, txHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        // Signer 2
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signer2, txHash);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        // Signer 3
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(signer3, txHash);
        bytes memory signature3 = abi.encodePacked(r3, s3, v3);

        // Concatenate signatures in the correct order (addresses must be sorted)
        // For Gnosis Safe, signatures must be sorted by signer address
        address[] memory signerAddresses = new address[](3);
        signerAddresses[0] = signer1.addr;
        signerAddresses[1] = signer2.addr;
        signerAddresses[2] = signer3.addr;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature1;
        signatures[1] = signature2;
        signatures[2] = signature3;

        // Sort signers and signatures by address too avoid FS026
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 2 - i; j++) {
                if (signerAddresses[j] > signerAddresses[j + 1]) {
                    // Swap addresses
                    address tempAddr = signerAddresses[j];
                    signerAddresses[j] = signerAddresses[j + 1];
                    signerAddresses[j + 1] = tempAddr;

                    // Swap corresponding signatures
                    bytes memory tempSig = signatures[j];
                    signatures[j] = signatures[j + 1];
                    signatures[j + 1] = tempSig;
                }
            }
        }

        // Sort signers and signatures by address too avoid FS026
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 2 - i; j++) {
                if (signerAddresses[j] > signerAddresses[j + 1]) {
                    // Swap addresses
                    address tempAddr = signerAddresses[j];
                    signerAddresses[j] = signerAddresses[j + 1];
                    signerAddresses[j + 1] = tempAddr;

                    // Swap corresponding signatures
                    bytes memory tempSig = signatures[j];
                    signatures[j] = signatures[j + 1];
                    signatures[j + 1] = tempSig;
                }
            }
        }

        // Concatenate all signatures
        bytes memory combinedSignatures = abi.encodePacked(signatures[0], signatures[1], signatures[2]);

        // Execute multisig transaction to set risk score
        oracle.execTransaction(
            to, value, txData, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, combinedSignatures
        );

        // Verify risk score was set and status is Pending
        AlphaAMLBridge.Request memory request = bridge.requests(requestId);
        assertEq(request.riskScore, riskScore);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Pending));

        // Step 3: Execute the transfer (anyone can do this)
        uint256 initialSenderBalance = token.balanceOf(sender);
        uint256 initialBridgeBalance = token.balanceOf(address(bridge));
        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        vm.prank(unrelatedAddress);
        bridge.execute(requestId);

        // Step 4: Verify refund (riskScore > threshold)
        request = bridge.requests(requestId);
        assertEq(uint8(request.status), uint8(AlphaAMLBridge.Status.Executed));
        assertEq(token.balanceOf(sender), initialSenderBalance + request.amountFromSender);
        assertEq(token.balanceOf(address(bridge)), initialBridgeBalance - request.amountFromSender);
        assertEq(token.balanceOf(recipient), initialRecipientBalance);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance);
    }
}
