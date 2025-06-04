// scripts/deploy.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with", deployer.address);

  const oracleAddr   = process.env.ORACLE_ADDRESS;
  const gasDeposit   = process.env.GAS_DEPOSIT;       // in wei, as string
  const feeRecipient = process.env.FEE_RECIPIENT;

  if (!oracleAddr || !gasDeposit || !feeRecipient) {
    throw new Error("Missing ORACLE_ADDRESS, GAS_DEPOSIT or FEE_RECIPIENT in .env");
  }

  const AMLBridge = await ethers.getContractFactory("AMLBridge");
  const bridge = await AMLBridge.deploy(
    oracleAddr,
    gasDeposit,
    feeRecipient
  );

  // Wait for the deployment transaction to be mined
  await bridge.waitForDeployment();

  // Use `bridge.target` to get the deployed address under ethers v6
  console.log("AMLBridge deployed to:", bridge.target);
}

main()
  .then(() => process.exit(0))
  .catch(err => {
    console.error(err);
    process.exit(1);
  });

