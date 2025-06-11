// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error CarbonTrader_NotOwner();
error CarbonTrader_ParamError();
error CarbonTrader_TransferFailed();

contract CarbonTrader {
    struct trade {
        address seller;
        uint256 sellAmount;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 minimumBidAmount;
        uint256 initPriceOfunit;
        mapping(address => uint256) deposits;
        mapping(address => string) bidInfos;
        mapping(address => string) bidSecrets;
    }

    mapping(address => uint256) private s_addressToAllowances;
    mapping(address => uint256) private s_fronzeAllowances;
    mapping(string => trade) private s_trade;
    mapping(address => uint256) private s_auctionAmount;

    address private immutable i_owner;
    IERC20 private immutable i_usdtToken;

    constructor(address usdtTokenAddress) {
        i_owner = msg.sender;
        i_usdtToken = IERC20(usdtTokenAddress);
    }

    modifier onlyOwner() {
        if (msg.sender != i_owner) {
            revert CarbonTrader_NotOwner();
        }
        _;
    }

    function issueAllowance(address user, uint256 amount) public onlyOwner {
        s_addressToAllowances[user] += amount;
    }

    function getAllowance(address user) public view returns (uint256) {
        return s_addressToAllowances[user];
    }

    function freezeAllowance(
        address user,
        uint256 freezedAmount
    ) public onlyOwner {
        s_addressToAllowances[user] -= freezedAmount;
        s_fronzeAllowances[user] += freezedAmount;
    }

    function unfreezeAllowance(
        address user,
        uint256 freezedAmount
    ) public onlyOwner {
        s_addressToAllowances[user] += freezedAmount;
        s_fronzeAllowances[user] -= freezedAmount;
    }

    function getFrozenAllowance(address user) public view returns (uint256) {
        return s_fronzeAllowances[user];
    }

    function destoryAllowance(
        address user,
        uint256 destoryAmount
    ) public onlyOwner {
        s_addressToAllowances[user] -= destoryAmount;
    }

    function destoryAllowance(address user) public onlyOwner {
        s_addressToAllowances[user] = 0;
        s_fronzeAllowances[user] = 0;
    }

    function startTrade(
        string memory tradeId,
        uint256 amount,
        uint256 startTimestamp,
        uint256 endTimeStamp,
        uint256 miniumimBidAmount,
        uint256 initPriceOfUnit
    ) public {
        if (
            amount <= 0 ||
            startTimestamp >= endTimeStamp ||
            miniumimBidAmount <= 0 ||
            initPriceOfUnit <= 0 ||
            miniumimBidAmount > amount
        ) revert CarbonTrader_ParamError();
        trade storage newTrade = s_trade[tradeId];
        newTrade.seller = msg.sender;
        newTrade.sellAmount = amount;
        newTrade.startTimestamp = startTimestamp;
        newTrade.endTimestamp = endTimeStamp;
        newTrade.minimumBidAmount = miniumimBidAmount;
        newTrade.initPriceOfunit = initPriceOfUnit;

        s_addressToAllowances[msg.sender] -= amount;
        s_fronzeAllowances[msg.sender] += amount;
    }

    function getTrade(
        string memory tradeId
    )
        public
        view
        returns (address, uint256, uint256, uint256, uint256, uint256)
    {
        trade storage curTrade = s_trade[tradeId];
        return (
            curTrade.seller,
            curTrade.sellAmount,
            curTrade.startTimestamp,
            curTrade.endTimestamp,
            curTrade.minimumBidAmount,
            curTrade.initPriceOfunit
        );
    }

    function deposit(
        string memory tradeId,
        uint256 amount,
        string memory info
    ) public {
        trade storage curTrade = s_trade[tradeId];
        bool success = i_usdtToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );

        if (!success) revert CarbonTrader_TransferFailed();

        curTrade.deposits[msg.sender] = amount;
        setBidInfo(tradeId, info);
    }

    function setBidInfo(string memory tradeID, string memory info) public {
        trade storage curTrade = s_trade[tradeID];
        curTrade.bidInfos[msg.sender] = info;
    }

    function refundDeposit(stirng memory tradeID) public {
        trade storage curTrade = s_trade[tradeID];
        uint256 depositAmount = curTrade.deposits[msg.sender];
        curTrade.deposits[msg.sender] = 0;

        bool success = i_usdtToken.transfer(msg.sender, depositAmount);

        if (!success) {
            curTrade.deposits[msg.sender] = depositAmount;
            revert CarbonTrader_TransferFailed();
        }
    }

    function setBidSecret(string memory tradeID, string memory secret) public {
        trade storage curTrade = s_trade[tradeID];
        curTrade.bidSecrets[msg.sender] = secret;
    }

    function getBidSecret(
        string memory tradeID
    ) public view returns (string memory) {
        trade storage curTrade = s_trade[tradeID];
        return curTrade.bidInfos[msg.sender];
    }

    function finalizeAuctionAndTransferCarbon(
        string memory tradeID,
        uint256 allowanceAmount,
        uint256 addtionalAmountToPay
    ) public {
        // 获取保证金
        uint256 depositAmount = s_trade[tradeID].deposits[msg.sender];
        s_trade[tradeID].deposits[msg.sender] = 0;
        // 把保证金和新补的这些钱给卖家
        address seller = s_trade[tradeID].seller;
        s_auctionAmount[seller] += (depositAmount + addtionalAmountToPay);
        // 扣除卖家的碳额度
        s_fronzeAllowances[seller] = 0;
        // 增加买家的碳额度
        s_addressToAllowances[msg.sender] += allowanceAmount;

        bool success = i_usdtToken.transferFrom(
            msg.sender,
            address(this),
            addtionalAmountToPay
        );
        if (!success) revert CarbonTrader_TransferFailed();
    }

    function withdrawAcutionAmount() public {
        uint256 auctionAmount = s_auctionAmount[msg.sender];
        s_auctionAmount[msg.sender] = 0;

        bool success = i_usdtToken.transfer(msg.sender, auctionAmount);

        if (!success) {
            s_auctionAmount[msg.sender] = auctionAmount;
            revert CarbonTrader_TransferFailed();
        }
    }
}
