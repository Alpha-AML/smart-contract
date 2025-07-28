require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1337
      }
    }
  },
  // Add support for Foundry lib imports
  compilers: {
    solc: {
      settings: {
        remappings: [
          "@openzeppelin/contracts=lib/openzeppelin-contracts/contracts/",
          "@safe-global/=lib/safe-contracts/contracts/",
          "safe-contracts/=lib/safe-contracts/contracts/"
        ]
      }
    }
  },
  networks: {
    ethereum: {
      url: process.env.ETHEREUM_MAINNET_RPC,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 1,
      gas: "auto",
      gasPrice: "auto"
    },
    arbitrum: {
      url: process.env.ARBITRUM_MAINNET_RPC,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 42161,
      gas: "auto",
      gasPrice: "auto",
      // Arbitrum-specific Etherscan verification endpoint
      verify: {
        etherscan: {
          apiUrl: "https://api.arbiscan.io",
          apiKey: process.env.ARBISCAN_API_KEY
        }
      }
    },
    base: {
      url: process.env.BASE_MAINNET_RPC,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 8453,
      gas: "auto",
      gasPrice: "auto"
    },
    bsc: {
      url: process.env.BSC_MAINNET_RPC,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 56,
      gas: "auto",
      gasPrice: "auto"
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
      ethereum: process.env.ETHERSCAN_API_KEY,
      arbitrum: process.env.ARBISCAN_API_KEY,
      base: process.env.BASESCAN_API_KEY,
      bsc: process.env.BSCSCAN_API_KEY
    },
    customChains: [
      {
        network: "ethereum",
        chainId: 1,
        urls: {
          apiURL: "https://api.etherscan.io/api",
          browserURL: "https://etherscan.io"
        }
      },
      {
        network: "arbitrum",
        chainId: 42161,
        urls: {
          apiURL: "https://api.arbiscan.io/api",
          browserURL: "https://arbiscan.io"
        }
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      },
      {
        network: "bsc",
        chainId: 56,
        urls: {
          apiURL: "https://api.bscscan.com/api",
          browserURL: "https://bscscan.com"
        }
      }
    ]
  }
};
