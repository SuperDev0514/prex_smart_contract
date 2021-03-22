
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/openzeppelin-solidity/ownership/Ownable.sol";
import "./external/openzeppelin-solidity/token/ERC20/IERC20.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMarketRegistry.sol";
import "./interfaces/IChainLinkOracle.sol";

contract Market is Ownable {
  using SafeMath for *;

  enum Option {
    Bullish,
    Neutral,
    Bearish
  }
  
  struct MarketData {
    uint256 startTime;
    uint256 predictionTime;
    uint256 endTime;
    uint256 neutralMinValue;
    uint256 neutralMaxValue;
    uint256 neutralRange;
  }

  struct MarketResult {
    uint256 winningOption;
    uint256 totalReward;
    uint256 startPrice;
    uint256 endPrice;
  }

  struct UserData {
    mapping(uint256 => uint256) assetStaked;
    bool claimedReward;
    bool available;
    uint256 returnAmount;
  }
    
  bytes32 public constant marketCurrency = "ETH/USDT";
  
  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address constant PRICE_FEED_ADDRESS = 0x9326BFA02ADD2366b30bacB125260Af641031331;
  address constant ASSET_ADDRESS = 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;
  uint256 constant MIN_STAKE_AMOUNT = 1;
  uint256 constant COMMISSION_PERCENTAGE = 10; //with 2 decimals
  uint256 constant totalOptions = 3;

  uint256 totalCommissionAmount;

  IMarketRegistry marketRegistry;
  IERC20 assetToken = IERC20(ASSET_ADDRESS);
  
  MarketData public marketData;
  MarketResult public marketResult;
  uint256 totalUsers;
  mapping(uint256 => address) internal users;
  mapping(address => UserData) internal userData;
  mapping(uint256 => uint256) internal optionsStaked;

  /**
    * @dev Initialize the market.
    * @param _startTime The time at which market will create.
    * @param _duration The time duration of market.
    * @param _neutralRange The neutral option range.
    */
  function initiate(uint256 _startTime, uint256 _duration, uint256 _neutralRange, address registry) external onlyOwner {
    require(marketData.startTime == 0, "Already initialized");
    require(_startTime.add(_duration) > now);
    marketData.startTime = _startTime;
    marketData.predictionTime = _startTime.add(_duration);
    marketData.endTime = marketData.predictionTime.add(_duration);
    marketData.neutralRange = _neutralRange;
    marketResult.winningOption = totalOptions;
    marketRegistry = IMarketRegistry(registry);
    marketRegistry.registerMarket();
    emit MarketCreated(marketData.startTime, marketData.predictionTime, marketData.endTime);
  }

  /**
    * @dev Place prediction on the available options of the market.
    * @param _stakeAmount The amount staked by user at the time of prediction.
    * @param _option The option on which user placed prediction.
    */
  function placePrediction(uint256 _stakeAmount, uint256 _option) external payable {
    require(_option < totalOptions, "Option is invalid");
    require(_stakeAmount >= MIN_STAKE_AMOUNT, "Too small amount");
    require(now >= marketData.startTime, "Market has not started yet");
    require(now <= marketData.predictionTime, "Market prediction has expried.");

    require(msg.value == 0, "Not allowed transaction value.");
    assetToken.transferFrom(msg.sender, address(this), _stakeAmount);
    uint256 commissionAmount = _calculatePercentage(COMMISSION_PERCENTAGE, _stakeAmount, 10000);
    totalCommissionAmount = totalCommissionAmount.add(commissionAmount);
    uint256 realAmount = _stakeAmount;
    realAmount = realAmount.sub(commissionAmount);

    require(realAmount > 0, "Amount is zero");
    _storePredictionData(_option, realAmount);

    uint256[] memory totalStaked = new uint256[](totalOptions);
    for (uint256 i = 0; i < totalOptions; i++) {
      totalStaked[i] = optionsStaked[i];
    }

    emit PredictionDataUpdated(totalUsers, totalStaked);
  }
  
  /**
    * @dev Calculate the result of market.
    * @param _value The current price of market currency.
    */
  function _postResult(uint256 _value) internal {
    require(marketData.endTime < now, "Time not reached");
    require(_value > 0,"value should be greater than 0");
    
    uint256 i;

    if(_value < marketData.neutralMinValue) {
      marketResult.winningOption = uint256(Option.Bearish);
    } else if(_value > marketData.neutralMaxValue) {
      marketResult.winningOption = uint256(Option.Bullish);
    } else {
      marketResult.winningOption = uint256(Option.Neutral);
    }
    if (optionsStaked[marketResult.winningOption] > 0) {
      for(i = 0; i < totalOptions; i++){
        marketResult.totalReward = marketResult.totalReward.add(optionsStaked[i]);
      }
    }
    for (i = 0; i < totalUsers; i++) {
      claimReturn(users[i]);
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
  function _storePredictionData(uint256 _option, uint256 _stakeAmount) internal {
    if (userData[msg.sender].available == false) {
      delete userData[msg.sender];
      for (uint256 i = 0; i < totalOptions; i++) {
        userData[msg.sender].assetStaked[i] = 0;
      }
      userData[msg.sender].available = true;
      users[totalUsers] = msg.sender;
      totalUsers++;
    }
    userData[msg.sender].assetStaked[_option] = userData[msg.sender].assetStaked[_option].add(_stakeAmount);
    optionsStaked[_option] = optionsStaked[_option].add(_stakeAmount);
  }
  
  /**
    * @dev Settle the market, setting the winning option
    */
  function endMarket() external onlyOwner {
    require(marketData.endTime < now, "Market has not ended yet.");
    marketResult.endPrice = getPrice(marketData.endTime);
    _postResult(marketResult.endPrice);
    emit MarketEnded(marketResult.endPrice, marketResult.winningOption);
  }

  /**
    * @dev Get price of provided feed address
    **/
  function getPrice(uint256 _time) public view returns (uint256) {
    require(_time < now);
    int256 currentRoundAnswer;
    uint80 currentRoundId;
    uint256 currentRoundTime;
    (currentRoundId, currentRoundAnswer, , currentRoundTime, )= IChainLinkOracle(PRICE_FEED_ADDRESS).latestRoundData();
    while(currentRoundTime > _time) {
      currentRoundId--;
      (currentRoundId, currentRoundAnswer, , currentRoundTime, )= IChainLinkOracle(PRICE_FEED_ADDRESS).getRoundData(currentRoundId);
      if(currentRoundTime <= _time) {
        break;
      }
    }
    return uint256(currentRoundAnswer);
  }

  /**
    * @dev Claim the return amount of the specified address.
    * @param _user The address to query the claim return amount of.
    * @return Flag, if 0:cannot claim, 1: Already Claimed, 2: Claimed
    */
  function claimReturn(address _user) public returns(uint256) {

    if(userData[_user].claimedReward) {
      return 1;
    }
    userData[_user].claimedReward = true;
    uint256 _returnAmount = getReturn(_user);
    if (_returnAmount > 0) {
      _transferAsset(ASSET_ADDRESS, address(uint160(_user)), _returnAmount);
    }
    userData[_user].returnAmount = _returnAmount;
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
    if (optionsStaked[marketResult.winningOption] == 0) {
      return 0;
    }
    else {
      return userData[_user].assetStaked[marketResult.winningOption].mul(marketResult.totalReward).div(optionsStaked[marketResult.winningOption]);
    }
  }

  function getPredictionData() public view returns (uint256 totalParticipants, uint256[] memory totalStaked, uint256[] memory userStaked) {
    totalStaked = new uint256[](totalOptions);
    userStaked = new uint256[](totalOptions);
    totalParticipants = totalUsers;
    uint256 i;
    for(i = 0; i < totalOptions; i++) {
      totalStaked[i] = optionsStaked[i];
      if (userData[msg.sender].available)
        userStaked[i] = userData[msg.sender].assetStaked[i];
    }
  }

  function getCurrentTime() public view returns (uint256) {
    return now;
  }

  /**
    * @dev Start market
    */
  function startMarket() external onlyOwner returns (uint256 startPrice, uint256 neutralMinValue, uint256 neutralMaxValue) {
    require(marketResult.startPrice == 0, "Market already started");
    require(marketData.startTime <= now, "Before start time");

    marketResult.startPrice = getPrice(marketData.startTime);
    marketData.neutralMinValue = marketResult.startPrice.sub(marketData.neutralRange);
    marketData.neutralMaxValue = marketResult.startPrice.add(marketData.neutralRange);
    emit MarketStarted(marketResult.startPrice, marketData.neutralMinValue, marketData.neutralMaxValue);
    startPrice = marketResult.startPrice;
    neutralMinValue = marketData.neutralMinValue;
    neutralMaxValue = marketData.neutralMaxValue;
  }

  /**
    * @dev Clear market.
    */
  function clearMarket() public payable onlyOwner {
    for (uint256 i = 0; i < totalUsers; i++) {
      userData[users[i]].available = false;
    }
    delete marketData;
    delete marketResult;
    delete totalUsers;
    delete totalCommissionAmount;

    for (uint256 i = 0; i < totalOptions; i++) {
      optionsStaked[i] = 0;
    }
  }

  event MarketCreated (
    uint256 startTime,
    uint256 predictionTime,
    uint256 endTime
  );

  event MarketStarted (
    uint256 startPrice,
    uint256 neutralMinValue,
    uint256 neutralMaxValue
  );

  event PredictionDataUpdated (
    uint256 totalParticipants,
    uint256[] totalStaked
  );

  event MarketEnded (
    uint256 endPrice,
    uint256 winningOption
  );
}