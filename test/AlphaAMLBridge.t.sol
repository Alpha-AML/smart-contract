// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AlphaAMLBridge} from "../contracts/AlphaAMLBridge.sol";
import {MockERC20} from "./tokens/MockERC20.sol";
import {Safe as Multisig} from "./multisig/Safe.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

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

    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public signer3 = makeAddr("signer3");
    
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
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        owner.setup(
            signers,
            3,
            address(0),
            "",
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        oracle.setup(
            signers,
            3,
            address(0),
            "",
            address(0),
            address(0),
            0,
            payable(address(0))
        );

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
        emit AlphaAMLBridge.Initiated(requestId, sender, address(token), ONE_THOUSAND + expectedFee, expectedFee, recipient);
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
        uint256 amount = 100 * 10**18;
        
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
        uint256 amount = 100 * 10**18;
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
}