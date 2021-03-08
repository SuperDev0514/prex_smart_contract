
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/openzeppelin-solidity/ownership/Ownable.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMarketRegistry.sol";
import "./interfaces/IChainLinkOracle.sol";

contract Market is Ownable {
  using SafeMath for *;

  enum Option {
    Bearish,
    Netural,
    Boolish
  }
  
  struct MarketData {
    uint64 startTime;
    uint64 predictionTime;
    uint64 endTime;
    uint64 neutralMinValue;
    uint64 neutralMaxValue;
  }

  struct MarketResult {
    uint64 winningOption;
    uint256 totalReward;
  }

  struct UserData {
    mapping(uint => uint256) assetStaked;
    bool claimedReward;
  }
    
  bytes32 public constant marketCurrency = "ETH/USDT";
  
  address constant PRICE_FEED_ADDRESS = 0x9326BFA02ADD2366b30bacB125260Af641031331;
  address constant ASSET_ADDRESS = 0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa;
  uint256 constant MIN_STAKE_AMOUNT = 1;
  uint constant COMMISSION_PERCENTAGE = 10; //with 2 decimals
  uint constant TOTAL_OPTIONS = 3;

  uint256 totalCommissionAmount;

  IMarketRegistry constant marketRegistry = IMarketRegistry(0x65Add15C5Ff3Abc069358AAe842dE13Ce92f3447);
  IERC20 assetToken = IERC20(ASSET_ADDRESS);
  
  MarketData public marketData;
  mapping(address => UserData) internal userData;
  mapping(uint => uint256) internal optionsStaked;

  /**
    * @dev Initialize the market.
    * @param _startTime The time at which market will create.
    * @param _duration The time duration of market.
    * @param _minValue The minimum value of neutral option range.
    * @param _maxValue The maximum value of neutral option range.
    */
  function initiate(uint64 _startTime, uint64 _duration, uint64 _minValue, uint64 _maxValue) public payable onlyOwner {
    require(marketData.startTime == 0, "Already initialized");
    require(_startTime.add(_predictionTime) > now);
    marketData.startTime = _startTime;
    marketData.predictionTime = _startTime.add(_duration);
    marketData.endTime = arketData.endTime.add(_duration);
    marketData.neutralMinValue = _minValue;
    marketData.neutralMaxValue = _maxValue;
  }

  /**
    * @dev Place prediction on the available options of the market.
    * @param _predictionStake The amount staked by user at the time of prediction.
    * @param _prediction The option on which user placed prediction.
    * @param _leverage The leverage opted by user at the time of prediction.
    */
  function placePrediction(uint256 _stakeAmount, uint256 _option) public payable {
    require(_option <= TOTAL_OPTIONS && _stakeAmount >= MIN_STAKE_AMOUNT);
    require(now >= marketData.startTime && now <= marketData.predictionTime);

    require(msg.value == 0);
    assetToken.transferFrom(msg.sender, address(this), _stakeAmount);
    uint256 memory commissionAmount = _calculatePercentage(COMMISSION_PERCENTAGE, _stakeAmount, 10000);
    totalCommissionAmount = totalCommissionAmount.add(commissionAmount);
    _stakeAmount = _stakeAmount.sub(commissionAmount);

    require(_stakeAmount > 0);

    _storePredictionData(_option, _stakeAmount);
  }
  
  /**
    * @dev Calculate the result of market.
    * @param _value The current price of market currency.
    */
  function _postResult(uint256 _value, uint256 _roundId) internal {
    require(marketData.endTime < now, "Time not reached");
    require(_value > 0,"value should be greater than 0");
    
    uint memory i;

    if(_value < marketData.neutralMinValue) {
      marketResult.winningOption = Option.Bearish;
    } else if(_value > marketData.neutralMaxValue) {
      marketResult.winningOption = Option.Boolish;
    } else {
      marketResult.winningOption = Option.Neutral;
    }
    if (optionsStaked[marketResult.winningOption] > 0) {
      for(i = 0; i < totalOptions; i++){
        if(i != marketResult.winningOption) {
          marketResult.totalReward = marketResult.totalReward.add(optionsStaked[i]);
        }
      }
    }
  }

  function _calculatePercentage(uint256 _percent, uint256 _value, uint256 _divisor) internal pure returns(uint256) {
    return _percent.mul(_value).div(_divisor);
  }

  /**
    * @dev Stores the prediction data.
    * @param _option The option on which user place prediction.
    * @param _stakeAmount The amount staked by user at the time of prediction.
    */
  function _storePredictionData(uint _option, uint _stakeAmount) internal {
    userData[msg.sender].assetStaked[_option] = userData[msg.sender].assetStaked[_option].add(_stakeAmount);
    optionsStaked[_option] = optionsStaked[_option].add(_stakeAmount);
  }
  
  /**
    * @dev Settle the market, setting the winning option
    */
  function endMarket() external onlyOwner {
    require(marketData.endTime < now)
    (uint256 _value, uint256 _roundId) = marketUtility.getEndingPrice();
    _postResult(_value, _roundId);
  }

  /**
    * @dev Get price of provided feed address
    **/
  function getEndingPrice() public view returns (uint256 latestAnswer, uint256 roundId) {
    require(marketData.endTime < now)
    int256 currentRoundAnswer;
    uint80 currentRoundId;
    uint256 currentRoundTime;
    uint256 endTime = marketData.endTime;
    (currentRoundId, currentRoundAnswer, , currentRoundTime, )= IChainLinkOracle(PRICE_FEED_ADDRESS).latestRoundData();
    while(currentRoundTime > endTime) {
      currentRoundId--;
      (currentRoundId, currentRoundAnswer, , currentRoundTime, )= IChainLinkOracle(PRICE_FEED_ADDRESS).getRoundData(currentRoundId);
      if(currentRoundTime <= endTime) {
        break;
      }
    }
    return
      (uint256(currentRoundAnswer), currentRoundId);
  }

  /**
    * @dev Claim the return amount of the specified address.
    * @param _user The address to query the claim return amount of.
    * @return Flag, if 0:cannot claim, 1: Already Claimed, 2: Claimed
    */
  function claimReturn(address payable _user) public returns(uint256) {

    if(userData[_user].claimedReward) {
      return 1;
    }
    userData[_user].claimedReward = true;
    uint256 memory _returnAmount = getReturn(_user);
    _transferAsset(ASSET_ADDRESS, _user, _returnAmount);
    return 2;
  }

  /**
    * @dev Transfer the assets to specified address.
    * @param _asset The asset transfer to the specific address.
    * @param _recipient The address to transfer the asset of
    * @param _amount The amount which is transfer.
    */
  function _transferAsset(address _asset, address payable _recipient, uint256 _amount) internal {
    if(_amount > 0) { 
      if(_asset == ETH_ADDRESS) {
        _recipient.transfer(_amount);
      } else {
        require(IToken(_asset).transfer(_recipient, _amount));
      }
    }
  }

  /**
  * @dev Gets the return amount of the specified address.
  * @param _user The address to specify the return of
  * @return returnAmount uint256 memory representing the return amount.
  */
  function getReturn(address _user) public view returns (uint256) {
    return userData[_user].assetStaked[marketResult.winningOption].mul(marketResult.totalReward).div(optionsStaked[marketResult.winningOption]);
  }  
}