// SPDX-License-Identifier: MIT

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
    
    mapping(address => mapping(uint8 => address)) public referrersOf;
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

    /// @notice register in affiliate program
    /// @dev in referrersOf, 0 - immediate referrer, 1 - referrer of referrer 0, distant referrer of sender
    /// @param referrer - address of immediate referrer (either zero address or registered user)
    function register(address referrer) external {
        require(!isRegistered[msg.sender], "Already registered");
        require(msg.sender != referrer, "Can't register oneself as referrer");
        require(referrersOf[referrer][0] != address(0) ? referrersOf[referrer][0] != msg.sender : true, "Circular referrer relation");

        if(referrer == address(0)) {
            isRegistered[msg.sender] = true;
        } else {
            require(isRegistered[referrer], "Referrer is not registered");

            referrersOf[msg.sender][0] = referrer;
            isRegistered[msg.sender] = true;

            // if referrer has referrer, add it to caller's list of referrers
            if(referrersOf[referrer][0] != address(0)) { referrersOf[msg.sender][1] = referrersOf[referrer][0]; }
        }
    }

    /// @notice starts new sale round if conditions are met
    /// @dev relies on allowance from token seller
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

    /// @notice buys tokens during sale round
    /// @dev accepts ETH, determines how much can be bought, and returns ETH if sale limit is reached
    function buyACDM() external payable onlyDuring("sale", 1) onlyAfterStart nonReentrant {
        require(msg.value > 0, "Value is 0");

        PlatformSaleRound storage round = saleRounds[roundCount - 1];

        uint256 maxAmountToBuy = msg.value / round.price * 10**18;
        uint256 lastAvailableAmount = round.volumeAvailable - round.volumeTransacted;

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

    /// @notice starts new trade round if conditions are met
    /// @dev can be started if all sale round tokens are sold or round time expires
    function startTradeRound() external onlyDuring("sale", 0) onlyAfterStart onlyOwner {
        // close sale round if it wasn't closed before but time expired
        if((block.timestamp >= (saleRounds[roundCount - 1].startedAt + ROUND_TIME)) && !saleRounds[roundCount - 1].hasEnded) { closeSaleRoundAndBurn(); }

        require(saleRounds[roundCount - 1].hasEnded, "Trade round can't get started" );

        PlatformTradeRound memory newRound = PlatformTradeRound({
            startedAt: block.timestamp,
            volumeTransacted: 0,
            hasEnded: false
        });

        tradeRounds[roundCount++] = newRound;

        emit RoundStarted("Trade", 0);
    }

    /// @notice adds order to ongoing trade round
    /// @dev relies on allowance from token seller
    /// @param amount - amount to token to be sold
    /// @param price - price of token in ETH
    function addOrder(uint256 amount, uint256 price) external onlyDuring("trade", 1) {
        (bool success,) = TOKEN.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount));
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

    /// @notice removes order from ongoing trade round
    /// @dev returns tokens to seller
    /// @param id - id of order destined for removal 
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

    /// @notice accepts ETH and triggers token purchase
    /// @dev called by buyer, can be redeemed partially
    /// @param id - id of order within latest trade round 
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
        } else {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, orders[id].volumeAvailable));
            uint256 ethToReturn = msg.value - (orders[id].volumeAvailable * orders[id].price) / 10**18;
            payable(msg.sender).transfer(ethToReturn);

            emit TokenBought(msg.sender, orders[id].volumeAvailable);
            rewardReferrers(msg.sender, msg.value - ethToReturn, 25, 25);

            orders[id].volumeTransacted += orders[id].volumeAvailable;
            tradeRounds[roundCount - 1].volumeTransacted += msg.value - ethToReturn;
            orders[id].volumeAvailable = 0;
        }
    }

    /// @notice calculates quantity of tokens for sale
    /// @dev determined by volume of previous round / new price
    /// @param newPrice - price per token in ETH
    /// @return volume of tokens sold during upcoming sale round
    function getSaleRoundVolume(uint256 newPrice) private view returns(uint256) {
        return roundCount == 0 
            ? 100000 * 10**18 
            : tradeRounds[roundCount - 1].volumeTransacted / newPrice * 10**18;
    }

    /// @notice calculates current token price depending on round
    /// @dev initial price is 0.00001 ether, then it scales according to a formula
    /// @return amount of ETH per token
    function getNewSaleRoundPrice() private view returns(uint256) {
        return roundCount == 0 
            ? 0.00001 ether 
            : (saleRounds[roundCount - 2].price * 103) / 100 + 0.000004 ether
        ;
    }

    /// @notice sends ETH to referral's referrers if they exist
    /// @param referral - address whose referrers to award 
    /// @param value - amount of ETH that was used to purchase tokens 
    /// @param reward0 - percentage multiplied by ten, e.g. 2.5% is 25, commission sent to immediate referrer
    /// @param reward0 - percentage multiplied by ten, e.g. 2.5% is 25, commission sent to distant referrer
    function rewardReferrers(address referral, uint256 value, uint8 reward0, uint8 reward1) private {
        if(referrersOf[referral][0] != address(0) && referrersOf[referral][1] == address(0)) {
            payable(referrersOf[referral][0]).transfer(value * reward0 / 1000);
        } else if (referrersOf[referral][1] != address(0)) {
            payable(referrersOf[referral][0]).transfer(value * reward0 / 1000);
            payable(referrersOf[referral][1]).transfer(value * reward1 / 1000);
        }
    }

    /// @notice determines if round has ended
    /// @param roundType - round type used to determine what piece of state to modify 
    /// @return true if round hs ended, false if it hasn't
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

    /// @notice close sale round and burn unsold tokens
    function closeSaleRoundAndBurn() private {
        PlatformSaleRound memory previousSaleRound = saleRounds[roundCount - 1];
        
        if(previousSaleRound.volumeAvailable - previousSaleRound.volumeTransacted > 0) {
            emit RoundEnded("Sale", previousSaleRound.price);
            TOKEN.call(abi.encodeWithSignature("burn(uint256)", previousSaleRound.volumeAvailable - previousSaleRound.volumeTransacted));
        }

        saleRounds[roundCount - 1].hasEnded  = true;
    }

    /// @notice get all orders existing within trade round 
    /// @param id - round id
    /// @return orders returns all existing orders assigned to round
    function getOrdersByRoundId(uint256 id) external view onlyDuring("trade", 1) onlyOwner returns(UserTradeOrder[] memory orders) {
        require(id > 0 && id < roundCount, "Incorrect id");
        orders = tradeOrders[id];
    }
    
    /// @notice assigns unredeemed existing orders to new round
    /// @dev no other way to bind array to new map key
    /// @param orders - orders from previous round that are supposed to be continued 
    function transferOrdersToCurrentTradeRound(UserTradeOrder[] calldata orders) external onlyDuring("trade", 1) onlyOwner {
        for (uint256 i = 0; i < orders.length; i++) {
            tradeOrders[roundCount - 1].push(orders[i]);
        }
    }
}