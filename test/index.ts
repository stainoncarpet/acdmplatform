/* eslint-disable no-undef */
/* eslint-disable no-unused-expressions */
/* eslint-disable spaced-comment */
/* eslint-disable no-unused-vars */
/* eslint-disable prettier/prettier */
/* eslint-disable node/no-missing-import */
/* eslint-disable import/no-duplicates */

import { expect } from "chai";
import { ethers, network, waffle } from "hardhat";
import { ACDMPlatform, ACDMToken } from "../typechain";

const pe = ethers.utils.parseEther;

describe("ACDM", () => {
  let ACDMToken, acdmToken: ACDMToken, ACDMPlatform, acdmPlatform: ACDMPlatform;
  let signers, deployer, user1: any, user2: any, user3: any, user4: any;

  beforeEach(async () => {
    ACDMToken = await ethers.getContractFactory("ACDMToken");
    acdmToken = await ACDMToken.deploy();
    await acdmToken.deployed();
    
    ACDMPlatform = await ethers.getContractFactory("ACDMPlatform");
    acdmPlatform = await ACDMPlatform.deploy(acdmToken.address, 86400);
    await acdmPlatform.deployed();

    await acdmToken.setPlatform(acdmPlatform.address);

    signers = await ethers.getSigners();
    [deployer, user1, user2, user3, user4] = signers;

    // console.log("DEPLOYER", deployer.address)
    // console.log("[USER1]", user1.address)
    // console.log("[USER2]", user2.address)
    // console.log("[USER3]", user3.address)
  });

  it("Should register self and referrers", async () => {
    await expect(acdmPlatform.connect(user1).register(user1.address))
      .to.be.revertedWith("Can't register oneself as referrer")
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
  });

  it("Should start and conduct sale round (without referrers)", async () => {
    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", pe("0.00001"))
    ;

    await acdmPlatform.connect(user3).buyACDM({value: pe("1")});
  });

  it("Should start and conduct sale round (with referrers)", async () => {
    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", pe("0.00001"))
    ;

    await acdmPlatform.connect(user1).register("0x0000000000000000000000000000000000000000");
    await acdmPlatform.connect(user2).register(user1.address);
    await acdmPlatform.connect(user3).register(user2.address);

    // referrer0 = direct referrer, referrer1 = referrer of referrer0
    const referrer1BalanceBefore = await waffle.provider.getBalance(user1.address);
    const referrer0BalanceBefore = await waffle.provider.getBalance(user2.address);

    await acdmPlatform.connect(user3).buyACDM({value: pe("1")});

    // referrer0 = direct referrer, referrer1 = referrer of referrer0
    const referrer1BalanceAfter = await waffle.provider.getBalance(user1.address);
    const referrer0BalanceAfter = await waffle.provider.getBalance(user2.address);

    // referrer0 gets 0.05 eth and referrer1 gets 0.03 eth
    expect(referrer1BalanceAfter.sub(referrer1BalanceBefore))
    .to.be.equal(pe("0.03"))
    ;
    expect(referrer0BalanceAfter.sub(referrer0BalanceBefore))
    .to.be.equal(pe("0.05"))
    ;
  });

  it("Should start and conduct trade round (without referrers)", async () => {
    await expect(acdmPlatform.startTradeRound())
    .to.be.revertedWith("This action is possible only after first sale round start")
    ;

    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", pe("0.00001"))
    ;

    await acdmPlatform.connect(user1).buyACDM({value: pe("1")});

    await expect(acdmPlatform.startTradeRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Trade", 0)
    ;

    await acdmToken.connect(user1).approve(acdmPlatform.address, pe("1000"));

    await expect(
      acdmPlatform
        .connect(user1)
        .addOrder(true, pe("1000"), pe("0.00002"))
    )
    .to.emit(acdmPlatform, "OrderAdded")
    .withArgs("Sell", pe("1000"), pe("0.00002"))
  
    await expect(
      acdmPlatform
        .connect(user2)
        .addOrder(false, pe("100000"), pe("0.00001"), { value: pe("1") })
    )
    .to.emit(acdmPlatform, "OrderAdded")
    .withArgs("Buy", pe("100000"), pe("0.00001"))
    ;

    await expect(acdmPlatform.connect(user2).removeOrder(0))
    .to.be.revertedWith("Only creator can cancel order")
    ;

    await expect(acdmPlatform.connect(user2).removeOrder(1))
    .to.emit(acdmPlatform, "OrderRemoved")
    .withArgs("Buy", pe("100000"), pe("0.00001"))
    ;
  });
});

