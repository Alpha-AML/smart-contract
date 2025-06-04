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

## Overview

Alpha AML Bridge is a smart contract system that enables secure token transfers with built-in compliance checks. The system uses an oracle-based risk assessment mechanism to evaluate transfers before execution, ensuring regulatory compliance while maintaining decentralization.

## How It Works

![](https://i.ibb.co/LDHWXmwM/Screenshot-2025-06-05-at-03-40-57.png)

### 1. **User Initiates Transfer**
- User deposits tokens + ETH gas fee
- ETH is immediately sent to oracle for gas coverage
- Tokens are held in escrow
- Transfer request enters "Pending" status

### 2. **Oracle Risk Assessment**
- Oracle analyzes the transfer for AML compliance
- Risk score is assigned (0-100, lower = safer)
- Oracle calls `setRiskScore()` with assessment

### 3. **Transfer Execution**
- Oracle calls `execute()` to finalize transfer
- **If approved** (risk score < threshold): Transfer proceeds to recipient minus fee
- **If rejected** (risk score ≥ threshold): Full refund to sender

### 4. **Alternative: Cancellation**
- Users can cancel their own pending transfers
- Owner can cancel any transfer (admin override)
- Tokens are refunded, ETH stays with oracle

## Core Features

- **Whitelist Control**: Optional access control for initiate function
- **Risk Threshold**: Configurable risk tolerance (default: 50)
- **Multi-Token Support**: Support for multiple ERC20 tokens
- **Fee System**: Configurable fee collection on successful transfers
- **Admin Controls**: Comprehensive management functions for owner

## Contract Methods

### User Functions

#### `initiate(address token, uint256 amount, address recipient)`
Initiates a new transfer request.
- **Access**: Whitelisted users (or anyone if whitelist empty)
- **Requirements**: 
  - Token must be supported
  - Amount > 0
  - Must send exact `gasDeposit` ETH
  - Requires token approval first
- **Effects**: 
  - ETH sent directly to oracle
  - Tokens escrowed in contract
  - Request created with "Pending" status

#### `cancel(uint256 requestId)`
Cancels a pending transfer request.
- **Access**: Request owner or contract owner
- **Requirements**: Request must be in "Pending" status
- **Effects**: 
  - Tokens refunded to user
  - Request marked as "Cancelled"
  - ETH remains with oracle

### Oracle Functions

#### `setRiskScore(uint256 requestId, uint256 riskScore)`
Sets the risk assessment score for a transfer.
- **Access**: Oracle only
- **Requirements**: 
  - Request must be in "Pending" status
  - Risk score ≤ 100
- **Effects**: Risk score stored for execution logic

#### `execute(uint256 requestId)`
Executes or rejects a transfer based on risk assessment.
- **Access**: Oracle only
- **Requirements**: Request must be in "Pending" status
- **Logic**:
  - If `riskScore < riskThreshold`: Transfer approved
    - Fee charged and sent to `feeRecipient`
    - Remaining tokens sent to recipient
  - If `riskScore ≥ riskThreshold`: Transfer rejected
    - Full amount refunded to sender

### Owner Functions

#### Contract Configuration
- `setOracle(address _oracle)` - Update oracle address
- `setGasDeposit(uint256 _gasDeposit)` - Update required ETH deposit
- `setFeeRecipient(address _feeRecipient)` - Update fee collection address
- `setFeeBP(uint256 _feeBP)` - Update fee in basis points (max 1000 = 10%)
- `setRiskThreshold(uint256 _riskThreshold)` - Update risk approval threshold (max 100)

#### Token Management
- `setSupportedToken(address token, bool supported)` - Add/remove single token
- `setSupportedTokens(address[] tokens, bool[] supported)` - Batch token management
- `initializeSupportedTokens()` - Initialize with USDT, USDC, USDC.e on Arbitrum
- `clearSupportedTokens()` - Reset supported tokens counter

#### Whitelist Management
- `addToWhitelist(address user)` - Add single user to whitelist
- `addToWhitelistBatch(address[] users)` - Add multiple users to whitelist
- `removeFromWhitelist(address user)` - Remove user from whitelist
- `clearWhitelist()` - Reset whitelist counter

## Access Control Matrix

| Method | Owner | Oracle | Sender | Any Address |
|--------|-------|--------|--------|-------------|
| `initializeSupportedTokens` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setOracle` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setGasDeposit` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setFeeRecipient` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setFeeBP` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setRiskThreshold` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setSupportedToken` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `setSupportedTokensBatch` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `clearSupportedTokens` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `addToWhitelist` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `addToWhitelistBatch` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `clearWhitelist` | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `initiate` | ✅ YES | ✅ YES | ✅ YES | ✅ YES* |
| `cancel` | ✅ YES | ❌ NO | ✅ YES** | ❌ NO |
| `setRiskScore` | ❌ NO | ✅ YES | ❌ NO | ❌ NO |
| `execute` | ❌ NO | ✅ YES | ❌ NO | ❌ NO |

*\* Subject to whitelist restrictions*  
*\*\* Only for own requests*

## Whitelist Logic

- **If `whitelistLength == 0`**: Anyone can call `initiate()`
- **If `whitelistLength > 0`**: Only whitelisted addresses can call `initiate()`

## Risk Assessment Logic

- **Risk Score Range**: 0-100 (0 = no risk, 100 = maximum risk)
- **Approval Logic**: `riskScore < riskThreshold`
- **Default Threshold**: 50
- **Examples**:
  - Threshold 20: Only very low-risk transfers (0-19) approved
  - Threshold 75: More lenient, scores 0-74 approved

## Fee Structure

- **Fee Unit**: Basis points (1 BP = 0.01%)
- **Default Fee**: 10 BP = 0.1%
- **Maximum Fee**: 1000 BP = 10%
- **Collection**: Only on approved transfers

## Supported Tokens (Arbitrum)

- **USDT**: `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9`
- **USDC Native**: `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`
- **USDC.e Bridged**: `0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8`

## Events

- `Initiated(uint256 requestId, address user, address token, uint256 amount, address recipient)`
- `Cancelled(uint256 requestId)`
- `RiskScoreSet(uint256 requestId, uint256 riskScore)`
- `Executed(uint256 requestId, bool approved)`
- `TokenSupportUpdated(address token, bool supported)`
- `WhitelistUpdated(address user, bool whitelisted)`
- `WhitelistCleared()`
- `SupportedTokensCleared()`
- `RiskThresholdUpdated(uint256 newThreshold)`