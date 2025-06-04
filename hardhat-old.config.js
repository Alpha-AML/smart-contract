require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.20",
  networks: {
    arbitrum: {
      url: process.env.ARBITRUM_MAINNET_RPC,
      accounts: [ process.env.PRIVATE_KEY ]
    }
  },
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ETHERSCAN_API_KEY
    }
  }
};
