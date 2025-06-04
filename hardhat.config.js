require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    arbitrum: {
      url: process.env.ARBITRUM_MAINNET_RPC,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 42161,
      gas: "auto",
      gasPrice: "auto",
      // Add these Arbitrum-specific settings
      verify: {
        etherscan: {
          apiUrl: "https://api.arbiscan.io",
          apiKey: process.env.ETHERSCAN_API_KEY
        }
      }
    },
    hardhat: {
      forking: {
        url: process.env.ARBITRUM_MAINNET_RPC,
        enabled: false
      }
    }
  },
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ETHERSCAN_API_KEY
    },
    customChains: [
      {
        network: "arbitrumOne",
        chainId: 42161,
        urls: {
          apiURL: "https://api.arbiscan.io/api",
          browserURL: "https://arbiscan.io"
        }
      }
    ]
  }
};
