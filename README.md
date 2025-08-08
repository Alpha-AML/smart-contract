# Alpha AML Bridge

A decentralized bridge with integrated AML (Anti-Money Laundering) compliance checks for secure cross-chain token transfers.

Powered by Alpha AML technology
https://alpha-aml.com/

## Quick Start

```bash
npx hardhat clean
npx hardhat compile
npx hardhat run scripts/deploy.js --network arbitrum
```

## Contract Verification

After deployment, verify the contract on Etherscan:

### For Arbitrum Mainnet
```bash
npx hardhat verify --network arbitrum CONTRACT_ADDRESS "OWNER_ADDRESS" "ORACLE_ADDRESS" "GAS_DEPOSIT" "FEE_RECIPIENT" "GAS_PAYMENTS_RECIPIENT"
```

### Example with values:
```bash
npx hardhat verify --network arbitrum 0x0737AEE33BA21Da073459C373181Fd3ed228E6c9 "0x21Bf52C3c1d09a3F9d9CF1E7F32aD6d638e90a99" "0x1c478aA7F9c8e0A570b6f48d7aE1b1D2052033a5" "1000000000000" "0xc36887213fB7E33A55717C8943ba7fA7f109aA97" "0x1c478aA7F9c8e0A570b6f48d7aE1b1D2052033a5"
```

## Overview

Alpha AML Bridge is a smart contract system that enables secure token transfers with built-in compliance checks. The system uses an oracle-based risk assessment mechanism to evaluate transfers before execution, ensuring regulatory compliance while maintaining decentralization.

## How It Works

