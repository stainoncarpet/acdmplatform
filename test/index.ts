/* eslint-disable spaced-comment */
/* eslint-disable no-unused-vars */
/* eslint-disable prettier/prettier */
/* eslint-disable node/no-missing-import */
/* eslint-disable import/no-duplicates */

import { expect } from "chai";
import { ethers } from "hardhat";
import { ACDMToken } from "../typechain";
import { ACDMPlatform } from "../typechain";

describe("ACDM", () => {
  let ACDMToken, acdmToken: ACDMToken, ACDMPlatform, acdmPlatform: ACDMPlatform;
  let signers, deployer, user1: any, user2: any, user3: any, user4: any;

  before(async () => {
    ACDMToken = await ethers.getContractFactory("ACDMToken");
    acdmToken = await ACDMToken.deploy();
    await acdmToken.deployed();
    
    ACDMPlatform = await ethers.getContractFactory("ACDMPlatform");
    acdmPlatform = await ACDMPlatform.deploy(acdmToken.address, 86400);
    await acdmPlatform.deployed();

    await acdmToken.setPlatform(acdmPlatform.address);

    signers = await ethers.getSigners();
    [deployer, user1, user2, user3, user4] = signers;

    console.log("DEPLOYER", deployer.address)
    console.log("[USER1]", user1.address)
    console.log("[USER2]", user2.address)
    console.log("[USER3]", user3.address)
  });

  it("Should register self and referrers", async () => {
    await expect(acdmPlatform.connect(user1).register(user1.address))
      .to.be.revertedWith("One can't register oneself as referrer")
    ;

    await expect(acdmPlatform.connect(user1).register(user2.address))
      .to.be.revertedWith("Referrer is not registered")
    ;

    await acdmPlatform.connect(user1).register("0x0000000000000000000000000000000000000000");
    await acdmPlatform.connect(user2).register(user1.address);
    await acdmPlatform.connect(user3).register(user2.address);

    await acdmPlatform.connect(user4).register("0x0000000000000000000000000000000000000000");
    await expect(acdmPlatform.connect(user4).register(user1.address))
    .to.be.revertedWith("Already registered")
    ;

    expect(await acdmPlatform.isRegistered(user1.address)).to.be.equal(true);
    expect(await acdmPlatform.isRegistered(user2.address)).to.be.equal(true);
    expect(await acdmPlatform.isRegistered(user3.address)).to.be.equal(true);

    // referrer doesn't exist, accessing array with 0 items
    await expect(acdmPlatform.referrersOf(user1.address, 0))
    .to.be.reverted
    ;

    expect(await acdmPlatform.referrersOf(user3.address, 0))
    .to.be.equal(user2.address)
    ;

    expect(await acdmPlatform.referrersOf(user3.address, 1))
    .to.be.equal(user1.address)
    ;

    return true;
  });
});
