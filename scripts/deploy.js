const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("Deploying to Arbitrum...");
  
  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  // Check balance
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ETH");
  
  // Get constructor parameters
  const oracleAddress = process.env.ORACLE_ADDRESS;
  const gasDeposit = process.env.GAS_DEPOSIT;
  const feeRecipient = process.env.FEE_RECIPIENT;
  
  console.log("Oracle Address:", oracleAddress);
  console.log("Gas Deposit:", gasDeposit, "wei (", ethers.formatEther(gasDeposit), "ETH )");
  console.log("Fee Recipient:", feeRecipient);
  
  // Deploy the contract with explicit gas settings
  const AlphaAMLBridge = await ethers.getContractFactory("AlphaAMLBridge");
  
  console.log("Deploying contract...");
  const alphaAmlBridge = await AlphaAMLBridge.deploy(
    oracleAddress,
    gasDeposit,
    feeRecipient,
    {
      gasLimit: 5000000, // Set explicit gas limit
      // Remove gasPrice to use network default
    }
  );
  
  // Wait for deployment
  await alphaAmlBridge.waitForDeployment();
  const contractAddress = await alphaAmlBridge.getAddress();
  
  console.log("AlphaAMLBridge deployed to:", contractAddress);
  console.log("Transaction hash:", alphaAmlBridge.deploymentTransaction().hash);
  
  // Wait a bit before verification
  console.log("Waiting 30 seconds before verification...");
  await new Promise(resolve => setTimeout(resolve, 30000));
  
  // Verify the contract
  try {
    await hre.run("verify:verify", {
      address: contractAddress,
      constructorArguments: [
        oracleAddress,
        gasDeposit,
        feeRecipient
      ],
    });
    console.log("Contract verified successfully");
  } catch (error) {
    console.log("Verification failed:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
