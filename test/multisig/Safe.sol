// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Safe as GnosisSafe} from "@safe-global/Safe.sol";

/**
 * @title Safe
 * @dev A wrapper contract that inherits from Gnosis Safe for multisig functionality
 * @notice This contract provides multisig capabilities using the official Gnosis Safe implementation
 */
contract Safe is GnosisSafe {
    // No constructor needed - Safe uses proxy pattern
    // The setup() function will initialize the Safe after deployment
    constructor() GnosisSafe(){
        threshold = 0;
    }
}