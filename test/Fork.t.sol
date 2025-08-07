// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AlphaAMLBridge} from "../contracts/AlphaAMLBridge.sol";
import {Safe as Multisig} from "./multisig/Safe.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Enum} from "lib/safe-contracts/contracts/libraries/Enum.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {Safe} from "lib/safe-contracts/contracts/Safe.sol";


contract ForkTest is Test {
    uint256 public blockNumber = 365981150;
    string public RPC_URL = vm.envString("RPC_URL");

    uint256 public constant PK_1 = 0x1; // replace with your private key
    uint256 public constant PK_2 = 0x2; // replace with your private key
    uint256 public constant PK_3 = 0x3; // replace with your private key

    address public constant signer_1 = 0x463cb2c678Ca6C202Fc479C71929E232bC7Cb97d;
    address public constant signer_2 = 0x07a5FfcD58F71E0cC606c512F005DdC1EAe6492D;
    address public constant signer_3 = 0xB64a4e7E7C8a3CEF11460Fe885407D589AD21179;

    


    address public constant ALPHA_AML_BRIDGE = 0x0737AEE33BA21Da073459C373181Fd3ed228E6c9;
    address payable public constant MULTISIG_ADDRESS = payable(0x5292746Dfa3f70F6c03364CE4DC17AA3427826E6);
    address public constant BRIDGE_OWNER = 0x21Bf52C3c1d09a3F9d9CF1E7F32aD6d638e90a99;

    uint256 public constant requestId = 20;
    uint256 public constant riskScore = 16;

    uint256 public constant safeTxGas = 0x186a0;
    uint256 public constant baseGas = 0x30d40;
    uint256 public constant gasPrice = 0;
    address public constant gasToken = 0x0000000000000000000000000000000000000000;
    address payable public constant refundReceiver = payable(0x0000000000000000000000000000000000000000);

    function setUp() public {}

    function testFork() public {

        address wallet_1 = vm.addr(PK_1);
        address wallet_2 = vm.addr(PK_2);
        address wallet_3 = vm.addr(PK_3);

       vm.createSelectFork(RPC_URL, blockNumber);
// 0xf982b322
// 0000000000000000000000000000000000000000000000000000000000000014
// 0000000000000000000000000000000000000000000000000000000000000010

        bytes memory data = abi.encodeWithSelector(AlphaAMLBridge.setRiskScore.selector, requestId, riskScore);
        console.logBytes(data);
    
        Multisig oracle = Multisig(MULTISIG_ADDRESS);
        uint256 nonce = oracle.nonce();
        bytes32 txHash = oracle.getTransactionHash(
            ALPHA_AML_BRIDGE, 0, data, Enum.Operation.Call, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce
        );

        console.log(nonce);
        console.logBytes32(txHash);


        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(PK_1, txHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(PK_2, txHash);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(PK_3, txHash);
        bytes memory signature3 = abi.encodePacked(r3, s3, v3);

        console.logBytes(signature1);
        console.logBytes(signature2);
        console.logBytes(signature3);

        address[] memory signerAddresses = new address[](3);
        signerAddresses[0] = signer_1;
        signerAddresses[1] = signer_2;
        signerAddresses[2] = signer_3;

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

        vm.prank(signer_1);
        oracle.execTransaction(ALPHA_AML_BRIDGE, 0, data, Enum.Operation.Call, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, combinedSignatures);
        bytes memory execData = abi.encodeWithSelector(Safe.execTransaction.selector, ALPHA_AML_BRIDGE, 0, data, Enum.Operation.Call, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, combinedSignatures);
        console.logBytes(execData);
        // revert();
    }
}