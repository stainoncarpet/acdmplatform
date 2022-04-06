//SPDX-License-Identifier: MIT

pragma solidity >=0.8.12 <0.9.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ACDMPlatform is Ownable {
    enum RoundMode { NONE, SALE, TRADE }
    enum OrderType { NONE, SELL, BUY }

    struct Round { 
        RoundMode mode;
        uint256 startedAt; 
        uint256 price; 
        uint256 volumeAvailable; 
        uint256 volumeTransacted; 
        bool hasEnded;
    }

    struct Order { OrderType otype; }

    event RoundStarted(string indexed mode,uint256 indexed price);

    address public immutable TOKEN;
    uint256 public immutable ROUND_TIME;
    mapping(address => address[]) public referrersOf; // item0 - direct referrer, item1 - referrer of referrer
    mapping(address => bool) public isRegistered;
    Round[] public rounds;

    constructor(address token, uint256 roundTime) {
        TOKEN = token;
        ROUND_TIME = roundTime;
    }

    modifier onlyDuringSale() {
        if(rounds.length > 0) {
            Round memory round = rounds[rounds.length - 1];
            require(!round.hasEnded, "Round has ended");
            require(round.mode == RoundMode.SALE, "Allowed only during sale periods");
        }
        _;
    }

    modifier onlyDuringTrade() {
        if(rounds.length > 0) {
            Round memory round = rounds[rounds.length - 1];
            require(!round.hasEnded, "Round has ended");
            require(round.mode == RoundMode.TRADE || rounds.length == 0, "Allowed only during trading periods");
        }
        _;
    }

    function register(address referrer) external {
        require(!isRegistered[msg.sender], "Already registered");
        require(msg.sender != referrer, "Can't register oneself as referrer");

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
    // в начале sale-раунда мы минтим необходимую сумму токенов на контракт
    function startSaleRound() external onlyDuringTrade onlyOwner {
        uint256 newPrice = getNewPrice();
        uint256 mintedAmount = getVolumeAvailable(newPrice);

        TOKEN.call(abi.encodeWithSignature("mint(uint256)", mintedAmount));

        Round memory newRound = Round({
            mode: RoundMode.SALE,
            startedAt: block.timestamp,
            price: newPrice,
            volumeAvailable: mintedAmount,
            volumeTransacted: 0,
            hasEnded: false
        });
        rounds.push(newRound);

        emit RoundStarted("Sale", newRound.price);
    }

    // нужно использовать модификатор noreentrancy
    function buyACDM() external payable onlyDuringSale {
        require(msg.value > 0, "Value is 0");

        Round storage currentRound = rounds[rounds.length - 1];

        uint256 fullAmountToBuy = msg.value / currentRound.price * 10**18;
        uint256 lastAvailableAmount = currentRound.volumeAvailable - currentRound.volumeTransacted;

        if(lastAvailableAmount > fullAmountToBuy) {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, fullAmountToBuy));
            currentRound.volumeTransacted += fullAmountToBuy;
        } else if (lastAvailableAmount == fullAmountToBuy) {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, fullAmountToBuy));
            currentRound.volumeTransacted = currentRound.volumeAvailable;
            currentRound.hasEnded = true;
        } else {
            TOKEN.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, lastAvailableAmount));
            currentRound.volumeTransacted = currentRound.volumeAvailable;
            uint256 ethToReturn = msg.value - lastAvailableAmount * currentRound.price;
            payable(msg.sender).transfer(ethToReturn);
            currentRound.hasEnded = true;
        }

        address[] memory refs = referrersOf[msg.sender];

        if(refs.length == 1) {
            payable(refs[0]).transfer(msg.value * 5 / 100);
        } else if (refs.length == 2) {
            payable(refs[0]).transfer(msg.value * 5 / 100);
            payable(refs[1]).transfer(msg.value * 3 / 100);
        }
    }

    // some time passes
    // TRADE @6:00
    // если с сейл раунда остались токены мы их сжигаем
    // не может закончиться раньше чем 3 дня
    // если никто не купил или никто ордер не создавал мы стартуем и сразу заканчиваем sale-раунд
    // как только в сейл-раунде закончатся токены или по истечению 3 дней мы сможем запустить trade-раунд
    // function startTradeRound() external onlyDuringSale onlyOwner {
        // Round memory currentRound = rounds[rounds.length - 1];

        // require(
        //     currentRound.mode == RoundMode.SALE
        //         && (
        //             (currentRound.volumeTransacted >= currentRound.volumeAvailable) 
        //                 ||  block.timestamp >= (currentRound.startedAt + ROUND_TIME)
        //         )
        // );
    // }

    // // can be of buy or sell types
    // если ордер никто не купил и он не отменился: то токены должны перейти на след раунд, изначальная цена остается
    // function addOrder() external onlyDuringTrade {

    // }

    // function removeOrder() external onlyDuringTrade {

    // }

    // // можно выкупить частично
    // function redeemOrder() external payable onlyDuringTrade {

    // }

    // qty of sold t0kens is determined by volume of previous round / new price 
    function getVolumeAvailable(uint256 newPrice) private view returns(uint256) {
        return rounds.length == 0 
            ? 100000 * 10**18
            : rounds[rounds.length - 1].volumeTransacted / newPrice
        ;
    }

    function getNewPrice() private view returns(uint256) {
        return rounds.length == 0 
            ? 0.00001 ether 
            : (rounds[rounds.length - 1].price * 103) / 100 + 0.000004 ether
        ;
    }
}
