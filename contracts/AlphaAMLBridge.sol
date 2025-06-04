// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AlphaAMLBridge is Ownable {
    using SafeERC20 for IERC20;

    enum Status { Pending, Cancelled, Executed }

    struct Request {
        address user;
        IERC20 token;
        uint256 amount;
        address recipient;
        uint256 riskScore;
        Status status;
        uint256 depositEth;
    }

    address public oracle;
    uint256 public gasDeposit;
    address public feeRecipient;
    uint256 public feeBP = 10; // 10 basis points = 0.1%
    uint256 public riskThreshold = 50; // Default risk threshold

    uint256 private nextRequestId = 1;
    mapping(uint256 => Request) public requests;
    mapping(address => bool) public supportedTokens;
    mapping(address => bool) public whitelist;
    uint256 public whitelistLength;
    uint256 public supportedTokensLength;

    event Initiated(
        uint256 indexed requestId,
        address indexed user,
        address token,
        uint256 amount,
        address recipient
    );
    event Cancelled(uint256 indexed requestId);
    event RiskScoreSet(uint256 indexed requestId, uint256 riskScore);
    event Executed(uint256 indexed requestId, bool approved);
    event TokenSupportUpdated(address indexed token, bool supported);
    event WhitelistUpdated(address indexed user, bool whitelisted);
    event WhitelistCleared();
    event SupportedTokensCleared();
    event RiskThresholdUpdated(uint256 newThreshold);

    modifier onlyOracle() {
        require(msg.sender == oracle, "Caller is not oracle");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelistLength == 0 || whitelist[msg.sender], "Not whitelisted");
        _;
    }

    /// @param _oracle       the oracle EOA
    /// @param _gasDeposit   exact ETH (in wei) required per request
    /// @param _feeRecipient address that collects 0.1% fees
    constructor(
        address _oracle,
        uint256 _gasDeposit,
        address _feeRecipient
    )
        Ownable(msg.sender)  // pass deployer as initial owner
    {
        require(_oracle != address(0), "Oracle=0");
        require(_feeRecipient != address(0), "FeeRecipient=0");
        oracle = _oracle;
        gasDeposit = _gasDeposit;
        feeRecipient = _feeRecipient;
    }

    /// @notice Initialize supported tokens after deployment
    function initializeSupportedTokens() external onlyOwner {
        // USDT on Arbitrum
        supportedTokens[0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9] = true;
        // USDC Native on Arbitrum  
        supportedTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831] = true;
        // USDC.e Bridged on Arbitrum
        supportedTokens[0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8] = true;
        
        supportedTokensLength = 3;
        
        emit TokenSupportUpdated(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, true);
        emit TokenSupportUpdated(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, true);
        emit TokenSupportUpdated(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, true);
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Oracle=0");
        oracle = _oracle;
    }

    function setGasDeposit(uint256 _gasDeposit) external onlyOwner {
        gasDeposit = _gasDeposit;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "FeeRecipient=0");
        feeRecipient = _feeRecipient;
    }

    function setFeeBP(uint256 _feeBP) external onlyOwner {
        require(_feeBP <= 1000, "Fee too high"); // max 10%
        feeBP = _feeBP;
    }

    function setRiskThreshold(uint256 _riskThreshold) external onlyOwner {
        require(_riskThreshold <= 100, "Threshold too high"); // max 100
        riskThreshold = _riskThreshold;
        emit RiskThresholdUpdated(_riskThreshold);
    }

    function setSupportedToken(address token, bool supported) external onlyOwner {
        require(token != address(0), "Token=0");
        
        // Update counter
        if (supported && !supportedTokens[token]) {
            supportedTokensLength++;
        } else if (!supported && supportedTokens[token]) {
            supportedTokensLength--;
        }
        
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    function setSupportedTokenBatch(address[] calldata tokens, bool[] calldata supported) external onlyOwner {
        require(tokens.length == supported.length, "Array length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "Token=0");
            
            // Update counter
            if (supported[i] && !supportedTokens[tokens[i]]) {
                supportedTokensLength++;
            } else if (!supported[i] && supportedTokens[tokens[i]]) {
                supportedTokensLength--;
            }
            
            supportedTokens[tokens[i]] = supported[i];
            emit TokenSupportUpdated(tokens[i], supported[i]);
        }
    }

    function clearSupportedTokens(address[] calldata tokensToRemove) external onlyOwner {
        for (uint256 i = 0; i < tokensToRemove.length; i++) {
            if (supportedTokens[tokensToRemove[i]]) {
                supportedTokens[tokensToRemove[i]] = false;
                supportedTokensLength--;
                emit TokenSupportUpdated(tokensToRemove[i], false);
            }
        }
    }

    function addToWhitelist(address user) external onlyOwner {
        require(user != address(0), "User=0");
        if (!whitelist[user]) {
            whitelist[user] = true;
            whitelistLength++;
            emit WhitelistUpdated(user, true);
        }
    }

    function addToWhitelistBatch(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "User=0");
            if (!whitelist[users[i]]) {
                whitelist[users[i]] = true;
                whitelistLength++;
                emit WhitelistUpdated(users[i], true);
            }
        }
    }

    function clearWhitelist(address[] calldata usersToRemove) external onlyOwner {
        for (uint256 i = 0; i < usersToRemove.length; i++) {
            if (whitelist[usersToRemove[i]]) {
                whitelist[usersToRemove[i]] = false;
                whitelistLength--;
                emit WhitelistUpdated(usersToRemove[i], false);
            }
        }
    }

    /// @notice User initiates a new transfer by depositing tokens + exact ETH (sent directly to oracle)
    function initiate(
        address token,
        uint256 amount,
        address recipient
    ) external payable onlyWhitelisted {
        require(amount > 0, "Amount>0");
        require(recipient != address(0), "Recipient=0");
        require(msg.value == gasDeposit, "Wrong gas deposit");
        require(supportedTokensLength > 0 && supportedTokens[token], "Token not supported");

        uint256 requestId = nextRequestId++;
        Request storage r = requests[requestId];
        r.user       = msg.sender;
        r.token      = IERC20(token);
        r.amount     = amount;
        r.recipient  = recipient;
        r.status     = Status.Pending;
        r.depositEth = msg.value;

        r.token.safeTransferFrom(msg.sender, address(this), amount);
        
        // Send ETH directly to oracle
        payable(oracle).transfer(msg.value);
        
        emit Initiated(requestId, msg.sender, token, amount, recipient);
    }

    /// @notice User can cancel their own request, or contract owner can cancel any request
    function cancel(uint256 requestId) external {
        Request storage r = requests[requestId];
        require(msg.sender == r.user || msg.sender == owner(), "Not authorized");
        require(r.status == Status.Pending, "Not pending");

        r.status = Status.Cancelled;

        // refund tokens (ETH was already sent to oracle)
        r.token.safeTransfer(r.user, r.amount);

        emit Cancelled(requestId);
    }

    /// @notice Oracle writes back the risk score
    function setRiskScore(uint256 requestId, uint256 riskScore)
        external
        onlyOracle
    {
        Request storage r = requests[requestId];
        require(r.status == Status.Pending, "Not pending");
        r.riskScore = riskScore;
        emit RiskScoreSet(requestId, riskScore);
    }

    /// @notice Oracle executes the transfer, fee is charged if approved
    function execute(uint256 requestId) external onlyOracle {
        Request storage r = requests[requestId];
        require(r.status == Status.Pending, "Not pending");
        r.status = Status.Executed;

        bool approved = r.riskScore < riskThreshold;
        if (approved) {
            uint256 fee = (r.amount * feeBP) / 10000;
            uint256 net = r.amount - fee;
            r.token.safeTransfer(feeRecipient, fee);
            r.token.safeTransfer(r.recipient, net);
        } else {
            // failed check → return full amount to user
            r.token.safeTransfer(r.user, r.amount);
        }

        emit Executed(requestId, approved);
    }
}