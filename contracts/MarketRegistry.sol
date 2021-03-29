
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/openzeppelin-solidity/ownership/Ownable.sol";
import "./interfaces/IChainLinkOracle.sol";

contract MarketRegistry is Ownable {

  using SafeMath for *; 

  struct MarketPair {
    string name;
    address feedAddress;
    uint256 decimal;
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
    marketPairs.push(MarketPair("ETH/USDT", 0x9326BFA02ADD2366b30bacB125260Af641031331, 9));
  }

  /**
    * @dev Register the new market
    */
  function registerMarket() external returns (uint256) {
    markets.push(MarketInfo(msg.sender));
    emit MarketCreated(markets.length - 1, msg.sender);
    return markets.length - 1;
  }

  /**
    * @dev Get price of the specified time and pair
    * @param _time The time when to get price.
    * @param _pair The pair id which to get price.
    */
  function getPairPrice(uint256 _time, uint256 _pair) external view returns (uint256) {
    require(_time > block.timestamp, "It's not time yet to get the price.");
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
  * @dev Get market registry data.
  */
  function getRegistryData() external view returns(uint256 _nPairs, address[] memory _markets) {
    uint256 i;
    _nPairs = marketPairs.length;
    _markets = new address[](markets.length);
    for (i = 0; i < markets.length; i++) {
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
    uint256 roundId,
    address marketAddress
  );

}