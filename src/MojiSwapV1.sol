// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

import "lib/solady/src/auth/Ownable.sol";

// TODO: Events, final pricing model,

contract MojiSwapV1 is Ownable {
    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    uint256 public subjectFeePercent;

    uint64 public constant LOWEST_EMOJI = 0xf0000000;
    uint64 public constant HIGHEST_EMOJI = 0xe2000000;

    event Trade(
        address trader,
        uint64 emoji,
        bool isBuy,
        uint256 shareAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 supply
    );

    // EmojiSubject => (Holder => Balance)
    mapping(uint64 => mapping(address => uint256)) public emojiBalance;

    // EmojiSubject => Supply
    mapping(uint64 => uint256) public emojiSupply;

    constructor() {
        _initializeOwner(msg.sender);
    }

    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1) * (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }

    function getBuyPrice(uint64 emojiSubject, uint256 amount) public view returns (uint256) {
        return getPrice(emojiSupply[emojiSubject], amount);
    }

    function getSellPrice(uint64 emojiSubject, uint256 amount) public view returns (uint256) {
        return getPrice(emojiSupply[emojiSubject] - amount, amount);
    }

    function getBuyPriceAfterFee(uint64 emojiSubject, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 price = getBuyPrice(emojiSubject, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        return price + protocolFee;
    }

    function getSellPriceAfterFee(uint64 emojiSubject, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 price = getSellPrice(emojiSubject, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        return price - protocolFee - subjectFee;
    }

    function buyShares(uint64 emojiSubject, uint256 amount) public payable {
        uint256 supply = emojiSupply[emojiSubject];
        require(
            supply > 0 || owner() == msg.sender, "Only the shares' subject can buy the first share"
        );
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        require(msg.value >= price + protocolFee + subjectFee, "Insufficient payment");
        emojiBalance[emojiSubject][msg.sender] = emojiBalance[emojiSubject][msg.sender] + amount;
        emojiSupply[emojiSubject] = supply + amount;
        /*emit Trade(
            msg.sender, emojiSubject, true, amount, price, protocolFee, subjectFee, supply + amount
        );
        */
        (bool success1,) = protocolFeeDestination.call{value: protocolFee}("");
        require(success1, "Unable to send funds");
    }

    function sellShares(uint64 emojiSubject, uint256 amount) public payable {
        uint256 supply = emojiSupply[emojiSubject];
        require(supply > amount, "Cannot sell the last share");
        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        require(emojiBalance[emojiSubject][msg.sender] >= amount, "Insufficient shares");
        emojiBalance[emojiSubject][msg.sender] = emojiBalance[emojiSubject][msg.sender] - amount;
        emojiSupply[emojiSubject] = supply - amount;
        /*emit Trade(
            msg.sender, emojiSubject, false, amount, price, protocolFee, subjectFee, supply - amount
        );
        */
        (bool success1,) = msg.sender.call{value: price - protocolFee - subjectFee}("");
        (bool success2,) = protocolFeeDestination.call{value: protocolFee}("");
        require(success1 && success2, "Unable to send funds");
    }
}
