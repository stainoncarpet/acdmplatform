//SPDX-License-Identifier: MIT

pragma solidity >=0.8.12 <0.9.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ACDMPlatform is Ownable, ReentrancyGuard {
    event RoundStarted(string indexed mode, uint256 indexed price);
    event RoundEnded(string indexed mode, uint256 indexed price);
    event TokenBought(address indexed buyer, uint256 indexed amount);
    event OrderAdded(uint256 indexed amount, uint256 indexed price);
    event OrderRemoved(uint256 indexed id, uint256 indexed price);
    event OrderRedeemed(uint256 indexed amount, uint256 indexed price);

    struct PlatformSaleRound {
        uint256 startedAt;
        uint256 price; 
        uint256 volumeAvailable; 
        uint256 volumeTransacted;
        bool hasEnded;
    }

    struct PlatformTradeRound {
        uint256 startedAt;
        uint256 volumeTransacted;
        bool hasEnded;
    }

    struct UserTradeOrder {
        address creator;
        uint256 volumeAvailable; 
        uint256 volumeTransacted;
        uint256 price;
    }
    
    // item0 - direct referrer, item1 - referrer of referrer
    mapping(address => address[]) public referrersOf;
    mapping(address => bool) public isRegistered;
    mapping(uint256 => PlatformSaleRound) public saleRounds;
    mapping(uint256 => PlatformTradeRound) public tradeRounds;
    mapping(uint256 => UserTradeOrder[]) public tradeOrders;
    uint256 public roundCount;
    uint256 public immutable ROUND_TIME;
    address public immutable TOKEN;

    constructor(address token, uint256 roundTime) {
        TOKEN = token;
        ROUND_TIME = roundTime;
    }

    // offset 0 = before starting new round, offset 1 = after starting new round
    modifier onlyDuring(bytes32 what, uint8 offset) {
        bool isSaleRoundCurrent = (roundCount - offset) % 2 == 0;

        // if(roundCount > offset) {
        //     require(
        //         isSaleRoundCurrent 
        //             ? !saleRounds[roundCount].hasEnded 
        //             : !tradeRounds[roundCount].hasEnded, 
        //         "Round has ended"
        //     );
        // }

        if(what == "sale" && offset == 1) {
            require(isSaleRoundCurrent, "Allowed only during sale periods");
        } else if(what == "trade" && offset == 1) {
            require(!isSaleRoundCurrent, "Allowed only during trade periods");
        }
        _;
    }

    modifier onlyAfterStart() {
        require(roundCount != 0, "This action is possible only after first sale round start");
        _;
    }

    function register(address referrer) external {
        require(!isRegistered[msg.sender], "Already registered");
        require(msg.sender != referrer, "Can't register oneself as referrer");
        require(referrersOf[referrer].length > 0 ? referrersOf[referrer][0] != msg.sender : true, "Circular referrer relation");

        if(referrer == address(0)) {
            isRegistered[msg.sender] = true;
        } else {
            require(isRegistered[referrer], "Referrer is not registered");

            referrersOf[msg.sender].push(referrer);
            isRegistered[msg.sender] = true;

            // if referrer has referrer, add it to caller's list of referrers
            if(referrersOf[referrer].length > 0) { referrersOf[msg.sender].push(referrersOf[referrer][0]); }
        }
    }

    function startSaleRound() external onlyDuring("trade", 0) onlyOwner {
        // check if we can close ongoing trade round
        if (roundCount > 0) {
            require(hasRoundEnded("trade"), "Trade round is still ongoing");
        }

        uint256 newPrice = getNewSaleRoundPrice();
        uint256 amountToMint = getSaleRoundVolume(newPrice);

        (bool success,) = TOKEN.call(abi.encodeWithSignature("mint(uint256)", amountToMint));
        require(success, "Failed to mint");

        PlatformSaleRound memory newRound = PlatformSaleRound({
            startedAt: block.timestamp,
            price: newPrice,
            volumeAvailable: amountToMint,
            volumeTransacted: 0,
            hasEnded: false
        });

        saleRounds[roundCount++] = newRound;

        emit RoundStarted("Sale", newRound.price);

        // if during previous trade round there was no activity we immediately close sale round
        if (roundCount > 2 && (tradeOrders[roundCount - 2].length == 0 || tradeRounds[roundCount - 2].volumeTransacted == 0)) {
            closeSaleRoundAndBurn();
        }
    }

    function buyACDM() external payable onlyDuring("sale", 1) onlyAfterStart nonReentrant {
        require(msg.value > 0, "Value is 0");

        PlatformSaleRound storage round = saleRounds[roundCount - 1];

        uint256 maxAmountToBuy = msg.value / round.price * 10**18;
        console.log("maxAmountToBuy", maxAmountToBuy);
        uint256 lastAvailableAmount = round.volumeAvailable - round.volumeTransacted;
        console.log(round.volumeAvailable, round.volumeTransacted);
        console.log("lastAvailableAmount", lastAvailableAmount);

        if(lastAvailableAmount > maxAmountToBuy) {
            (bool success,) = TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, maxAmountToBuy));
            require(success, "Failed: 1");
            round.volumeTransacted += maxAmountToBuy;
            emit TokenBought(msg.sender, maxAmountToBuy);
            rewardReferrers(msg.sender, msg.value, 50, 30);
        } else if (lastAvailableAmount == maxAmountToBuy) {
            (bool success,) = TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, maxAmountToBuy));
            require(success, "Failed: 2");
            round.volumeTransacted = round.volumeAvailable;
            round.hasEnded = true;
            emit TokenBought(msg.sender, maxAmountToBuy);
            emit RoundEnded("Sale", round.price);
            rewardReferrers(msg.sender, msg.value, 50, 30);
        } else {
            (bool success,) = TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, lastAvailableAmount));
            console.log("lastAvailableAmount", lastAvailableAmount);
            require(success, "Failed: 3");
            round.volumeTransacted = round.volumeAvailable;
            uint256 ethToReturn = msg.value - (lastAvailableAmount * round.price) / 10**18;
            payable(msg.sender).transfer(ethToReturn);
            round.hasEnded = true;
            emit TokenBought(msg.sender, lastAvailableAmount);
            emit RoundEnded("Sale", round.price);
            rewardReferrers(msg.sender, msg.value - ethToReturn, 50, 30);
        }
    }

    // как только в сейл-раунде закончатся токены или по истечению 3 дней мы сможем запустить trade-раунд
    function startTradeRound() external onlyDuring("sale", 0) onlyAfterStart onlyOwner {
        require(saleRounds[roundCount - 1].hasEnded || (block.timestamp >= (saleRounds[roundCount - 1].startedAt + ROUND_TIME)),
            "Trade round can't get started"
        );

        // close sale round if it wasn't closed before but time expired
        if(!saleRounds[roundCount - 1].hasEnded) { closeSaleRoundAndBurn(); }

        PlatformTradeRound memory newRound = PlatformTradeRound({
            startedAt: block.timestamp,
            volumeTransacted: 0,
            hasEnded: false
        });

        tradeRounds[roundCount++] = newRound;

        emit RoundStarted("Trade", 0);

        // carry over remaining orders from previous trade round
        if(roundCount > 3) {
            for (uint256 i = 0; i < tradeOrders[roundCount - 3].length; i++) {
                if(tradeOrders[roundCount - 3][i].volumeAvailable > 0) {
                    tradeOrders[roundCount - 1].push(tradeOrders[roundCount - 3][i]);
                }
            }
            // this doesn't have to be deleted because we always manipulate the latest arrays
            // delete tradeOrders[roundCount - 3];
        }
    }

    function addOrder(uint256 amount, uint256 price) external onlyDuring("trade", 1) {
        (bool success,) = TOKEN.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount));
        console.log("addOrder", amount, price); // correct
        require(success, "Failed to place order");
        
        UserTradeOrder memory newOrder = UserTradeOrder({
            creator: msg.sender,
            volumeAvailable: amount,
            volumeTransacted: 0,
            price: price
        });

        tradeOrders[roundCount - 1].push(newOrder);

        emit OrderAdded(amount, price);
    }

    function removeOrder(uint256 id) external onlyDuring("trade", 1) {
        UserTradeOrder[] storage orders = tradeOrders[roundCount - 1];

        require(id < orders.length, "Order with specified id doesn't exist");
        require(orders[id].creator == msg.sender, "Only creator can cancel order");

        // return unsold tokens to seller
        (bool success,) = TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, orders[id].volumeAvailable));
        
        require(success, "Failed to remove order");
        orders[id].volumeAvailable = 0;
        emit OrderRemoved(id, orders[id].price);
    }

    function redeemOrder(uint256 id) external payable onlyDuring("trade", 1) nonReentrant {
        require(!hasRoundEnded("trade"), "Round has ended");
        
        UserTradeOrder[] storage orders = tradeOrders[roundCount - 1];

        require(id < orders.length, "Order with specified id doesn't exist");
        require(orders[id].volumeAvailable > 0, "Order is no longer available");
        require(msg.value >= 0.00001 ether, "Minimum amount is 0.00001 ETH");

        uint256 maxAmountToBuyAmount = msg.value / orders[id].price * 10**18;

        if(orders[id].volumeAvailable > maxAmountToBuyAmount) {
            TOKEN.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", orders[id].creator, msg.sender, maxAmountToBuyAmount));

            orders[id].volumeAvailable -= maxAmountToBuyAmount;
            orders[id].volumeTransacted += maxAmountToBuyAmount;
            tradeRounds[roundCount - 1].volumeTransacted += msg.value;
            
            rewardReferrers(msg.sender, msg.value, 25, 25);
            emit TokenBought(msg.sender, maxAmountToBuyAmount);  
        } else if (orders[id].volumeAvailable == maxAmountToBuyAmount) {
            TOKEN.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", orders[id].creator, msg.sender, maxAmountToBuyAmount));
            orders[id].volumeAvailable = 0;
            orders[id].volumeTransacted += maxAmountToBuyAmount;
            tradeRounds[roundCount - 1].volumeTransacted += msg.value;
            rewardReferrers(msg.sender, msg.value, 25, 25);
            emit TokenBought(msg.sender, maxAmountToBuyAmount);
            emit OrderRedeemed(orders[id].volumeAvailable + orders[id].volumeTransacted, orders[id].price);
        } else {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, orders[id].volumeAvailable));
            uint256 ethToReturn = msg.value - (orders[id].volumeAvailable * orders[id].price) / 10**18;
            payable(msg.sender).transfer(ethToReturn);

            emit TokenBought(msg.sender, orders[id].volumeAvailable);
            emit OrderRedeemed(orders[id].volumeAvailable + orders[id].volumeTransacted, orders[id].price);
            rewardReferrers(msg.sender, msg.value - ethToReturn, 25, 25);

            orders[id].volumeTransacted += orders[id].volumeAvailable;
            tradeRounds[roundCount - 1].volumeTransacted += msg.value - ethToReturn;
            orders[id].volumeAvailable = 0;
        }
    }

    // qty of sold t0kens is determined by volume of previous round / new price 
    function getSaleRoundVolume(uint256 newPrice) private view returns(uint256) {
        if(roundCount > 0) {
            console.log("calculating new volume");
            console.log(tradeRounds[roundCount - 1].volumeTransacted);
            console.log(newPrice);
            
            
            uint256 ddd = tradeRounds[roundCount - 1].volumeTransacted / newPrice * 10**18;
            console.log("new round volume", ddd);
        }

        return roundCount == 0 
            ? 100000 * 10**18 
            : tradeRounds[roundCount - 1].volumeTransacted / newPrice * 10**18;
    }

    function getNewSaleRoundPrice() private view returns(uint256) {
        return roundCount == 0 
            ? 0.00001 ether 
            : (saleRounds[roundCount - 2].price * 103) / 100 + 0.000004 ether
        ;
    }

    function rewardReferrers(address referral, uint256 value, uint8 reward0, uint8 reward1) private {
        address[] memory refs = referrersOf[referral];

        if(refs.length == 1) {
            payable(refs[0]).transfer(value * reward0 / 1000);
        } else if (refs.length == 2) {
            payable(refs[0]).transfer(value * reward0 / 1000);
            payable(refs[1]).transfer(value * reward1 / 1000);
        }
    }

    function hasRoundEnded(bytes32 roundType) private returns(bool){
        if(roundType == "trade" && block.timestamp >= tradeRounds[roundCount - 1].startedAt + ROUND_TIME) {
            tradeRounds[roundCount - 1].hasEnded = true; 
            return true;
        } else if(roundType == "sale" && block.timestamp >= saleRounds[roundCount - 1].startedAt + ROUND_TIME) {
            saleRounds[roundCount - 1].hasEnded = true;
            return true;
        } else {
            return false;
        }
    }

    function closeSaleRoundAndBurn() private {
        PlatformSaleRound memory previousSaleRound = saleRounds[roundCount - 1];

        if(previousSaleRound.volumeAvailable - previousSaleRound.volumeTransacted > 0) {
            saleRounds[roundCount - 1].hasEnded  = true;
            emit RoundEnded("Sale", previousSaleRound.price);
            TOKEN.call(abi.encodeWithSignature("burn(uint256)", previousSaleRound.volumeAvailable - previousSaleRound.volumeTransacted));
        }
    }
}

// 6993006993000000000000000000 - bad

// 100000000000000000000000 from 1 eth
// 26737960000000000000000 from 0.5 eth

// 18700000000000
// 14300000000000
// 20000000000000
// 30000000000000