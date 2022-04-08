/* eslint-disable no-unused-vars */
/* eslint-disable prettier/prettier */

import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import * as ethers from "ethers";

dotenv.config();

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      ETHERSCAN_API_KEY: string;
      ALCHEMY_KEY: string;
      METAMASK_PRIVATE_KEY: string;
      METAMASK_PUBLIC_KEY: string;
      COINMARKETCAP_API_KEY: string;
      RINKEBY_URL: string;
      RINKEBY_WS: string;
    }
  }
}

task("register", "Register yourself or referrer address")
  .addParam("contract", "Contract address")
  .addParam("referrer", "Referrer address")
  .setAction(async (taskArguments, hre) => {
    const acdmPlatformSchema = require("./artifacts/contracts/ACDMPlatform.sol/ACDMPlatform.json");

    const alchemyProvider = new hre.ethers.providers.AlchemyProvider("rinkeby", process.env.ALCHEMY_KEY);
    const walletOwner = new hre.ethers.Wallet(process.env.METAMASK_PRIVATE_KEY, alchemyProvider);
    const acdmPlatform = new hre.ethers.Contract(taskArguments.contract, acdmPlatformSchema.abi, walletOwner);

    const registerTx = await acdmPlatform.register(taskArguments.referrer);

    console.log("Receipt: ", registerTx);
  })
;

task("startsale", "Start sale round")
  .addParam("contract", "Contract address")
  .setAction(async (taskArguments, hre) => {
    const acdmPlatformSchema = require("./artifacts/contracts/ACDMPlatform.sol/ACDMPlatform.json");

    const alchemyProvider = new hre.ethers.providers.AlchemyProvider("rinkeby", process.env.ALCHEMY_KEY);
    const walletOwner = new hre.ethers.Wallet(process.env.METAMASK_PRIVATE_KEY, alchemyProvider);
    const acdmPlatform = new hre.ethers.Contract(taskArguments.contract, acdmPlatformSchema.abi, walletOwner);

    const startSaleTx = await acdmPlatform.startSaleRound();

    console.log("Receipt: ", startSaleTx);
  })
;

task("buytoken", "Buy ACDMToken by sending ETH")
  .addParam("contract", "Contract address")
  .addParam("eth", "Amount to ETH to exchange for ACDM")
  .setAction(async (taskArguments, hre) => {
    const acdmPlatformSchema = require("./artifacts/contracts/ACDMPlatform.sol/ACDMPlatform.json");

    const alchemyProvider = new hre.ethers.providers.AlchemyProvider("rinkeby", process.env.ALCHEMY_KEY);
    const walletOwner = new hre.ethers.Wallet(process.env.METAMASK_PRIVATE_KEY, alchemyProvider);
    const acdmPlatform = new hre.ethers.Contract(taskArguments.contract, acdmPlatformSchema.abi, walletOwner);

    const buyTx = await acdmPlatform.buyACDM({value: ethers.utils.parseEther(taskArguments.eth)});

    console.log("Receipt: ", buyTx);
  })
;

task("starttrade", "Start trade round")
  .addParam("contract", "Contract address")
  .setAction(async (taskArguments, hre) => {
    const acdmPlatformSchema = require("./artifacts/contracts/ACDMPlatform.sol/ACDMPlatform.json");

    const alchemyProvider = new hre.ethers.providers.AlchemyProvider("rinkeby", process.env.ALCHEMY_KEY);
    const walletOwner = new hre.ethers.Wallet(process.env.METAMASK_PRIVATE_KEY, alchemyProvider);
    const acdmPlatform = new hre.ethers.Contract(taskArguments.contract, acdmPlatformSchema.abi, walletOwner);

    const startTradeTx = await acdmPlatform.startTradeRound();

    console.log("Receipt: ", startTradeTx);
  })
;

task("addorder", "Add sell order")
  .addParam("contract", "Contract address")
  .addParam("amount", "Amount of ACDM you'd like to sell")
  .addParam("price", "Price to sell ACDM at")
  .setAction(async (taskArguments, hre) => {
    const acdmPlatformSchema = require("./artifacts/contracts/ACDMPlatform.sol/ACDMPlatform.json");

    const alchemyProvider = new hre.ethers.providers.AlchemyProvider("rinkeby", process.env.ALCHEMY_KEY);
    const walletOwner = new hre.ethers.Wallet(process.env.METAMASK_PRIVATE_KEY, alchemyProvider);
    const acdmPlatform = new hre.ethers.Contract(taskArguments.contract, acdmPlatformSchema.abi, walletOwner);

    const addOrderTx = await acdmPlatform.addOrder(taskArguments.amount, taskArguments.price);

    console.log("Receipt: ", addOrderTx);
  })
;

task("removeorder", "Remove sell order")
  .addParam("contract", "Contract address")
  .addParam("id", "Order id")
  .setAction(async (taskArguments, hre) => {
    const acdmPlatformSchema = require("./artifacts/contracts/ACDMPlatform.sol/ACDMPlatform.json");

    const alchemyProvider = new hre.ethers.providers.AlchemyProvider("rinkeby", process.env.ALCHEMY_KEY);
    const walletOwner = new hre.ethers.Wallet(process.env.METAMASK_PRIVATE_KEY, alchemyProvider);
    const acdmPlatform = new hre.ethers.Contract(taskArguments.contract, acdmPlatformSchema.abi, walletOwner);

    const removeOrderTx = await acdmPlatform.removeOrder(taskArguments.id);

    console.log("Receipt: ", removeOrderTx);
  })
;

task("redeemorder", "Redeem sell order")
  .addParam("contract", "Contract address")
  .addParam("id", "Order id")
  .addParam("eth", "Amount of eth to spend")
  .setAction(async (taskArguments, hre) => {
    const acdmPlatformSchema = require("./artifacts/contracts/ACDMPlatform.sol/ACDMPlatform.json");

    const alchemyProvider = new hre.ethers.providers.AlchemyProvider("rinkeby", process.env.ALCHEMY_KEY);
    const walletOwner = new hre.ethers.Wallet(process.env.METAMASK_PRIVATE_KEY, alchemyProvider);
    const acdmPlatform = new hre.ethers.Contract(taskArguments.contract, acdmPlatformSchema.abi, walletOwner);

    const redeemOrderTx = await acdmPlatform.removeOrder(taskArguments.id, {value: ethers.utils.parseEther(taskArguments.eth)});

    console.log("Receipt: ", redeemOrderTx);
  })
;

const config: HardhatUserConfig = {
  solidity: "0.8.12",
  networks: {
    rinkeby: {
      url: process.env.RINKEBY_URL,
      accounts: [process.env.METAMASK_PRIVATE_KEY],
      gas: 2100000,
      gasPrice: 8000000000
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
