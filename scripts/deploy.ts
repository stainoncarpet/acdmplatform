/* eslint-disable node/no-missing-import */
/* eslint-disable prettier/prettier */

import { ethers } from "hardhat";

const main = async () => {
  const ACDMToken = await ethers.getContractFactory("ACDMToken");
  const acdmToken = await ACDMToken.deploy();
  await acdmToken.deployed();

  const ACDMPlatform = await ethers.getContractFactory("ACDMPlatform");
  const acdmPlatform = await ACDMPlatform.deploy(acdmToken.address, 86400);
  await acdmPlatform.deployed();

  console.log("ACDMToken deployed to:", acdmToken.address, "by", await acdmToken.signer.getAddress());
  console.log("ACDMPlatform deployed to:", acdmPlatform.address, "by", await acdmPlatform.signer.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});