![](https://i.ibb.co/LDHWXmwM/Screenshot-2025-06-05-at-03-40-57.png)

### 1. **User Initiates Transfer**
- User deposits tokens + ETH (or other native token) gas fee
- ETH (or other native token) is immediately sent to gas payments recipient for gas coverage
- Tokens are held in escrow
- Transfer request enters "Initiated" status

### 2. **Oracle Risk Assessment**
- Oracle analyzes the transfer for AML compliance
- Risk score is assigned (0-100, lower = safer)
- Oracle calls `setRiskScore()` with assessment
- Request status changes to "Pending"

### 3. **Transfer Execution**
- Anyone can call `execute()` to finalize transfer (permissionless)
- **If approved** (risk score < threshold): Transfer proceeds to recipient minus fee
- **If rejected** (risk score ≥ threshold): Full refund to sender

### 4. **Alternative: Cancellation**
- Users can cancel their own pending transfers
- Owner can cancel any transfer (admin override)
- Tokens are refunded, ETH (or other native token)stays with gas payments recipient

## Gnosis Safe Configuration

For enhanced security, it is required to use a Gnosis Safe multisig wallet:

### Setup Requirements
1. **Deploy Gnosis Safe** with required signatures for optimal security
2. **Configure Safe** using the Gnosis Safe UI or programmatically
3. **Update Oracle Address** - After deployment, change the smart contract's oracle address to the Gnosis Safe address
4. **Decentralized Operations** - The `setRiskScore` function should only be called through the multisig to avoid centralization issues

### Recommended Configuration
- **Signature Threshold**: 2/3 or 3/4 signatures required
- **Signers**: Trusted parties with expertise in AML compliance
- **Usage**: All oracle functions should be executed through the multisig
- **Gas Fee Compensation**: When signing `setRiskScore` transactions, ETH (or other native token) will be paid from the signer's address. It's recommended to set the `gasPaymentsRecipient` to one of the multisig signers to compensate for gas fees. This can be updated anytime using the `setGasPaymentsRecipient` function.

## Core Features

- **Dual Whitelist Control**: Separate access control for senders and recipients
- **Risk Threshold**: Configurable risk tolerance (default: 50)
- **Multi-Token Support**: Support for multiple ERC20 tokens
- **Fee System**: Configurable fee collection on successful transfers
- **Permissionless Execution**: Anyone can execute pending transfers after risk assessment
- **Separated Gas Management**: Dedicated recipient for gas payments
- **Admin Controls**: Comprehensive management functions for owner

## Contract Methods

### User Functions

#### `initiate(address token, uint256 amount, address recipient)`
Initiates a new transfer request.
- **Access**: Whitelisted senders and recipients (or anyone if respective whitelist empty)
- **Requirements**: 
  - Token must be supported
  - Amount > 0 (net amount to recipient)
  - Must send exact `gasDeposit` ETH (or other native token)
  - Requires token approval first for `amount + fee`
- **Effects**: 
  - ETH (or other native token) sent directly to gas payments recipient
  - Total tokens (amount + fee) escrowed in contract
  - Request created with "Initiated" status

#### `cancel(uint256 requestId)`
Cancels a pending transfer request.
- **Access**: Request owner or contract owner
- **Requirements**: Request must be in "Initiated" or "Pending" status
- **Effects**: 
  - Tokens refunded to user
  - Request marked as "Cancelled"
  - ETH (or other native token) remains with gas payments recipient

### Oracle Functions

#### `setRiskScore(uint256 requestId, uint96 riskScore)`
Sets the risk assessment score for a transfer.
- **Access**: Oracle only (should be multisig)
- **Requirements**: 
  - Request must be in "Initiated" status
  - Risk score ≤ 100
- **Effects**: 
  - Risk score stored for execution logic
  - Status changed to "Pending"

### Public Functions

#### `execute(uint256 requestId)`
Executes or rejects a transfer based on risk assessment.
- **Access**: Anyone (permissionless)
- **Requirements**: Request must be in "Pending" status
- **Logic**:
  - If `riskScore < riskThreshold`: Transfer approved
    - Fee sent to `feeRecipient`
    - Net amount sent to recipient
  - If `riskScore ≥ riskThreshold`: Transfer rejected
    - Full amount refunded to sender

### Owner Functions

#### Contract Configuration
- `setOracle(address _oracle)` - Update oracle address (should be multisig)
- `setGasDeposit(uint256 _gasDeposit)` - Update required ETH (or other native token) deposit
- `setFeeRecipient(address _feeRecipient)` - Update fee collection address
- `setGasPaymentsRecipient(address _gasPaymentsRecipient)` - Update gas payments recipient
- `setFeeBP(uint256 _feeBP)` - Update fee in basis points (max 1000 = 10%)
- `setRiskThreshold(uint256 _riskThreshold)` - Update risk approval threshold (1-100)

#### Token Management
- `setSupportedToken(address token, bool supported)` - Add/remove single token
- `setSupportedTokenBatch(address[] tokens, bool[] supported)` - Batch token management

#### Senders Whitelist Management
- `addToSendersWhitelist(address user)` - Add single user to senders whitelist
- `addToSendersWhitelistBatch(address[] users)` - Add multiple users to senders whitelist
- `clearSendersWhitelist(address[] usersToRemove)` - Remove users from senders whitelist

#### Recipients Whitelist Management
- `addToRecipientsWhitelist(address user)` - Add single user to recipients whitelist
- `addToRecipientsWhitelistBatch(address[] users)` - Add multiple users to recipients whitelist
- `clearRecipientsWhitelist(address[] usersToRemove)` - Remove users from recipients whitelist

## Access Control Matrix

| Method | Owner | Oracle | Sender | Any Address |
|--------|-------|--------|--------|-------------|
| **Configuration** |
| `setOracle` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setGasDeposit` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setFeeRecipient` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setGasPaymentsRecipient` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setFeeBP` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setRiskThreshold` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| **Token Management** |
| `setSupportedToken` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setSupportedTokenBatch` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| **Senders Whitelist** |
| `addToSendersWhitelist` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `addToSendersWhitelistBatch` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `clearSendersWhitelist` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| **Recipients Whitelist** |
| `addToRecipientsWhitelist` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `addToRecipientsWhitelistBatch` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `clearRecipientsWhitelist` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| **Transfer Operations** |
| `initiate` | ✅ YES* | ✅ YES* | ✅ YES* | ✅ YES* |
| `cancel` | ✅ YES | ❌ NO | ✅ YES** | ❌ NO |
| `setRiskScore` | ❌ NO | ✅ YES | ❌ NO | ❌ NO |
| `execute` | ✅ YES | ✅ YES | ✅ YES | ✅ YES |

*\* Subject to senders and recipients whitelist restrictions*  
*\*\* Only for own requests*

## Whitelist Logic

### Senders Whitelist
- **If `sendersWhitelistLength() == 0`**: Anyone can initiate transfers
- **If `sendersWhitelistLength() > 0`**: Only whitelisted senders can initiate transfers

### Recipients Whitelist
- **If `recipientsWhitelistLength() == 0`**: Transfers can be sent to anyone
- **If `recipientsWhitelistLength() > 0`**: Transfers can only be sent to whitelisted recipients

## Risk Assessment Logic

- **Risk Score Range**: 0-100 (0 = no risk, 100 = maximum risk)
- **Approval Logic**: `riskScore < riskThreshold`
- **Default Threshold**: 50
- **Threshold Range**: 1-100 (must be > 0)
- **Examples**:
  - Threshold 20: Only very low-risk transfers (0-19) approved
  - Threshold 75: More lenient, scores 0-74 approved

## Fee Structure

- **Fee Unit**: Basis points (1 BP = 0.01%)
- **Default Fee**: 10 BP = 0.1%
- **Maximum Fee**: 1000 BP = 10%
- **Fee Calculation**: Based on recipient amount (fee = amount × feeBP / 10000)
- **Total Deduction**: User pays `amount + fee` total
- **Collection**: Only on approved transfers, sent to `feeRecipient`

## Gas Management

- **Gas Deposit**: Fixed ETH (or other native token) amount required per transaction
- **Immediate Transfer**: ETH (or other native token) sent directly to `gasPaymentsRecipient` upon initiation
- **No Refund**: ETH (or other native token) is not refunded even if transfer is cancelled or rejected
- **Purpose**: Covers oracle operation costs and execution gas

## Events

### Transfer Lifecycle
- `Initiated(uint256 requestId, address user, address token, uint256 amount, uint256 fee, address recipient)`
- `Cancelled(uint256 requestId)`
- `RiskScoreSet(uint256 requestId, uint96 riskScore)`
- `Executed(uint256 requestId, bool approved)`

### Configuration Updates
- `TokenSupportUpdated(address token, bool supported)`
- `SendersWhitelistUpdated(address user, bool whitelisted)`
- `RecipientsWhitelistUpdated(address user, bool whitelisted)`
- `SupportedTokensCleared()`
- `RiskThresholdUpdated(uint256 newThreshold)`
- `OracleChanged(address oldOracle, address newOracle)`
- `GasDepositUpdated(uint256 oldGasDeposit, uint256 newGasDeposit)`
- `FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient)`
- `GasPaymentsRecipientUpdated(address oldGasPaymentsRecipient, address newGasPaymentsRecipient)`
- `FeeBPUpdated(uint256 oldFeeBP, uint256 newFeeBP)`

## Request Status Flow

```
None → Initiated → Pending → Executed
            ↓         ↓
       Cancelled ← Cancelled
```

- **None**: Initial state (request doesn't exist)
- **Initiated**: Request created, waiting for risk assessment
- **Pending**: Risk score set, ready for execution
- **Cancelled**: Request cancelled by user or owner
- **Executed**: Final state, transfer completed (approved or rejected)

## View Functions

### Token Information
- `supportedTokens(address token)` - Check if token is supported
- `supportedTokensLength()` - Get number of supported tokens
- `getSupportedTokens()` - Get all supported tokens
- `getSupportedTokensWithIndices(uint256 fromIdx, uint256 toIdx)` - Get paginated tokens

### Whitelist Information
- `sendersWhitelist(address user)` - Check if user is whitelisted as sender
- `recipientsWhitelist(address user)` - Check if user is whitelisted as recipient
- `sendersWhitelistLength()` - Get number of whitelisted senders
- `recipientsWhitelistLength()` - Get number of whitelisted recipients
- `getSendersWhitelist()` - Get all whitelisted senders
- `getRecipientWhitelist()` - Get all whitelisted recipients
- `getSendersWhitelistWithIndices(uint256 fromIdx, uint256 toIdx)` - Get paginated senders
- `getRecipientsWhitelistWithIndices(uint256 fromIdx, uint256 toIdx)` - Get paginated recipients

### Request Information
- `requests(uint256 requestId)` - Get request details
- `nextRequestId()` - Get next request ID