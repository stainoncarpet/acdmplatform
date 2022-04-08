/* eslint-disable no-undef */
/* eslint-disable no-unused-expressions */
/* eslint-disable spaced-comment */
/* eslint-disable no-unused-vars */
/* eslint-disable prettier/prettier */
/* eslint-disable node/no-missing-import */
/* eslint-disable import/no-duplicates */

import { expect } from "chai";
import { ethers, network, waffle } from "hardhat";
import { ACDMToken } from "../typechain";
import { ACDMPlatform } from "../typechain";

const parseEth = ethers.utils.parseEther;

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
/*
  it("Should start and conduct sale round 1 (without referrers)", async () => {
    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", parseEth("0.00001"))
    ;

    await acdmPlatform.connect(user3).buyACDM({value: parseEth("1")});
  });

  it("Should start and conduct sale round 2 (without referrers)", async () => {
    // SALE ROUND 1
    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", parseEth("0.00001"))
    ;

    await acdmPlatform.connect(user1).buyACDM({value: parseEth("1")});

    // TRADE ROUND 1
    await expect(acdmPlatform.startTradeRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Trade", 0)
    ;

    await acdmToken.connect(user1).approve(acdmPlatform.address, parseEth("100000"));

    // user1 adds sell order
    await expect(
      acdmPlatform
        .connect(user1)
        .addOrder(parseEth("100000"), parseEth("0.00002"))
    )
    .to.emit(acdmPlatform, "OrderAdded")
    .withArgs(parseEth("100000"), parseEth("0.00002"))
    ;

    const orderAmount = "100000";

    // user2 buys 90000/100000 tokens
    await expect(
      acdmPlatform
        .connect(user2)
        .redeemOrder(0, {value: parseEth("2")})
    )
    .to.emit(acdmPlatform, "TokenBought")
    .withArgs(user2.address, parseEth(orderAmount))
    ;

    // try to start sale round prematurely
    await expect(acdmPlatform.startSaleRound())
    .to.be.revertedWith("Trade round is still ongoing")
    ;

    // fast forward 3+ days to try again then
    await network.provider.request({ method: "evm_increaseTime", params: [90000] });
    await network.provider.request({ method: "evm_mine", params: [] });

    // SALE ROUND 2
    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", parseEth("0.0000143"))
    ;

    //console.log(await acdmPlatform.saleRounds(2));

    // roundId
    //console.log(await acdmPlatform.tradeRounds(1));
    // roundId, orderId
    //console.log(await acdmPlatform.tradeOrders(1, 0));
  });
*/
  it("Should start and conduct sale round 3 (without referrers)", async () => {
    // SALE ROUND 1
    await acdmPlatform.startSaleRound();
    await acdmPlatform.connect(user1).buyACDM({value: parseEth("1")});

    // TRADE ROUND 1
    await acdmPlatform.startTradeRound();
    await acdmToken.connect(user1).approve(acdmPlatform.address, parseEth("100000"));

    // user1 adds sell order
    await acdmPlatform.connect(user1)
                      .addOrder(parseEth("100000"), parseEth("0.00002"))

    const orderAmount = "100000";

    // user2 buys all tokens
    await acdmPlatform.connect(user2)
          .redeemOrder(0, {value: parseEth("3")})

    // fast forward 3+ days
    await network.provider.request({ method: "evm_increaseTime", params: [90000] });
    await network.provider.request({ method: "evm_mine", params: [] });

    // SALE ROUND 2
    await acdmPlatform.startSaleRound();

    console.log("supply", await acdmToken.totalSupply())
    console.log("PLATFORM BALANCE", await acdmToken.balanceOf(acdmPlatform.address))

    await acdmPlatform.connect(user3).buyACDM({value: parseEth("10")});

    console.log("BALANCE", await acdmToken.balanceOf(user3.address))

    //TRADE ROUND 2
    await acdmPlatform.startTradeRound();
    
    await acdmToken.connect(user3).approve(acdmPlatform.address, parseEth("50000"));
    
    console.log("token balance", await acdmToken.balanceOf(user3.address), ethers.utils.formatEther(await acdmToken.balanceOf(user3.address)))
    
    // user3 adds sell order
    await acdmPlatform.connect(user3)
      .addOrder(parseEth("50000"), parseEth("0.00003"))

    // user2 buys all tokens
    await acdmPlatform.connect(user4)
      .redeemOrder(0, {value: parseEth("0.57")})

    // fast forward 3+ days
    await network.provider.request({ method: "evm_increaseTime", params: [90000] });
    await network.provider.request({ method: "evm_mine", params: [] });
  });
