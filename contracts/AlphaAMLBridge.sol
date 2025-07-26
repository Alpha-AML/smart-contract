// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title AlphaAMLBridge
 * @dev A bridge contract that performs AML (Anti-Money Laundering) checks on cross-chain transfers
 * @notice This contract allows users to initiate transfers that are validated by an oracle for risk assessment
 */
contract AlphaAMLBridge is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// Status of a transfer request
    enum Status { None, Initiated, Pending, Cancelled, Executed }

    /// Structure representing a transfer request
    struct Request {
        address sender;                // Sender, who initiated the request
        Status status;              // Current status of the request
        address token;               // Token being transferred
        uint96 riskScore;          // Risk score assigned by oracle (0-100)
        address recipient;          // Destination address for the transfer
        uint256 amountFromSender;   // Total amount deducted from sender (including fee)
        uint256 amountToRecipient;  // Net amount recipient will receive
        uint256 fee;                // Fee amount charged for the transfer
        uint256 depositEth;         // ETH deposited for gas costs
    }

    /// Emitted when a new transfer request is initiated
    event Initiated(
        uint256 indexed requestId,
        address indexed user,
        address token,
        uint256 amount,
        uint256 fee,
        address recipient
    );
    
    /// Emitted when a transfer request is cancelled
    event Cancelled(uint256 indexed requestId);
    
    /// Emitted when oracle sets a risk score for a request
    event RiskScoreSet(uint256 indexed requestId, uint96 riskScore);
    
    /// Emitted when a transfer request is executed
    event Executed(uint256 indexed requestId, bool approved);
    
    /// Emitted when token support status is updated
    event TokenSupportUpdated(address indexed token, bool supported);
    
    /// Emitted when senders whitelist status is updated
    event SendersWhitelistUpdated(address indexed user, bool whitelisted);

    /// Emitted when recipients whitelist status is updated
    event RecipientsWhitelistUpdated(address indexed user, bool whitelisted);
    
    /// Emitted when supported tokens list is cleared
    event SupportedTokensCleared();
    
    /// Emitted when risk threshold is updated
    event RiskThresholdUpdated(uint256 newThreshold);

    /// Emitted when oracle address is updated
    event OracleChanged(address oldOracle, address newOracle);

    /// Emitted when gas deposit is updated
    event GasDepositUpdated(uint256 oldGasDeposit, uint256 newGasDeposit);

    /// Emitted when fee recipient is updated
    event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);

    /// Emitted when gas payments recipient is updated
    event GasPaymentsRecipientUpdated(address oldGasPaymentsRecipient, address newGasPaymentsRecipient);

    /// Emitted when fee basis points is updated
    event FeeBPUpdated(uint256 oldFeeBP, uint256 newFeeBP);

    uint256 private constant BASIS_POINTS = 10_000; // 100%
    uint256 private constant MAX_FEE_BP = 1000; // 10%
    uint256 private constant MAX_RISK_SCORE = 100; // 100%

    /// Address of the oracle that provides risk scoring
    address public oracle;
    
    /// Required ETH deposit for gas costs (sent directly to oracle)
    uint256 public gasDeposit;
    
    /// Address that receives collected fees
    address public feeRecipient;

    /// Address that receives gas payments
    address public gasPaymentsRecipient;
    
    /// Fee in basis points (10 = 0.1%, 100 = 1%)
    uint256 public feeBP = 10; // 10 basis points = 0.1%
    
    /// Risk threshold above which transfers are rejected (0-100)
    uint256 public riskThreshold = 50; // Default risk threshold

    /// Counter for generating unique request IDs
    uint256 private _nextRequestId = 1;
    
    /// Mapping from request ID to request details
    mapping(uint256 => Request) public requests;

    /// Set of whitelisted addresses
    EnumerableSet.AddressSet private _sendersWhitelist;

    /// Set of whitelisted addresses
    EnumerableSet.AddressSet private _recipientsWhitelist;

    /// Set of supported tokens
    EnumerableSet.AddressSet private _supportedTokens;

    modifier onlyWhitelisted(address sender, address recipient) {
        require(_sendersWhitelist.contains(sender), "Sender not whitelisted");
        require(_recipientsWhitelist.contains(recipient), "Recipient not whitelisted");
        _;
    }

    /// Restricts function access to oracle only
    modifier onlyOracle() {
        require(msg.sender == oracle, "Caller is not oracle");
        _;
    }

    /**
     * @dev Initializes the bridge contract
     * @param _owner Address of the owner of the contract, which should be a multisig
     * @param _oracle Address of the oracle multisig that will provide risk scoring
     * @param _gasDeposit Exact ETH amount (in wei) required per request for gas costs
     * @param _feeRecipient Address that will receive collected fees
     * @param _gasPaymentsRecipient Address that will receive gas payments
     */
    constructor(
        address _owner,
        address _oracle,
        uint256 _gasDeposit,
        address _feeRecipient,
        address _gasPaymentsRecipient
    )
        Ownable(_owner)
    {
        require(_oracle != address(0), "Oracle=0");
        require(_feeRecipient != address(0), "FeeRecipient=0");
        oracle = _oracle;
        gasDeposit = _gasDeposit;
        feeRecipient = _feeRecipient;
        gasPaymentsRecipient = _gasPaymentsRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                             PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev User initiates a new transfer by depositing tokens + exact ETH for gas
     * @param token Address of the token to transfer
     * @param amount Net amount to be received by recipient (before fees)
     * @param recipient Destination address for the transfer
     * @notice ETH sent with this call is transferred directly to the oracle for gas costs
     * @notice Total token amount deducted = amount + fee
     */
    function initiate(
        address token,
        uint256 amount,
        address recipient
    ) external payable onlyWhitelisted(msg.sender, recipient) {
        require(amount > 0, "Amount>0");
        require(recipient != address(0), "Recipient=0");
        require(msg.value == gasDeposit, "Wrong gas deposit");
        require(_supportedTokens.contains(token), "Token not supported");

        uint256 requestId = _nextRequestId;

        // increment request id counter for next request
        unchecked {
            _nextRequestId++;
        }

        // Calculating fees based on the final recipient amount
        uint256 fee = (amount * feeBP) / BASIS_POINTS;
        uint256 amountFromSender = amount + fee;

        Request storage r   = requests[requestId];
        r.sender            = msg.sender;
        r.status            = Status.Initiated;
        r.token             = token;
        r.recipient         = recipient;
        r.amountFromSender  = amountFromSender;
        r.amountToRecipient = amount;
        r.fee               = fee;
        r.depositEth        = msg.value;

        // Transfer tokens from user to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amountFromSender);

        // Send ETH directly to gas payments recipient for gas costs
        Address.sendValue(payable(gasPaymentsRecipient), msg.value);

        emit Initiated(requestId, msg.sender, token, amountFromSender, fee, recipient);
    }

    /**
     * @dev Cancels a pending transfer request
     * @param requestId ID of the request to cancel
     * @notice Can be called by the user who created the request or by the contract owner
     * @notice Refunds tokens to user (ETH was already sent to oracle)
     */
    function cancel(uint256 requestId) external {
        Request storage r = requests[requestId];
        require(msg.sender == r.sender || msg.sender == owner(), "Not authorized");
        require(r.status == Status.Pending, "Not pending");

        r.status = Status.Cancelled;

        // Refund tokens to user (ETH was already sent to oracle)
        IERC20(r.token).safeTransfer(r.sender, r.amountFromSender);

        emit Cancelled(requestId);
    }

    /**
     * @dev Oracle executes the transfer based on risk assessment
     * @param requestId ID of the request to execute
     * @notice If approved (risk score < threshold): transfers tokens to recipient and fee to fee recipient
     * @notice If rejected (risk score >= threshold): refunds full amount to user
     */
    function execute(uint256 requestId) external {
        Request storage r = requests[requestId];
        require(r.status == Status.Pending, "Not pending");
        r.status = Status.Executed;

        // NOTE: executing request for users, which are no longer whitelisted is still intended
        // if their requests were created before they were removed from whitelist
        bool approved = r.riskScore < riskThreshold;
        if (approved) {
            // Transfer approved: send fee to fee recipient and net amount to recipient
            IERC20(r.token).safeTransfer(feeRecipient, r.fee);
            IERC20(r.token).safeTransfer(r.recipient, r.amountToRecipient);
        } else {
            // Transfer rejected: refund full amount to user
            IERC20(r.token).safeTransfer(r.sender, r.amountFromSender);
        }

        emit Executed(requestId, approved);
    }

    /*//////////////////////////////////////////////////////////////
                             ORACLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Oracle sets the risk score for an initiated request
     * @param requestId ID of the request to score
     * @param riskScore Risk score from 0-100 (higher = more risky)
     */
    function setRiskScore(uint256 requestId, uint96 riskScore)
        external
        onlyOracle
    {
        Request storage r = requests[requestId];
        require(r.status == Status.Initiated, "Not initiated");
        r.riskScore = riskScore;
        r.status = Status.Pending;
        emit RiskScoreSet(requestId, riskScore);
    }

    /*//////////////////////////////////////////////////////////////
                             OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updates the oracle address
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Oracle=0");
        address oldOracle = oracle;
        oracle = _oracle;
        emit OracleChanged(oldOracle, _oracle);
    }

    /**
     * @dev Updates the required gas deposit amount
     * @param _gasDeposit New gas deposit amount in wei
     */
    function setGasDeposit(uint256 _gasDeposit) external onlyOwner {
        uint256 oldGasDeposit = gasDeposit;
        gasDeposit = _gasDeposit;
        emit GasDepositUpdated(oldGasDeposit, _gasDeposit);
    }

    /**
     * @dev Updates the fee recipient address
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "FeeRecipient=0");
        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldFeeRecipient, _feeRecipient);
    }

    /**
     * @dev Updates the gas payments recipient address
     * @param _gasPaymentsRecipient New gas payments recipient address
     */
    function setGasPaymentsRecipient(address _gasPaymentsRecipient) external onlyOwner {
        require(_gasPaymentsRecipient != address(0), "GasPaymentsRecipient=0");
        address oldGasPaymentsRecipient = gasPaymentsRecipient;
        gasPaymentsRecipient = _gasPaymentsRecipient;
        emit GasPaymentsRecipientUpdated(oldGasPaymentsRecipient, _gasPaymentsRecipient);
    }

    /**
     * @dev Updates the fee percentage in basis points
     * @param _feeBP New fee in basis points (max 1000 = 10%)
     */
    function setFeeBP(uint256 _feeBP) external onlyOwner {
        require(_feeBP <= MAX_FEE_BP, "Fee too high"); // max 10%
        uint256 oldFeeBP = feeBP;
        feeBP = _feeBP;
        emit FeeBPUpdated(oldFeeBP, _feeBP);
    }

    /**
     * @dev Updates the risk threshold for transfer approval
     * @param _riskThreshold New risk threshold (0-100)
     */
    function setRiskThreshold(uint256 _riskThreshold) external onlyOwner {
        require(_riskThreshold <= MAX_RISK_SCORE && _riskThreshold > 0, "Threshold out of range");
        riskThreshold = _riskThreshold;
        emit RiskThresholdUpdated(_riskThreshold);
    }

    /**
     * @dev Adds or removes support for a specific token
     * @param token Token address to update
     * @param supported Whether the token should be supported
     */
    function setSupportedToken(address token, bool supported) external onlyOwner {
        require(token != address(0), "Token=0");
        supported ? _supportedTokens.add(token) : _supportedTokens.remove(token);
        emit TokenSupportUpdated(token, supported);
    }

    /**
     * @dev Batch update support status for multiple tokens
     * @param tokens Array of token addresses
     * @param supported Array of support statuses (must match tokens length)
     */
    function setSupportedTokenBatch(address[] calldata tokens, bool[] calldata supported) external onlyOwner {
        require(tokens.length == supported.length, "Array length mismatch");
        for (uint256 i = 0; i < tokens.length;) {
            require(tokens[i] != address(0), "Token=0");
            supported[i] ? _supportedTokens.add(tokens[i]) : _supportedTokens.remove(tokens[i]);
            emit TokenSupportUpdated(tokens[i], supported[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Adds a user to the whitelist
     * @param user Address to add to whitelist
     */
    function addToSendersWhitelist(address user) external onlyOwner {
        require(user != address(0), "User=0");
        _sendersWhitelist.add(user);
        emit SendersWhitelistUpdated(user, true);
    }

    /**
     * @dev Adds a user to the recipients whitelist
     * @param user Address to add to recipients whitelist
     */
    function addToRecipientsWhitelist(address user) external onlyOwner {
        require(user != address(0), "User=0");
        _recipientsWhitelist.add(user);
        emit RecipientsWhitelistUpdated(user, true);
    }

    /**
     * @dev Adds multiple users to the whitelist
     * @param users Array of addresses to add to whitelist
     */
    function addToSendersWhitelistBatch(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length;) {
            require(users[i] != address(0), "User=0");
            _sendersWhitelist.add(users[i]);
            emit SendersWhitelistUpdated(users[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Adds multiple users to the recipients whitelist
     * @param users Array of addresses to add to recipients whitelist
     */
    function addToRecipientsWhitelistBatch(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length;) {
            require(users[i] != address(0), "User=0");
            _recipientsWhitelist.add(users[i]);
            emit RecipientsWhitelistUpdated(users[i], true);
        }
    }

    /**
     * @dev Removes multiple users from the whitelist
     * @param usersToRemove Array of addresses to remove from whitelist
     */
    function clearSendersWhitelist(address[] calldata usersToRemove) external onlyOwner {
        for (uint256 i = 0; i < usersToRemove.length;) {
            _sendersWhitelist.remove(usersToRemove[i]);
            emit SendersWhitelistUpdated(usersToRemove[i], false);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Removes multiple users from the recipients whitelist
     * @param usersToRemove Array of addresses to remove from recipients whitelist
     */
    function clearRecipientsWhitelist(address[] calldata usersToRemove) external onlyOwner {
        for (uint256 i = 0; i < usersToRemove.length;) {
            _recipientsWhitelist.remove(usersToRemove[i]);
            emit RecipientsWhitelistUpdated(usersToRemove[i], false);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Checks if a token is supported
     * @param token Token address to check
     * @return _ True if token is supported, false otherwise
     */
    function supportedTokens(address token) external view returns (bool) {
        return _supportedTokens.contains(token);
    }

    /**
     * @dev Returns the number of supported tokens
     * @return _ length of supported tokens
     */
    function supportedTokensLength() external view returns (uint256) {
        return _supportedTokens.length();
    }

    /**
     * @dev Returns the supported tokens
     * @return _ Array of supported tokens
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return _supportedTokens.values();
    }

    /**
     * @dev Returns the supported tokens
     * @notice Use this function if list gets too large to be retrieved entirely
     * @param fromIdx Index of the first token to return
     * @param toIdx Index of the last token to return
     * @return tokens Array of supported tokens
     */
    function getSupportedTokensWithIndices(uint256 fromIdx, uint256 toIdx) external view returns (address[] memory tokens) {
        uint256 length = toIdx - fromIdx + 1;
        for (uint256 i = 0; i < length;) {
            tokens[i] = _supportedTokens.at(fromIdx + i);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Checks if a user is whitelisted as a sender
     * @param user Address to check
     * @return _ True if user is whitelisted as a sender, false otherwise
     */
    function sendersWhitelist(address user) external view returns (bool) {
        return _sendersWhitelist.contains(user);
    }

    /**
     * @dev Checks if a user is whitelisted as a recipient
     * @param user Address to check
     * @return _ True if user is whitelisted as a recipient, false otherwise
     */
    function recipientsWhitelist(address user) external view returns (bool) {
        return _recipientsWhitelist.contains(user);
    }

    /**
     * @dev Returns the number of whitelisted senders
     * @return _ Length of whitelisted senders
     */
    function sendersWhitelistLength() external view returns (uint256) {
        return _sendersWhitelist.length();
    }

    /**
     * @dev Returns the number of whitelisted recipients
     * @return _ Length of whitelisted recipients
     */
    function recipientsWhitelistLength() external view returns (uint256) {
        return _recipientsWhitelist.length();
    }

    /**
     * @dev Returns the whitelisted senders
     * @return _ Array of whitelisted senders
     */
    function getSendersWhitelist() external view returns (address[] memory) {
        return _sendersWhitelist.values();
    }

    /**
     * @dev Returns the whitelisted recipients
     * @return _ Array of whitelisted recipients
     */
    function getRecipientWhitelist() external view returns (address[] memory) {
        return _recipientsWhitelist.values();
    }

    /**
     * @dev Returns the whitelisted senders
     * @notice Use this function if list gets too large to be retrieved entirely
     * @param fromIdx Index of the first sender to return
     * @param toIdx Index of the last sender to return
     * @return users Array of whitelisted senders
     */
    function getSendersWhitelistWithIndices(uint256 fromIdx, uint256 toIdx) external view returns (address[] memory users) {
        uint256 length = toIdx - fromIdx + 1;
        for (uint256 i = 0; i < length;) {
            users[i] = _sendersWhitelist.at(fromIdx + i);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Returns the whitelisted recipients
     * @notice Use this function if list gets too large to be retrieved entirely
     * @param fromIdx Index of the first recipient to return
     * @param toIdx Index of the last recipient to return
     * @return users Array of whitelisted recipients
     */
    function getRecipientsWhitelistWithIndices(uint256 fromIdx, uint256 toIdx) external view returns (address[] memory users) {
        uint256 length = toIdx - fromIdx + 1;
        for (uint256 i = 0; i < length;) {
            users[i] = _recipientsWhitelist.at(fromIdx + i);
            unchecked {
                ++i;
            }
        }
    }
}