// SPDX-License-Identifier: MIT

/*  A decentralized prediction market: This project can demonstrate how to create a 
    market where users can bet on the outcome of events and get paid out 
    automatically if their prediction is correct. */

pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract BettingSystem is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    mapping(address => uint) private balances;
    mapping(uint => address) private predictionToUser;

    uint private capacity = 10;
    uint[] private predictions = new uint[](capacity);

    uint private immutable deadline;
    uint public volume;
    bytes32 private immutable jobId;
    uint private immutable fee;
    address private winner;
    uint private size;

    uint constant MAX_VALUE = 2 ** 256 - 1;

    event Deposited(address user, uint amount);
    event Withdrawn(address user, uint amount);
    event BettingStarted(uint time);
    event BettingEnded(uint time);
    event WinnerChosen(address winner, uint time);
    event RequestVolume(bytes32 indexed requestId, uint volume);

    // open means people can still place bets,
    enum BettingState {
        OPEN,
        CLOSED,
        CALCULATING
    }
    BettingState bettingState;

    constructor() ConfirmedOwner(msg.sender) {
        bettingState = BettingState.OPEN;
        deadline = block.timestamp + 60 seconds;
        setChainlinkToken(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        setChainlinkOracle(0xCC79157eb46F5624204f47AB42b3906cAA40eaB7);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = 1 * 10 ** 17;
        size = 0;
    }

    modifier canWithdraw() {
        require(
            bettingState == BettingState.OPEN,
            "Cannot withdraw at this time"
        );
        require(
            balances[msg.sender] > 0,
            "Do not have enough funds to withdraw"
        );
        _;
    }

    modifier canDeposit() {
        require(
            bettingState == BettingState.OPEN,
            "Cannot deposit at this time"
        );
        require(msg.value > 0, "Must enter a positive number");
        _;
    }

    modifier canBet() {
        require(
            balances[msg.sender] > 0,
            "You need to put in money before you can bet"
        );
        _;
    }

    // should call receive
    function deposit() public payable canDeposit {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function timeLeft() public returns (uint) {
        if (block.timestamp >= deadline) {
            bettingState = BettingState.CLOSED;
            emit BettingStarted(block.timestamp);
            return 0;
        } else {
            return deadline - block.timestamp;
        }
    }

    function withdraw() public payable canWithdraw {
        (bool success, ) = payable(msg.sender).call{
            value: balances[msg.sender]
        }("");
        require(success, "Withdraw failed");
        emit Withdrawn(msg.sender, balances[msg.sender]);
        balances[msg.sender] = 0;
    }

    function requestVolumeData() public returns (bytes32 requestId) {
        bytes4 selector = this.fulfill.selector;
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            selector
        );

        req.add(
            "get",
            "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD"
        );
        req.add("path", "RAW,ETH,USD,VOLUME24HOUR");
        int timesAmount = 10 ** 18;
        req.addInt("times", timesAmount);

        return sendChainlinkRequest(req, fee);
    }

    function fulfill(
        bytes32 _requestId,
        uint _volume
    ) public recordChainlinkFulfillment(_requestId) {
        emit RequestVolume(_requestId, _volume);
        volume = _volume;
        bettingState = BettingState.CALCULATING;
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        (bool success, ) = payable(msg.sender).call{
            value: link.balanceOf(address(this))
        }("");
        require(success, "Link Withdraw Failed");
    }

    function declareWinner() public onlyOwner returns (address) {
        require(bettingState == BettingState.CALCULATING, "Waiting on Oracle");
        if (predictionToUser[volume] != address(0)) {
            winner = predictionToUser[volume];
        } else {
            uint min = MAX_VALUE;
            uint closest = predictions[0];
            for (uint i = 0; i < size; i++) {
                uint diff = volume - predictions[i];
                if (diff < min) {
                    min = diff;
                    closest = predictions[i];
                }
            }

            winner = predictionToUser[closest];
        }

        emit WinnerChosen(winner, block.timestamp);
        return winner;
    }

    function resizeArray() private {
        require(capacity - 1 == size, "Array is not full yet");
        capacity *= 2;
        uint[] memory newPredictions = new uint[](capacity);
        for (uint i = 0; i < size; i++) {
            newPredictions[i] = predictions[i];
        }
        predictions = newPredictions;
    }

    function setPrediction(uint _prediction) public {
        predictionToUser[_prediction] = msg.sender;
        predictions[size] = _prediction;
        size++;
    }

    function getWinner() external view returns (address) {
        return winner;
    }

    function getDeadline() external view returns (uint) {
        return deadline;
    }

    function getBettingState() external view returns (BettingState) {
        return bettingState;
    }

    function getBalanceOfUser(address user) external view returns (uint) {
        return balances[user];
    }

    function getBalanceOfContract() external view returns (uint) {
        return address(this).balance;
    }

    function getSizeOfBets() external view returns (uint) {
        return size;
    }

    receive() external payable {}
}