/*
  it("Should start and conduct sale round 1 (with referrers)", async () => {
    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", parseEth("0.00001"))
    ;

    await acdmPlatform.connect(user1).register("0x0000000000000000000000000000000000000000");
    await acdmPlatform.connect(user2).register(user1.address);
    await acdmPlatform.connect(user3).register(user2.address);

    // referrer0 = direct referrer, referrer1 = referrer of referrer0
    const referrer1BalanceBefore = await waffle.provider.getBalance(user1.address);
    const referrer0BalanceBefore = await waffle.provider.getBalance(user2.address);

    await acdmPlatform.connect(user3).buyACDM({value: parseEth("1")});

    // referrer0 = direct referrer, referrer1 = referrer of referrer0
    const referrer1BalanceAfter = await waffle.provider.getBalance(user1.address);
    const referrer0BalanceAfter = await waffle.provider.getBalance(user2.address);

    // referrer0 gets 0.05 eth and referrer1 gets 0.03 eth
    expect(referrer1BalanceAfter.sub(referrer1BalanceBefore))
    .to.be.equal(parseEth("0.03"))
    ;
    expect(referrer0BalanceAfter.sub(referrer0BalanceBefore))
    .to.be.equal(parseEth("0.05"))
    ;
  });

  it("Should start trade round, add and remove orders (without referrers)", async () => {
    await expect(acdmPlatform.startTradeRound())
    .to.be.revertedWith("This action is possible only after first sale round start")
    ;

    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", parseEth("0.00001"))
    ;

    await acdmPlatform.connect(user1).buyACDM({value: parseEth("1")});

    await expect(acdmPlatform.startTradeRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Trade", 0)
    ;

    await acdmToken.connect(user1).approve(acdmPlatform.address, parseEth("1000"));

    const balanceBeforeAddOrder = await acdmToken.balanceOf(user1.address);
    await expect(
      acdmPlatform
        .connect(user1)
        .addOrder(parseEth("1000"), parseEth("0.00001"))
    )
    .to.emit(acdmPlatform, "OrderAdded")
    .withArgs(parseEth("1000"), parseEth("0.00001"))
    ;
    const balanceAfterAddOrder = await acdmToken.balanceOf(user1.address);

    await expect(acdmPlatform.connect(user2).removeOrder(0))
    .to.be.revertedWith("Only creator can cancel order")
    ;

    await expect(acdmPlatform.connect(user1).removeOrder(0))
    .to.emit(acdmPlatform, "OrderRemoved")
    .withArgs(0, parseEth("0.00001"))
    ;

    const balanceAfterRemoveOrder = await acdmToken.balanceOf(user1.address);
  
    expect(balanceBeforeAddOrder.sub(balanceAfterAddOrder)).to.be.equal(parseEth("1000"));
    expect(balanceBeforeAddOrder).to.be.equal(balanceAfterRemoveOrder);
  });

  it("Should start trade round, add and redeem orders (without referrers)", async () => {
    await expect(acdmPlatform.startTradeRound())
    .to.be.revertedWith("This action is possible only after first sale round start")
    ;

    await expect(acdmPlatform.startSaleRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Sale", parseEth("0.00001"))
    ;

    await acdmPlatform.connect(user1).buyACDM({value: parseEth("1")});

    await expect(acdmPlatform.startTradeRound())
    .to.emit(acdmPlatform, "RoundStarted")
    .withArgs("Trade", 0)
    ;

    //
    await acdmToken.connect(user1).approve(acdmPlatform.address, parseEth("100000"));

    await expect(
      acdmPlatform
        .connect(user1)
        .addOrder(parseEth("100000"), parseEth("0.00001"))
    )
    .to.emit(acdmPlatform, "OrderAdded")
    .withArgs(parseEth("100000"), parseEth("0.00001"))
    ;

    await expect(
      acdmPlatform
      .connect(user2)
      .redeemOrder(0, { value: parseEth("2")})
    )
    .to.emit(acdmPlatform, "TokenBought")
    .withArgs(user2.address, parseEth("100000"))
    ;

  });*/
});

