//SPDX-License-Identifier: MIT

pragma solidity >=0.8.12 <0.9.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ACDMPlatform is Ownable, ReentrancyGuard {
    event RoundStarted(string indexed mode, uint256 indexed price);
    event RoundEnded(string indexed mode, uint256 indexed price);
    event TokenBought(address indexed buyer, uint256 indexed amount);
    event OrderAdded(string indexed otype, uint256 indexed amount, uint256 indexed price);
    event OrderRemoved(string indexed otype, uint256 indexed amount, uint256 indexed price);
    event OrderRedeemed(string indexed otype, uint256 indexed amount, uint256 indexed price);

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

    struct UserOrder {
        bool isSell;
        bool isActive;
        address creator;
        uint256 amount;
        uint256 price;
    }

    address public immutable TOKEN;
    uint256 public immutable ROUND_TIME;
    uint256 public roundCount;
    mapping(address => address[]) public referrersOf; // item0 - direct referrer, item1 - referrer of referrer
    mapping(address => bool) public isRegistered;
    mapping(uint256 => PlatformSaleRound) public saleRounds;
    mapping(uint256 => PlatformTradeRound) public tradeRounds;
    mapping(uint256 => UserOrder[]) public tradeOrders;

    constructor(address token, uint256 roundTime) {
        TOKEN = token;
        ROUND_TIME = roundTime;
    }

    // offset 0 = before creating new entity, offset 1 = after creating new antity
    modifier onlyDuring(bytes32 what, uint8 offset) {
        bool isSaleRoundCurrent = (roundCount - offset) % 2 == 0;

        if(roundCount > offset) {
            require(isSaleRoundCurrent ? !saleRounds[roundCount].hasEnded : !tradeRounds[roundCount].hasEnded, "Round has ended");
        }

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
        require(referrersOf[referrer].length > 0 ? referrersOf[referrer][0] != msg.sender : true);

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

    // SALE
    function startSaleRound() external onlyDuring("trade", 0) onlyOwner {
        uint256 newPrice = getNewSaleRoundPrice();
        uint256 amountToMint = getSaleRoundVolume(newPrice);

        TOKEN.call(abi.encodeWithSignature("mint(uint256)", amountToMint));

        PlatformSaleRound memory newRound = PlatformSaleRound({
            startedAt: block.timestamp,
            price: newPrice,
            volumeAvailable: amountToMint,
            volumeTransacted: 0,
            hasEnded: false
        });

        saleRounds[roundCount++] = newRound;

        emit RoundStarted("Sale", newRound.price);
    }

    // нужно использовать модификатор noreentrancy
    function buyACDM() external payable onlyDuring("sale", 1) onlyAfterStart nonReentrant {
        require(msg.value > 0, "Value is 0");

        PlatformSaleRound storage round = saleRounds[roundCount - 1];

        uint256 fullAmountToBuy = msg.value / round.price * 10**18;
        uint256 lastAvailableAmount = round.volumeAvailable - round.volumeTransacted;

        if(lastAvailableAmount > fullAmountToBuy) {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, fullAmountToBuy));
            round.volumeTransacted += fullAmountToBuy;
            emit TokenBought(msg.sender, fullAmountToBuy);
        } else if (lastAvailableAmount == fullAmountToBuy) {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, fullAmountToBuy));
            round.volumeTransacted = round.volumeAvailable;
            round.hasEnded = true;
            emit RoundEnded("Sale", round.price);
            emit TokenBought(msg.sender, fullAmountToBuy);
        } else {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, lastAvailableAmount));
            round.volumeTransacted = round.volumeAvailable;
            uint256 ethToReturn = msg.value - lastAvailableAmount * round.price;
            payable(msg.sender).transfer(ethToReturn);
            round.hasEnded = true;
            emit RoundEnded("Sale", round.price);
            emit TokenBought(msg.sender, lastAvailableAmount);
        }

        address[] memory refs = referrersOf[msg.sender];

        if(refs.length == 1) {
            payable(refs[0]).transfer(msg.value * 5 / 100);
        } else if (refs.length == 2) {
            payable(refs[0]).transfer(msg.value * 5 / 100);
            payable(refs[1]).transfer(msg.value * 3 / 100);
        }
    }

    // TRADE @6:00
    // не может закончиться раньше чем 3 дня
    // если никто не купил или никто ордер не создавал мы стартуем и сразу заканчиваем sale-раунд
    // как только в сейл-раунде закончатся токены или по истечению 3 дней мы сможем запустить trade-раунд
    function startTradeRound() external onlyDuring("sale", 0) onlyAfterStart onlyOwner {
        PlatformSaleRound storage previousSaleRound = saleRounds[roundCount - 1];

        require(previousSaleRound.hasEnded || (block.timestamp >= (previousSaleRound.startedAt + ROUND_TIME)),
            "Trade round can't get started"
        );

        if(previousSaleRound.volumeAvailable - previousSaleRound.volumeTransacted > 0) {
            previousSaleRound.hasEnded  = true;
            emit RoundEnded("Sale", previousSaleRound.price);
            TOKEN.call(abi.encodeWithSignature("burn(uint256)", previousSaleRound.volumeAvailable - previousSaleRound.volumeTransacted));
        }

        PlatformTradeRound memory newRound = PlatformTradeRound({
            startedAt: block.timestamp,
            volumeTransacted: 0,
            hasEnded: false
        });

        tradeRounds[roundCount++] = newRound;

        emit RoundStarted("Trade", 0);
    }

    // если ордер никто не купил и он не отменился: то токены должны перейти на след раунд, изначальная цена остается
    function addOrder(bool isSell, uint256 amount, uint256 price) external payable onlyDuring("trade", 1) nonReentrant {
        bool success;

        if(!isSell) {
            success = msg.value / (amount * price / 10**18) >= 1;
            if (!success) { payable(msg.sender).transfer(msg.value); }
        } else {
            (success,) = TOKEN.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount));
        }
        
        require(success, "Failed to place order");
        
        UserOrder memory newOrder = UserOrder({
            isSell: isSell,
            creator: msg.sender,
            amount: amount,
            price: price,
            isActive: true
        });

        tradeOrders[roundCount - 1].push(newOrder);

        emit OrderAdded(isSell ? "Sell" : "Buy", amount, price);
    }

    function removeOrder(uint256 id) external onlyDuring("trade", 1) {
        UserOrder[] storage orders = tradeOrders[roundCount - 1];

        require(id < orders.length, "Order with specified id doesn't exist");
        require(orders[id].creator == msg.sender, "Only creator can cancel order");

        bool success;

        if(!orders[id].isSell) {
            uint256 ethToReturn = orders[id].amount * orders[id].price / 10**18;
            payable(orders[id].creator).transfer(ethToReturn);
            success = true;
        } else {
            (success,) = TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, orders[id].amount));
        }
        
        require(success, "Failed to cancel order");
        orders[id].isActive = false;
        emit OrderRemoved(orders[id].isSell ? "Sell" : "Buy", orders[id].amount, orders[id].price);
    }

    // // можно выкупить частично
    function redeemOrder(uint256 id, uint256 amount) external payable onlyDuring("trade", 1) nonReentrant {
        UserOrder[] storage orders = tradeOrders[roundCount - 1];

        require(id < orders.length, "Order with specified id doesn't exist");
        require(orders[id].isActive, "Order is no longer active");

        if(orders[id].isSell) {
            // caller is buying tokens with eth
            require(msg.value > 0);
        } else {
            // caller is selling tokens for eth
            TOKEN.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", arg));
        }

        // bool isSell;
        // bool isActive;
        // address creator;
        // uint256 amount;
        // uint256 price;

        emit OrderRedeemed("Buy", orders[id].amount, orders[id].price);
    }

    // qty of sold t0kens is determined by volume of previous round / new price 
    function getSaleRoundVolume(uint256 newPrice) private view returns(uint256) {
        return roundCount == 0 
            ? 100000 * 10**18
            : tradeRounds[roundCount - 1].volumeTransacted / newPrice
        ;
    }

    function getNewSaleRoundPrice() private view returns(uint256) {
        return roundCount == 0 
            ? 0.00001 ether 
            : (saleRounds[roundCount - 2].price * 103) / 100 + 0.000004 ether
        ;
    }
}
