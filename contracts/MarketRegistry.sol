
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/openzeppelin-solidity/ownership/Ownable.sol";
import "./interfaces/IChainLinkOracle.sol";
import "./Market.sol";

contract MarketRegistry is Ownable {

  using SafeMath for *; 

  struct MarketPair {
    string name;
    address feedAddress;
    uint256 decimal;
    uint256 totalRounds;
  }

  struct MarketInfo {
    address addr;
    // uint256 pair;
    // uint256 roundId;
    // uint256 startTime;
    // uint256 endTime;
    // uint256 startPrice;
    // uint256 endPrice;
    // uint256 totalUsers;
    // uint256 totalStaked;
    // uint256 winningOption;
  }

  MarketPair[] public marketPairs;
  MarketInfo[] public markets;
  
  constructor () public {
    marketPairs.push(MarketPair("ETH/USD", 0x9326BFA02ADD2366b30bacB125260Af641031331, 9, 0));
    marketPairs.push(MarketPair("BTC/USD", 0x6135b13325bfC4B00278B4abC5e20bbce2D6580e, 9, 0));
  }

  /**
    * @dev Register the new market
    * @param _pair The value pair of market.
    */
  function registerMarket(uint256 _pair) external returns (uint256) {
    require(_pair >= 0 && _pair < marketPairs.length, "Invalid market pair.");

    markets.push(MarketInfo(msg.sender));
    uint256 _roundId = marketPairs[_pair].totalRounds;
    marketPairs[_pair].totalRounds++;

    emit MarketCreated(_pair, _roundId, msg.sender);
    return _roundId;
  }

  /**
    * @dev Create a new market
    * @param _pair The value pair of market.
    * @param _startTime The time at which market will create.
    * @param _duration The time duration of market.
    */
  function createMarket(uint256 _pair, uint256 _startTime, uint256 _duration) external {
    require(_pair >= 0 && _pair < marketPairs.length, "Invalid market pair.");
    uint256 _roundId = marketPairs[_pair].totalRounds;
    Market market = new Market(_pair, _roundId, _startTime, _duration);
    address _marketAddress = address(market);

    markets.push(MarketInfo(_marketAddress));
    marketPairs[_pair].totalRounds++;
    market.transferOwnership(msg.sender);

    emit MarketCreated(_pair, _roundId, msg.sender);
  }

  /**
    * @dev Get price of the specified time and pair
    * @param _time The time when to get price.
    * @param _pair The pair id which to get price.
    */
  function getPairPrice(uint256 _time, uint256 _pair) external view returns (uint256) {
    require(_time <= block.timestamp, "It's not time yet to get the price.");
    require(_pair >= 0 && _pair < marketPairs.length, "Invalid market pair.");
        
    address priceFeedAddress = marketPairs[_pair].feedAddress;
    int256 currentRoundAnswer;
    uint80 currentRoundId;
    uint256 currentRoundTime;
    (currentRoundId, currentRoundAnswer, , currentRoundTime, ) = IChainLinkOracle(priceFeedAddress).latestRoundData();
    while(currentRoundTime > _time) {
      currentRoundId--;
      (currentRoundId, currentRoundAnswer, , currentRoundTime, ) = IChainLinkOracle(priceFeedAddress).getRoundData(currentRoundId);
      if(currentRoundTime <= _time) {
        break;
      }
    }
    return uint256(currentRoundAnswer);
  }

  /**
    * @dev Provide markets pagination.
    * @param from Page start index from back.
    * @param cnt Page size.
  */
  function getMarkets(uint256 from, uint256 cnt) public view returns(address[] memory _markets) {
    uint256 marketCnt = markets.length;
    require(marketCnt > from, "No result");
    uint256 realCnt = marketCnt.sub(from);
    if (realCnt > cnt)
      realCnt = cnt;

    _markets = new address[](realCnt);
    uint256 k = marketCnt.sub(from + 1);
    uint256 i;
    for (i = 0; i < realCnt; i++) {
      _markets[i] = markets[k--].addr;
    }
  }

  /**
  * @dev Get registry data.
  */
  function getRegistryData() external view returns(uint256 _nPairs, uint256 _time) {
    _nPairs = marketPairs.length;
    _time = block.timestamp;
  }

  /**
  * @dev Get market list.
  */
  function getMarketList() external view returns(address[] memory _markets) {
    _markets = new address[](markets.length);
    for (uint256 i = 0; i < markets.length; i++) {
      _markets[i] = markets[i].addr;
    }
  }

  /**
  * @dev Get current time of contract
  */
  function getCurrentTime() external view returns (uint256) {
    return block.timestamp;
  }

  /**
  * @dev Emitted by registering a new market
  */
  event MarketCreated (
    uint256 marketPair,
    uint256 roundId,
    address marketAddress
  );

}